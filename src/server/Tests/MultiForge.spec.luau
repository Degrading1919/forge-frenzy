-- Forge throughput, paid policy, and stale-session regression tests (v2 stations).
-- No real APIs or purchases.
local Services = script.Parent.Parent.Services
local Forge = require(Services.ForgeService)
local Data = require(Services.DataService)
local Production = require(Services.ProductionService)
local Shared = game:GetService("ReplicatedStorage").Shared
local Economy = require(Shared.Economy)
local Balance = require(Shared.Config.Balance)
local Evolution = require(Services.EvolutionService)
local Players = game:GetService("Players")

local function fixture(fn)
	local player = { UserId = -7351, Name = "BatchSmith", Parent = Players }
	local p = Economy.newProfile()
	p.ingots[1] = 10
	p.weaponsForged = Balance.forge.autoUnlockAfterForges -- Auto Forge unlocked
	p.stations[1].keep = 1 -- tests that inspect ownership explicitly keep every result
	local state = { now = 1000, allowed = true, owned = { MultiForge = true }, timers = {} }
	local saved = { clock = Forge.clock, delay = Forge.delay, rng = Forge.rng, service = Production._service, serverTime = Forge.serverTime }
	Forge.clock = function() return state.now end
	Forge.serverTime = function() return state.now end
	Forge.delay = function(_, callback) table.insert(state.timers, callback) end
	Forge.rng = Random.new(1948)
	Production._service = function(name)
		if name == "MonetizationService" then
			return {
				owns = function(_, key) return state.owned[key] == true end,
				canOfferPaidRandom = function()
					if state.policyHook then state.policyHook() end
					return state.allowed
				end,
			}
		end
		return nil
	end
	Data._setForTest(player, p)
	local ok, err = pcall(fn, player, p, state)
	Forge.stopAuto(player)
	Forge.clock, Forge.delay, Forge.rng, Forge.serverTime = saved.clock, saved.delay, saved.rng, saved.serverTime
	Production._service = saved.service
	Data._setForTest(player, nil)
	if not ok then error(err, 0) end
end

local function onlyWeapons(p)
	local list = {}
	for _, w in p.weapons do table.insert(list, w) end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

local tests = {}

