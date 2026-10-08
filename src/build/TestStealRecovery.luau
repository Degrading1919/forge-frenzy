--[[
	Studio-only integration test of stolen-weapon recovery against the real ProfileStore and, when
	Studio has API access, real DataStores (an isolated store with fresh GUID keys; production and
	playtest saves are never touched).

	    return require(game.ServerStorage.Build.TestStealRecovery)()

	It drives the real WorkshopService ledger code with real profile sessions. Ending a session
	and starting a new one on the same key is how a player leaving one server and joining another
	looks to ProfileStore (session lock released and re-acquired), so these cases cover "a
	different server" as far as one Studio process can. It does not run two live servers at once.

	Cases:
	  A  The victim's save holds the outbox entry, the thief's save only the pending record, then
	     both sessions end (crash). The victim never plays again. The thief joins a new session and
	     collects the weapon from the victim's saved profile (GetAsync).
	  B  A delivery message is sent twice to the thief's key while the thief is offline; the thief
	     joins and the weapon is applied once; a later session sees one weapon and an empty queue.
	  C  A message arrives while the thief's session is active in this server.
	  D  The victim restarts after committing (outbox saved, nothing delivered): the victim's next
	     session re-sends, the thief's pending record also resolves, and only one copy results.
]]
return function(forceMock: boolean?)
	assert(game:GetService("RunService"):IsStudio(), "Studio-only test")
	local ServerScriptService = game:GetService("ServerScriptService")
	local root = ServerScriptService:WaitForChild("Server")
	local library = require(root:WaitForChild("Packages"):WaitForChild("ProfileStore"))
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local Economy = require(Shared:WaitForChild("Economy"))
	local ForgeMath = require(Shared.ForgeMath)
	local HttpService = game:GetService("HttpService")
	local started = os.clock()
	while library.DataStoreState == "NotReady" and os.clock() - started < 20 do
		task.wait(0.05)
	end
	local mock = forceMock == true or library.DataStoreState ~= "Access"
	local storeName = "ForgeFrenzy_StealRecovery_v1"
	local store = library.New(storeName, Economy.newProfile())
	if mock then
		store = store.Mock
	end

	local Workshop = require(root.Services.WorkshopService:Clone())
	local Data = require(root.Services.DataService:Clone())
	local Logic = Workshop.Logic
	local runId = HttpService:GenerateGUID(false):sub(1, 8)
	local keys, sessions, evidence = {}, {}, {}

	local function newPlayer(userId: number, name: string)
		keys[userId] = "Recovery_" .. runId .. "_" .. name
		return { UserId = userId, DisplayName = name, Name = name }
	end
	local function open(player)
		local profile = store:StartSessionAsync(keys[player.UserId], { Cancel = function() return os.clock() - started > 120 end })
		assert(profile, "Could not open " .. player.Name)
		profile:AddUserId(math.abs(player.UserId))
		Economy.reconcile(profile.Data)
		sessions[player] = profile
		Data._setForTest(player, profile.Data, profile)
		return profile
	end
	local function close(player)
		local profile = sessions[player]
		sessions[player] = nil
		Data._setForTest(player, nil)
		if profile then
			profile:EndSession()
			local deadline = os.clock() + 30
			while profile:IsActive() and os.clock() < deadline do
				task.wait(0.05)
			end
		end
	end
	local function saved(player)
		local view = store:GetAsync(keys[player.UserId])
		return if view then view.Data else {}
	end
	local function count(data, value)
		local n = 0
		for _, w in data.weapons or {} do
			if w.v == value then
				n += 1
			end
		end
		for _, entry in data.outbox or {} do
			if entry.w and entry.w.v == value then
				n += 1
			end
		end
		return n
	end
	local online = {}
	Workshop._reset()
	Workshop._inject({
		getProfile = function(player)
			local profile = sessions[player]
			return if profile and profile:IsActive() then profile.Data else nil
		end,
		markDirty = function() end,
		saveNow = function(player)
			return Data.saveNow(player, 30)
		end,
		sendMessage = function(userId, message)
			return store:MessageAsync(keys[userId], message)
		end,
		viewProfile = function(userId)
			local ok, view = pcall(store.GetAsync, store, keys[userId])
			if not ok then
				return nil
			end
			return if view then view.Data else {}
		end,
		playerByUserId = function(userId)
			for player in online do
				if player.UserId == userId then
					return player
				end
			end
			return nil
		end,
		now = function()
			return os.time()
		end,
		spawn = function(fn, ...)
			fn(...)
		end,
	})
	local function weapon(value: number)
		local w = ForgeMath.rollWeapon(Random.new(value), 3, 2, 1.5, { id = "", ts = os.time() })
		w.v = value
		return w
	end
	local function attachHandler(player, profile)
		profile:MessageHandler(function(message, processed)
			if Workshop.onMessage(player, profile.Data, message) then
				processed()
			end
		end)
	end

	local ok, err = pcall(function()
		-- A ---------------------------------------------------------------------------------------
		local victim, thief = newPlayer(-92001, "VictimA"), newPlayer(-92002, "ThiefA")
		local pv, pt = open(victim), open(thief)
		local w = weapon(777001)
		w.id = "w1"
		pv.Data.weapons.w1 = w
		pv.Data.showcase[1] = "w1"
		local id = "A-" .. runId
		Logic.markPending(pt.Data, id, victim.UserId, "w1", os.time())
		assert(Data.saveNow(thief, 30), "A: thief pending save unconfirmed")
		assert(Logic.beginTransfer(pv.Data, { weaponId = "w1", slot = 1, weapon = w } :: any, id, thief.UserId, "ThiefA", "VictimA", os.time()))
		assert(Data.saveNow(victim, 30), "A: victim commit save unconfirmed")
		-- crash before delivery: both sessions end with what they hold
		close(victim)
		close(thief)
		assert(count(saved(victim), 777001) == 1 and count(saved(thief), 777001) == 0, "A: one durable copy, in the victim's outbox")
		-- the thief joins a new session; the victim never returns
		pt = open(thief)
		Workshop.resolvePending(thief)
		assert(count(pt.Data, 777001) == 1 and next(pt.Data.xferPending) == nil and pt.Data.xferIn[id], "A: thief collected it from the victim's save")
		Workshop.resolvePending(thief)
		assert(count(pt.Data, 777001) == 1, "A: second resolve made no copy")
		close(thief)
		pt = open(thief)
		assert(count(pt.Data, 777001) == 1 and pt.Data.weapons[next(pt.Data.weapons)].st == 1, "A: survives a further restart")
		close(thief)
		table.insert(evidence, "A: victim never returned; the thief's next session collected the weapon from the victim's saved outbox (GetAsync), once")

		-- B ---------------------------------------------------------------------------------------
		local thiefB = newPlayer(-92003, "ThiefB")
		pt = open(thiefB) -- create the profile, then leave
		close(thiefB)
		local msg = { kind = "steal", id = "B-" .. runId, w = weapon(777002), from = "VictimB" }
		assert(store:MessageAsync(keys[thiefB.UserId], msg), "B: first message failed")
		assert(store:MessageAsync(keys[thiefB.UserId], msg), "B: duplicate message failed")
		pt = open(thiefB)
		attachHandler(thiefB, pt)
		local deadline = os.clock() + 10
		while count(pt.Data, 777002) == 0 and os.clock() < deadline do
			task.wait(0.1)
		end
		task.wait(1)
		assert(count(pt.Data, 777002) == 1, "B: duplicate message applied twice or not at all: " .. count(pt.Data, 777002))
		assert(Data.saveNow(thiefB, 30), "B: save after messages unconfirmed")
		close(thiefB)
		pt = open(thiefB)
		local requeued = 0
		pt:MessageHandler(function()
			requeued += 1
		end)
		task.wait(1)
		assert(count(pt.Data, 777002) == 1 and requeued == 0, "B: processed messages were offered again after restart")
		close(thiefB)
		table.insert(evidence, "B: a delivery message sent twice to an offline thief's key was applied once and was not re-offered after a restart")

		-- C ---------------------------------------------------------------------------------------
		local thiefC = newPlayer(-92004, "ThiefC")
		pt = open(thiefC)
		attachHandler(thiefC, pt)
		assert(store:MessageAsync(keys[thiefC.UserId], { kind = "steal", id = "C-" .. runId, w = weapon(777003), from = "VictimC" }), "C: message failed")
		deadline = os.clock() + 15
		while count(pt.Data, 777003) == 0 and os.clock() < deadline do
			task.wait(0.1)
		end
		assert(count(pt.Data, 777003) == 1, "C: message to an active session was not applied")
		close(thiefC)
		table.insert(evidence, "C: a message to a thief whose session is active in this server was applied by the handler")

		-- D ---------------------------------------------------------------------------------------
		local victimD, thiefD = newPlayer(-92005, "VictimD"), newPlayer(-92006, "ThiefD")
		pv, pt = open(victimD), open(thiefD)
		local wd = weapon(777004)
		wd.id = "w1"
		pv.Data.weapons.w1 = wd
		local idD = "D-" .. runId
		Logic.markPending(pt.Data, idD, victimD.UserId, "w1", os.time())
		assert(Data.saveNow(thiefD, 30))
		assert(Logic.beginTransfer(pv.Data, { weaponId = "w1", slot = 1, weapon = wd } :: any, idD, thiefD.UserId, "ThiefD", "VictimD", os.time()))
		assert(Data.saveNow(victimD, 30))
		close(victimD)
		close(thiefD) -- crash before delivery
		-- the victim comes back first and re-sends to the offline thief
		pv = open(victimD)
		Workshop.retryOutbox(victimD)
		assert(next(pv.Data.outbox) == nil, "D: outbox not acknowledged after the message was queued")
		assert(Data.saveNow(victimD, 30))
		close(victimD)
		-- the thief comes back: both the queued message and the pending record point at the weapon
		pt = open(thiefD)
		attachHandler(thiefD, pt)
		Workshop.resolvePending(thiefD)
		task.wait(2)
		assert(count(pt.Data, 777004) == 1, "D: message plus pending record made " .. count(pt.Data, 777004) .. " copies")
		assert(Data.saveNow(thiefD, 30))
		close(thiefD)
		assert(count(saved(victimD), 777004) == 0 and count(saved(thiefD), 777004) == 1, "D: saved copies wrong")
		table.insert(evidence, "D: after a crash, the victim's re-send and the thief's pending record both arrived; one copy in total")
	end)
	for player in sessions do
		pcall(close, player)
	end
	Workshop._reset()
	assert(ok, err)
	return {
		passed = true,
		mode = if mock then "ProfileStore Mock (in-memory)" else "Real DataStore (isolated store " .. storeName .. ")",
		evidence = evidence,
		limitations = "One Studio process: sessions are ended and re-acquired to model players moving between servers; two live servers at once are not exercised.",
	}
end