tests["MultiForge rolls independently and counts every forge"] = function()
	fixture(function(player, p)
		-- replay the same seed through the pure rules to know what the two rolls must be
		local expected = Economy.newProfile()
		expected.ingots[1] = 10
		local rng = Random.new(1948)
		local _, batch = Economy.completeForgeBatch(expected, 1, p.stations[1].c, 1.5, rng, 0, 2, { keepFrom = 1, mult = 1, allowFullBackpack = true })
		local event
		local connection = Forge.completed.Event:Connect(function(_, payload)
			event = payload
		end)
		local progressBefore = Evolution.Logic.progress(p).forged
		assert(Forge.begin(player, 1, "free"))
		Forge._completeNow(player, 1)
		task.wait()
		connection:Disconnect()
		assert(event, "completed event")
		assert(#event.results == 2, "two results")
		assert(event.luck == 1.5 and event.auto and event.station == 1, "event fields")
		local weapons = onlyWeapons(p)
		assert(#weapons == 2 and p.pending == nil, "both rolls land in the backpack")
		assert(p.ingots[1] == 8 and p.weaponsForged == Balance.forge.autoUnlockAfterForges + 2, "one charge/counter increment per roll")
		for i = 1, 2 do
			local got, want = event.results[i].weapon, batch.results[i].weapon
			assert(got.v == want.v and got.r == want.r and got.q == want.q and got.d == want.d, "roll " .. i .. " must consume independent RNG draws")
			assert(p.weapons[got.id] and p.weapons[got.id].v == got.v)
		end
		assert(event.results[1].weapon.id ~= event.results[2].weapon.id)
		assert(Evolution.Logic.progress(p).forged - progressBefore == 2, "extra rolls must count toward evolution")
		Forge._completeNow(player, 1)
		assert(p.weaponsForged == Balance.forge.autoUnlockAfterForges + 2 and p.ingots[1] == 8, "completion replay duplicated rewards")
		local total = 0
		local ids = {}
		for _, w in weapons do
			total += w.v
			table.insert(ids, w.id)
		end
		assert(Forge.sellWeapons(player, ids))
		assert(not Forge.sellWeapons(player, ids) and not Forge.sellAll(player))
		assert(p.coins == total and p.weaponsSold == 2, "batch sales must be idempotent")
	end)
end

tests["MultiForge manual uses one server strike performance for both independent rolls"] = function()
	fixture(function(player, p, state)
		assert(Forge.begin(player, 1, "manual"))
		local session = Forge.session(player, 1)
		for i = 0, 29 do
			state.now = session.windowStart + i * 0.2
			assert(Forge.strike(player, session.id))
		end
		local luck
		local connection = Forge.completed.Event:Connect(function(_, payload) luck = payload.luck end)
		Forge._completeNow(player, 1)
		task.wait()
		connection:Disconnect()
		assert(luck == 2.5 and p.weaponsForged == Balance.forge.autoUnlockAfterForges + 2 and p.ingots[1] == 8)
		assert(Economy.weaponCount(p) == 2, "manual extras are always kept")
	end)
end

tests["MultiForge falls back to one roll when ingots or room for a second run out"] = function()
	-- one ingot left for a one-ingot recipe
	fixture(function(player, p)
		p.ingots[1] = 1
		assert(Forge.begin(player, 1, "free"))
		Forge._completeNow(player, 1)
		assert(p.weaponsForged == Balance.forge.autoUnlockAfterForges + 1 and p.ingots[1] == 0)
	end)
	-- a bigger recipe: three ingots only pay for one two-ingot Sword
	fixture(function(player, p)
		p.stations[1].c = 1 -- Sword: 2 ingots
		p.ingots[1] = 3
		assert(Forge.begin(player, 1, "free"))
		Forge._completeNow(player, 1)
		assert(p.weaponsForged == Balance.forge.autoUnlockAfterForges + 1 and p.ingots[1] == 1, "second roll needs its own recipe")
	end)
	-- one backpack slot left: the extra auto roll is sold instead of exceeding the cap
	fixture(function(player, p)
		for i = 1, Balance.inventory.maxWeapons - 1 do
			p.weapons["old" .. i] = { id = "old" .. i, m = 1, c = 1, q = 1, r = 1, d = "x", v = 12, ts = 0, }
		end
		assert(Forge.begin(player, 1, "free"))
		Forge._completeNow(player, 1)
		assert(p.weaponsForged == Balance.forge.autoUnlockAfterForges + 2 and p.ingots[1] == 8)
		assert(Economy.weaponCount(p) == Balance.inventory.maxWeapons, "the backpack never exceeds its cap")
		assert(p.weaponsSold == 1 and p.coins > 0, "the roll that did not fit was sold")
	end)
end

tests["each MultiForge result is filtered by the station keep rule; manual keeps everything"] = function()
	fixture(function(player, p)
		p.stations[1].keep = 7 -- sell everything
		p.weapons.previous = { id = "previous", m = 1, c = 1, q = 1, r = 6, d = "x", v = 100, ts = 0 }
		assert(Forge.begin(player, 1, "free"))
		Forge._completeNow(player, 1)
		assert(Economy.weaponCount(p) == 1 and p.weapons.previous ~= nil, "earlier weapons are never touched")
		assert(p.weaponsForged == Balance.forge.autoUnlockAfterForges + 2 and p.weaponsSold == 2 and p.coins > 0 and p.ingots[1] == 8)
	end)
	fixture(function(player, p)
		p.stations[1].keep = 4 -- default: keep Epic and above
		local event
		local connection = Forge.completed.Event:Connect(function(_, payload) event = payload end)
		assert(Forge.begin(player, 1, "free"))
		Forge._completeNow(player, 1)
		task.wait()
		connection:Disconnect()
		assert(event and #event.results == 2 and p.ingots[1] == 8)
		for _, result in event.results do
			if result.sold then
				assert(result.weapon.r < 4 and p.weapons[result.weapon.id] == nil)
			else
				assert(result.weapon.r >= 4 and p.weapons[result.weapon.id] == result.weapon)
			end
		end
	end)
	fixture(function(player, p)
		p.stations[1].keep = 7
		assert(Forge.begin(player, 1, "manual"))
		Forge._completeNow(player, 1)
		assert(Economy.weaponCount(p) == 2 and p.weaponsSold == 0 and p.coins == 0, "the keep rule is an auto-forge setting")
	end)
end

tests["premium luck requires current ownership and paid policy at start and completion"] = function()
	fixture(function(player, p, state)
		local forged = p.weaponsForged
		assert(select(2, Forge.begin(player, 1, "premium")) == "NotOwned")
		state.owned.PremiumAutoForge = true
		state.allowed = false
		assert(select(2, Forge.begin(player, 1, "premium")) == "PaidRandomRestricted")
		state.allowed = true
		local ok, info = Forge.begin(player, 1, "premium")
		assert(ok and info.sessionId)
		state.allowed = false
		Forge._completeNow(player, 1)
		assert(p.weaponsForged == forged and p.ingots[1] == 10 and not Forge.session(player, 1).auto, "restriction must cancel paid completion without charging")
		state.allowed = true
		assert(Forge.begin(player, 1, "premium"))
		state.owned.PremiumAutoForge = nil
		Forge._completeNow(player, 1)
		assert(p.weaponsForged == forged and p.ingots[1] == 10, "revoked pass must not retain premium luck")
		-- while owned and allowed, premium forges at the premium luck
		state.owned.PremiumAutoForge = true
		local luck
		local connection = Forge.completed.Event:Connect(function(_, payload) luck = payload.luck end)
		assert(Forge.begin(player, 1, "premium"))
		Forge._completeNow(player, 1)
		task.wait()
		connection:Disconnect()
		assert(luck == Balance.forge.auto.premiumLuck)
	end)
end

tests["restricted or revoked MultiForge retains free one-roll gameplay"] = function()
	fixture(function(player, p, state)
		state.allowed = false
		assert(Forge.begin(player, 1, "free"))
		Forge._completeNow(player, 1)
		assert(p.weaponsForged == Balance.forge.autoUnlockAfterForges + 1 and p.ingots[1] == 9)
	end)
	fixture(function(player, p, state)
		assert(Forge.begin(player, 1, "free"))
		state.owned.MultiForge = nil
		Forge._completeNow(player, 1)
		assert(p.weaponsForged == Balance.forge.autoUnlockAfterForges + 1 and p.ingots[1] == 9)
	end)
end

tests["evolution and reloaded profiles cancel stale sessions without consuming new materials"] = function()
	fixture(function(player, p)
		local forged = p.weaponsForged
		assert(Forge.begin(player, 1, "free"))
		p.evolutionRank = 1
		Forge._completeNow(player, 1)
		assert(p.weaponsForged == forged and p.ingots[1] == 10 and not Forge.session(player, 1).auto, "stale auto loop must stop")
	end)
	fixture(function(player, p)
		assert(Forge.begin(player, 1, "free"))
		local replacement = Economy.newProfile()
		Data._setForTest(player, replacement)
		Forge._completeNow(player, 1)
		assert(replacement.weaponsForged == 0 and replacement.ingots[1] == Economy.STARTER_INGOTS and p.ingots[1] == 10)
	end)
	fixture(function(player, p, state)
		-- a manual session cancelled by evolution costs nothing either
		assert(Forge.begin(player, 1, "manual"))
		p.evolutionRank = 2
		Forge._completeNow(player, 1)
		assert(p.ingots[1] == 10 and Economy.weaponCount(p) == 0)
		assert(state.now == 1000)
	end)
end

tests["a real normal evolution cancels a running auto loop and the old timers cannot spend"] = function()
	fixture(function(player, p, state)
		local forged = p.weaponsForged
		assert(Forge.begin(player, 1, "free"))
		-- evolve through the real rules: reset fields then the rank bump
		p.unlockedTier = 6
		p.weaponsForged = 1000
		p.coins = 1e9
		local ok = Evolution.Logic.evolve(p, false, 1)
		assert(ok and p.evolutionRank == 1)
		local ingotsAfter = p.ingots[1]
		for _, callback in table.clone(state.timers) do
			state.now += 20
			callback()
		end
		assert(p.weaponsForged == 1000 and p.ingots[1] == ingotsAfter and forged == 3, "stale timers spent materials after evolution")
		assert(not Forge.session(player, 1).auto, "stale auto loop stopped")
	end)
end

tests["locked or unaffordable recipes cannot be forged and failures are free"] = function()
	fixture(function(player, p)
		p.ingots[2] = 20
		p.stations[1].m = 2 -- stale recipe for a material that is not unlocked
		assert(select(2, Forge.begin(player, 1, "free")) == "MaterialLocked")
		assert(select(2, Forge.begin(player, 1, "manual")) == "MaterialLocked")
		assert(p.ingots[2] == 20 and p.weaponsForged == Balance.forge.autoUnlockAfterForges)
		assert(select(2, Economy.completeForgeBatch(p, 1, 4, 1.5, Random.new(5), 0, 3)) == "InvalidRequest")
		assert(p.ingots[1] == 10)
		assert(select(2, Forge.configure(player, 1, 2, 4, 4)) == "MaterialLocked")
		-- manual forges refuse to start without the recipe's ingots; auto forges wait instead
		p.stations[1].m = 1
		p.stations[1].c = 2 -- Greatsword: 5 ingots
		p.ingots[1] = 4
		assert(select(2, Forge.begin(player, 1, "manual")) == "NoMaterial")
		local ok, info = Forge.begin(player, 1, "free")
		assert(ok and info.waiting == true)
		assert(p.ingots[1] == 4 and p.weaponsForged == Balance.forge.autoUnlockAfterForges, "waiting spends nothing")
	end)
end

tests["two players have independent sessions, materials, rolls and backpacks"] = function()
	fixture(function(player, p)
		local other = { UserId = -7352, Name = "OtherSmith", Parent = Players }
		local otherProfile = Economy.newProfile()
		otherProfile.stations[1].c = 3 -- Axe, 3 ingots
		otherProfile.stations[1].keep = 1
		Data._setForTest(other, otherProfile)
		local ok, err = pcall(function()
			assert(Forge.begin(player, 1, "manual"))
			assert(Forge.begin(other, 1, "manual"))
			local a, b = Forge.session(player, 1), Forge.session(other, 1)
			assert(a.id ~= b.id)
			assert(select(2, Forge.strike(other, a.id)) == "NoSession", "another player's session id accepted")
			Forge._completeNow(player, 1)
			assert(p.weaponsForged == Balance.forge.autoUnlockAfterForges + 2 and p.ingots[1] == 8)
			assert(otherProfile.weaponsForged == 0 and Economy.weaponCount(otherProfile) == 0 and otherProfile.ingots[1] == Economy.STARTER_INGOTS)
			Forge._completeNow(other, 1)
			assert(otherProfile.weaponsForged == 2 and otherProfile.ingots[1] == Economy.STARTER_INGOTS - 6, "two Axe rolls cost two recipes of three ingots")
			for _, w in otherProfile.weapons do
				assert(w.c == 3, "ownership/class crossed profiles")
			end
			for _, w in p.weapons do
				assert(w.c == p.stations[1].c, "ownership/class crossed profiles")
			end
			-- another player's sale changes nothing here
			local coinsBefore = p.coins
			Forge.sellAll(other)
			assert(p.coins == coinsBefore and Economy.weaponCount(p) == 2)
		end)
		Data._setForTest(other, nil)
		if not ok then error(err, 0) end
	end)
end

tests["stop auto abandons the batch in progress and queued timer replays never restart it"] = function()
	fixture(function(player, p, state)
		local forged = p.weaponsForged
		assert(Forge.begin(player, 1, "free"))
		assert(Forge.stopAuto(player))
		Forge._completeNow(player, 1)
		state.now += 20
		for _, callback in table.clone(state.timers) do callback() end
		assert(p.weaponsForged == forged and p.ingots[1] == 10 and Forge.session(player, 1).done, "stopped loop restarted or replay duplicated the batch")
	end)
end

tests["policy-hook interleaving cannot open a second session or complete across evolution"] = function()
	-- manual: a second begin during the yielding policy check is refused
	fixture(function(player, p, state)
		assert(Forge.begin(player, 1, "manual"))
		local attempted = false
		state.policyHook = function()
			state.policyHook = nil
			local ok, why = Forge.begin(player, 1, "manual")
			assert(not ok and why == "Busy", "yielding completion opened second forge")
			attempted = true
			p.evolutionRank = 1
		end
		Forge._completeNow(player, 1)
		assert(attempted and p.weaponsForged == Balance.forge.autoUnlockAfterForges and p.ingots[1] == 10, "stale completion spent materials after policy yield")
	end)
	-- auto: starting a new loop on the station replaces the old one, and the old completion
	-- is cancelled rather than spending against the replacement
	fixture(function(player, p, state)
		assert(Forge.begin(player, 1, "free"))
		local replaced
		state.policyHook = function()
			state.policyHook = nil
			local ok, info = Forge.begin(player, 1, "free")
			assert(ok, "a new auto forge may replace the finishing one")
			replaced = info.sessionId
		end
		Forge._completeNow(player, 1)
		assert(replaced and Forge.session(player, 1).id == replaced, "the replacement is the live session")
		assert(p.weaponsForged == Balance.forge.autoUnlockAfterForges and p.ingots[1] == 10, "the replaced session must not spend or reward")
	end)
end

return tests
