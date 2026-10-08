-- WorkshopService: Forge Lock, steal validation, atomic weapon transfer, and the steal / carry
-- runtime driven with fake players and fake positions. Restores everything it overrides.

local Services = script.Parent.Parent.Services
local WorkshopService = require(Services.WorkshopService)
local Logic = WorkshopService.Logic
local Shared = game:GetService("ReplicatedStorage").Shared
local Economy = require(Shared.Economy)
local Balance = require(Shared.Config.Balance)
local Players = game:GetService("Players")

local function weapon(id: string, v: number): any
	return { id = id, m = 3, c = 2, q = 3, r = 4, d = "greatsword_claymore", v = v, ts = 11 }
end

-- A victim with a protected-by-nothing display: 30 forges (past the shield), w1 on podium 1.
local function victimProfile(): any
	local p = Economy.newProfile()
	p.weaponsForged = Logic.SHIELD_FORGES + 5
	p.weapons.w1 = weapon("w1", 5000)
	p.weapons.w2 = weapon("w2", 700)
	p.showcase[1] = "w1"
	p.nextWeaponId = 3
	return p
end

local tests = {}

-- Pure rules --------------------------------------------------------------------------------------

tests["forge lock lasts 30 seconds and cannot be reused until its cooldown ends"] = function()
	assert(Logic.LOCK_SEC == 30)
	local lock = Logic.newLock()
	assert(not Logic.isLocked(lock, 0))
	local ok, until_ = Logic.lock(lock, 100)
	assert(ok and until_ == 130 and lock.lockedUntil == 130)
	assert(Logic.isLocked(lock, 100) and Logic.isLocked(lock, 129.9) and not Logic.isLocked(lock, 130))
	local again, err = Logic.lock(lock, 110)
	assert(not again and err == "AlreadyLocked" and lock.lockedUntil == 130, "cannot extend a lock")
	again, err = Logic.lock(lock, 131)
	assert(not again and err == "LockCooldown", "cooldown after the lock ends")
	assert(lock.nextLockAt == 130 + Logic.LOCK_COOLDOWN_SEC)
	again, err = Logic.lock(lock, 130 + Logic.LOCK_COOLDOWN_SEC - 0.1)
	assert(not again and err == "LockCooldown")
	ok = Logic.lock(lock, 130 + Logic.LOCK_COOLDOWN_SEC)
	assert(ok and lock.lockedUntil == 130 + Logic.LOCK_COOLDOWN_SEC + 30)
	-- locks are per workshop
	local other = Logic.newLock()
	assert(Logic.lock(other, 100))
end

tests["new players are shielded until they have forged enough"] = function()
	assert(Logic.shielded({ weaponsForged = 0 }) and Logic.shielded({}))
	assert(Logic.shielded({ weaponsForged = Logic.SHIELD_FORGES - 1 }))
	assert(not Logic.shielded({ weaponsForged = Logic.SHIELD_FORGES }))
end

tests["canSteal accepts a normal steal and returns the weapon"] = function()
	local thief, victim = Economy.newProfile(), victimProfile()
	local ok, w = Logic.canSteal(thief, victim, 1, Logic.newLock(), 100, {}, nil)
	assert(ok and w == victim.weapons.w1)
	assert(victim.weapons.w1 ~= nil and Economy.weaponCount(thief) == 0, "validation moves nothing")
end

tests["canSteal refuses own workshop, bad slots, locks, shields and cooldowns"] = function()
	local thief, victim = Economy.newProfile(), victimProfile()
	local lock = Logic.newLock()
	local function why(profile, slot, theLock, now, carried, cooldown)
		local ok, code = Logic.canSteal(thief, profile, slot, theLock or lock, now or 100, carried or {}, cooldown)
		assert(not ok)
		return code
	end
	assert(select(2, Logic.canSteal(victim, victim, 1, lock, 100, {}, nil)) == "OwnWeapon")
	for _, slot in { 0, 9, 1.5, "1", -1 } do
		assert(why(victim, slot) == "InvalidSlot", "slot " .. tostring(slot))
	end
	-- locked workshop
	local locked = Logic.newLock()
	Logic.lock(locked, 100)
	assert(why(victim, 1, locked, 110) == "ForgeLocked")
	assert(Logic.canSteal(thief, victim, 1, locked, 131, {}, nil), "lock expired")
	-- new player shield
	local newbie = victimProfile()
	newbie.weaponsForged = Logic.SHIELD_FORGES - 1
	assert(why(newbie, 1) == "Shielded")
	-- per-slot cooldown after an earlier steal attempt
	assert(why(victim, 1, nil, 100, nil, 150) == "SlotCooldown")
	assert(Logic.canSteal(thief, victim, 1, lock, 150, {}, 150), "cooldown over exactly at its end")
	-- empty podium, dangling id, other slot
	assert(why(victim, 2) == "EmptySlot")
	victim.showcase[3] = "ghost"
	assert(why(victim, 3) == "EmptySlot", "podium pointing at a sold weapon")
	-- already being carried
	assert(why(victim, 1, nil, 100, { w1 = true }) == "AlreadyCarried")
	-- the thief's backpack is full
	local packed = Economy.newProfile()
	for i = 1, Balance.inventory.maxWeapons do
		packed.weapons["x" .. i] = weapon("x" .. i, 1)
	end
	local ok, code = Logic.canSteal(packed, victim, 1, lock, 100, {}, nil)
	assert(not ok and code == "InventoryFull")
end

tests["transfer moves the weapon atomically under a new id and clears the victim podium"] = function()
	local thief, victim = Economy.newProfile(), victimProfile()
	thief.nextWeaponId = 40
	local carry = { weaponId = "w1", slot = 1 }
	local ok, copy = Logic.transfer(thief, victim, carry, "Thief", "Victim")
	assert(ok)
	assert(victim.weapons.w1 == nil, "weapon left the victim's backpack")
	assert(victim.showcase[1] == "", "victim podium cleared")
	assert(victim.weapons.w2 ~= nil, "other weapons untouched")
	assert(copy.id == "w40" and thief.weapons.w40 == copy and thief.weapons.w1 == nil, "thief receives a fresh id")
	assert(copy.m == 3 and copy.c == 2 and copy.q == 3 and copy.r == 4 and copy.v == 5000 and copy.d == "greatsword_claymore" and copy.ts == 11, "weapon data preserved")
	assert(copy.sf == "Victim", "stolen-from tag")
	assert(thief.nextWeaponId == 41)
	assert(thief.weaponsStolen == 1 and victim.weaponsLost == 1)
	assert(thief.highestWeaponValue == 0, "a stolen weapon is not a forging record")
	assert(copy.st == 1, "marked stolen, so its usable value follows the thief's progression")
	assert(Economy.weaponCount(thief) + Economy.weaponCount(victim) == 2, "weapon count conserved: nothing duplicated or destroyed")
end

tests["transfer refuses when the weapon is gone or the thief has no room, changing nothing"] = function()
	local thief, victim = Economy.newProfile(), victimProfile()
	local carry = { weaponId = "w1", slot = 1 }
	-- the victim sold it while it was being carried
	victim.weapons.w1 = nil
	victim.showcase[1] = ""
	local ok, err = Logic.transfer(thief, victim, carry, "T", "V")
	assert(not ok and err == "Gone" and Economy.weaponCount(thief) == 0 and (thief.weaponsStolen or 0) == 0)
	-- full backpack: refused and the weapon stays with the victim
	local victim2 = victimProfile()
	local packed = Economy.newProfile()
	for i = 1, Balance.inventory.maxWeapons do
		packed.weapons["x" .. i] = weapon("x" .. i, 1)
	end
	ok, err = Logic.transfer(packed, victim2, carry, "T", "V")
	assert(not ok and err == "InventoryFull")
	assert(victim2.weapons.w1 ~= nil and victim2.showcase[1] == "w1" and (victim2.weaponsLost or 0) == 0)
	assert(Economy.weaponCount(packed) == Balance.inventory.maxWeapons)
	-- a second transfer of the same carry cannot duplicate
	local victim3, thief3 = victimProfile(), Economy.newProfile()
	assert(Logic.transfer(thief3, victim3, carry, "T", "V"))
	ok, err = Logic.transfer(thief3, victim3, carry, "T", "V")
	assert(not ok and err == "Gone" and Economy.weaponCount(thief3) == 1, "replayed delivery must not duplicate the weapon")
end

-- Runtime -------------------------------------------------------------------------------------------

local function pos(x: number): any
	return setmetatable({ x = x }, {
		__sub = function(a, b)
			return { Magnitude = math.abs(a.x - b.x) }
		end,
	})
end

local function fakePlayer(userId: number, name: string, x: number): (any, any)
	local root = { Position = pos(x) }
	local humanoid = { Health = 100 }
	local player = { UserId = userId, Name = name, DisplayName = name, Parent = Players }
	player.Character = {
		FindFirstChild = function(_, childName)
			return if childName == "HumanoidRootPart" then root else nil
		end,
		FindFirstChildOfClass = function(_, className)
			return if className == "Humanoid" then humanoid else nil
		end,
	}
	return player, root
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

-- Runs fn with two fake workshops: thief owns plot 2 (x = 100), victim plot 1 (x = 0).
local function runtime(fn: (any) -> ())
	if typeof(Players) == "Instance" then
		-- These drive fake players through a patched Players service, which only the Lune
		-- harness allows. In Studio the real two-client acceptance covers the same flows.
		return
	end
	local savedWorld = table.clone(WorkshopService.world)
	local savedPlayers = rawget(Players, "GetPlayers")
	local state: any = { now = 1000, saved = 0, notes = {}, owned = {}, persisted = {}, messages = {}, ids = 0 }
	local thief, thiefRoot = fakePlayer(-9001, "Thief", 100)
	local victim, victimRoot = fakePlayer(-9002, "Victim", 0)
	local profiles = { [thief] = Economy.newProfile(), [victim] = victimProfile() }
	profiles[thief].weaponsForged = 60
	state.thief, state.victim, state.thiefRoot, state.victimRoot, state.profiles = thief, victim, thiefRoot, victimRoot, profiles
	local plots = { [thief] = 2, [victim] = 1 }
	local owners = { [1] = victim, [2] = thief }
	WorkshopService._reset()
	WorkshopService._inject({
		getProfile = function(player)
			return profiles[player]
		end,
		markDirty = function() end,
		saveNow = function(player)
			state.saved += 1
			if state.onSave and state.onSave(player) == false then
				return false
			end
			if state.saveFails and state.saveFails[player] then
				return false
			end
			-- "persisted" copies model what a crash would leave in the DataStore
			state.persisted[player] = deepCopy(profiles[player])
			return true
		end,
		sendMessage = function(userId, message)
			if state.messageFails then
				return false
			end
			table.insert(state.messages, { to = userId, message = deepCopy(message) })
			return true
		end,
		playerByUserId = function(userId)
			for player in profiles do
				if player.UserId == userId and player.Parent == Players then
					return player
				end
			end
			return nil
		end,
		newId = function()
			state.ids += 1
			return "T" .. state.ids
		end,
		spawn = function(fn, ...)
			fn(...)
		end,
		now = function()
			return state.now
		end,
		owns = function(_, key)
			return state.owned[key] == true
		end,
		cashMultiplier = function()
			return 1
		end,
	})
	WorkshopService.world.plotOf = function(player)
		return plots[player] or 0
	end
	WorkshopService.world.ownerOf = function(plot)
		return owners[plot]
	end
	WorkshopService.world.inPlot = function(plot, position)
		-- plot 1 spans x < 50, plot 2 spans x >= 50
		return if plot == 1 then position.x < 50 else position.x >= 50
	end
	WorkshopService.world.podiumPosition = function()
		return pos(0)
	end
	WorkshopService.world.padPosition = function()
		return pos(100)
	end
	WorkshopService.world.collectorPosition = function()
		return pos(100)
	end
	WorkshopService.world.lockButtonPosition = function(plot)
		return pos(if plot == 1 then 0 else 100)
	end
	local conn = WorkshopService.notify.Event:Connect(function(player, text)
		table.insert(state.notes, { player = player, text = text })
	end)
	local ok, err = pcall(fn, state)
	conn:Disconnect()
	WorkshopService._reset()
	for key, value in savedWorld do
		WorkshopService.world[key] = value
	end
	rawset(Players, "GetPlayers", savedPlayers)
	WorkshopService._inject({
		getProfile = function()
			return nil
		end,
		now = function()
			return 0
		end,
		owns = function()
			return false
		end,
	})
	if not ok then
		error(err, 0)
	end
end

-- Runs the carrier to x at a normal carrying speed (10 studs every 0.5 s), stepping carries.
local function walk(s: any, x: number)
	local from = s.thiefRoot.Position.x
	local dir = if x >= from then 1 else -1
	local at = from
	while at ~= x do
		at = if math.abs(x - at) <= 10 then x else at + 10 * dir
		s.now += 0.5
		s.thiefRoot.Position = pos(at)
		WorkshopService.stepCarries()
	end
end

-- Walks a steal to the point where the thief is carrying the weapon.
local function startCarry(s: any, slot: number?)
	slot = slot or 1
	s.thiefRoot.Position = pos(0) -- standing at the podium
	assert(WorkshopService.stealBegin(s.thief, 1, slot))
	s.now += Logic.holdSec(s.profiles[s.victim].weapons[s.profiles[s.victim].showcase[slot]])
	local ok, info = WorkshopService.stealCommit(s.thief, 1, slot)
	assert(ok, tostring(info))
	return info
end

tests["a delivered steal moves the weapon, protects it while carried, and notifies"] = function()
	runtime(function(s)
		local victimData, thiefData = s.profiles[s.victim], s.profiles[s.thief]
		s.thiefRoot.Position = pos(0)
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		-- committing before the hold completes is refused, and the intent is consumed
		local early, why = WorkshopService.stealCommit(s.thief, 1, 1)
		assert(not early and why == "TooFast")
		early, why = WorkshopService.stealCommit(s.thief, 1, 1)
		assert(not early and why == "NoIntent", "intent is consumed by a failed commit")
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		s.now += 1
		early, why = WorkshopService.stealCommit(s.thief, 1, 1)
		assert(not early and why == "TooFast")
		assert(select(2, WorkshopService.stealCommit(s.thief, 1, 2)) == "NoIntent", "intent is per podium")
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		s.now += Logic.holdSec(victimData.weapons.w1)
		local ok, info = WorkshopService.stealCommit(s.thief, 1, 1)
		assert(ok and info.weapon.id == "w1" and info.deadline == s.now + Logic.CARRY_SEC)
		-- while carried, the weapon is still the victim's but cannot be sold or earn
		assert(victimData.weapons.w1 ~= nil and Economy.weaponCount(thiefData) == 0)
		assert(WorkshopService.isCarried(s.victim, "w1") and WorkshopService.carriedFrom(s.victim).w1 == true)
		assert(WorkshopService.carryOf(s.thief) ~= nil)
		local sold = Economy.sellWeapons(victimData, { "w1" }, WorkshopService.carriedFrom(s.victim))
		assert(not sold and victimData.weapons.w1 ~= nil, "carried weapon sold from under the thief")
		assert(WorkshopService.incomePerSec(s.victim) == 0, "a carried weapon earns nothing")
		-- a second thief cannot grab the same weapon
		local third = select(1, fakePlayer(-9003, "Third", 0))
		-- (no profile for the third player: the carried check is on the victim's side)
		assert(select(2, Logic.canSteal(Economy.newProfile(), victimData, 1, WorkshopService.lockState(1), s.now, WorkshopService.carriedFrom(s.victim), nil)) == "AlreadyCarried")
		assert(third ~= nil)
		-- not home yet: nothing moves
		s.thiefRoot.Position = pos(20)
		WorkshopService.stepCarries()
		assert(victimData.weapons.w1 ~= nil and WorkshopService.carryOf(s.thief) ~= nil)
		-- reach own workshop
		walk(s, 100)
		assert(WorkshopService.carryOf(s.thief) == nil, "carry ended")
		assert(victimData.weapons.w1 == nil and victimData.showcase[1] == "", "victim lost the weapon and podium")
		assert(Economy.weaponCount(thiefData) == 1, "thief gained exactly one weapon")
		local stolen
		for _, w in thiefData.weapons do
			stolen = w
		end
		assert(stolen.v == 5000 and thiefData.weapons[stolen.id] == stolen and thiefData.nextWeaponId == 2, "fresh id from the thief's own counter")
		assert(stolen.sf == "Victim")
		assert(s.saved == 2, "both profiles saved at once after a transfer, saved " .. s.saved)
		-- the weapon is gone: a repeated step cannot duplicate it
		WorkshopService.stepCarries()
		assert(Economy.weaponCount(thiefData) == 1 and Economy.weaponCount(victimData) == 1)
		local told = false
		for _, note in s.notes do
			if note.player == s.victim and note.text:find("stole your weapon") then told = true end
		end
		assert(told, "victim was told")
	end)
end

tests["tagging the thief returns the weapon and starts the podium cooldown"] = function()
	runtime(function(s)
		local victimData = s.profiles[s.victim]
		startCarry(s)
		s.thiefRoot.Position = pos(60)
		s.victimRoot.Position = pos(55) -- within TAG_RANGE
		WorkshopService.stepCarries()
		assert(WorkshopService.carryOf(s.thief) == nil)
		assert(victimData.weapons.w1 ~= nil and victimData.showcase[1] == "w1", "weapon is back on its podium")
		assert(Economy.weaponCount(s.profiles[s.thief]) == 0)
		-- the thief may try again after their personal cooldown and the podium's cooldown
		s.victimRoot.Position = pos(0)
		s.thiefRoot.Position = pos(0)
		local soon, soonWhy = WorkshopService.stealBegin(s.thief, 1, 1)
		assert(not soon and soonWhy == "StealCooldown", "a failed attempt still counts toward the thief's cooldown")
		s.now += Logic.STEAL_COOLDOWN_SEC + 1
		soon, soonWhy = WorkshopService.stealBegin(s.thief, 1, 1)
		assert(not soon and soonWhy == "SlotCooldown", "the robbed podium rests")
		s.now += Logic.SLOT_COOLDOWN_SEC
		assert(WorkshopService.stealBegin(s.thief, 1, 1), "cooldown eventually ends")
	end)
end

tests["running out of time, or the thief leaving, returns the weapon without duplicating it"] = function()
	runtime(function(s)
		local victimData = s.profiles[s.victim]
		local info = startCarry(s)
		s.thiefRoot.Position = pos(30)
		s.now = info.deadline + 1
		WorkshopService.stepCarries()
		assert(WorkshopService.carryOf(s.thief) == nil and victimData.weapons.w1 ~= nil and Economy.weaponCount(s.profiles[s.thief]) == 0, "timeout")
		WorkshopService._reset()
		s.now += 1000
		startCarry(s)
		s.thief.Parent = nil -- disconnected
		WorkshopService.stepCarries()
		assert(WorkshopService.carryOf(s.thief) == nil and victimData.weapons.w1 ~= nil and Economy.weaponCount(s.profiles[s.thief]) == 0, "thief left")
		s.thief.Parent = Players
		WorkshopService._reset()
		s.now += 1000
		startCarry(s)
		s.thiefRoot.Position = pos(30)
		local hp = s.thief.Character:FindFirstChildOfClass("Humanoid")
		hp.Health = 0 -- thief died
		WorkshopService.stepCarries()
		assert(WorkshopService.carryOf(s.thief) == nil and victimData.weapons.w1 ~= nil, "thief died")
	end)
end

tests["the weapon vanishing mid-carry ends the carry safely"] = function()
	runtime(function(s)
		local victimData = s.profiles[s.victim]
		startCarry(s)
		victimData.weapons.w1 = nil -- e.g. removed by a support tool
		victimData.showcase[1] = ""
		walk(s, 100)
		assert(WorkshopService.carryOf(s.thief) == nil and Economy.weaponCount(s.profiles[s.thief]) == 0, "nothing created from nothing")
	end)
end

tests["steal begin refuses own workshop, locked workshops, shields, distance and cooldown"] = function()
	runtime(function(s)
		local victimData = s.profiles[s.victim]
		s.thiefRoot.Position = pos(0)
		-- own workshop (plot 2 belongs to the thief)
		local ok, why = WorkshopService.stealBegin(s.thief, 2, 1)
		assert(not ok and why == "OwnWeapon")
		assert(select(2, WorkshopService.stealBegin(s.thief, 7, 1)) == "OwnWeapon", "unowned plot")
		assert(select(2, WorkshopService.stealBegin(s.thief, "1" :: any, 1)) == "InvalidSlot")
		-- too far
		s.thiefRoot.Position = pos(40)
		ok, why = WorkshopService.stealBegin(s.thief, 1, 1)
		assert(not ok and why == "TooFar")
		s.thiefRoot.Position = pos(0)
		-- empty podium
		ok, why = WorkshopService.stealBegin(s.thief, 1, 2)
		assert(not ok and why == "EmptySlot")
		-- shielded victim
		victimData.weaponsForged = 3
		ok, why = WorkshopService.stealBegin(s.thief, 1, 1)
		assert(not ok and why == "Shielded")
		victimData.weaponsForged = 60
		-- the victim locks the forge: stealing is impossible and the lock expires
		local locked, until_ = WorkshopService.lockForge(s.victim)
		assert(locked and until_ == s.now + 30)
		ok, why = WorkshopService.stealBegin(s.thief, 1, 1)
		assert(not ok and why == "ForgeLocked")
		local again, lockWhy = WorkshopService.lockForge(s.victim)
		assert(not again and lockWhy == "AlreadyLocked")
		s.now += 31
		assert(WorkshopService.stealBegin(s.thief, 1, 1), "lock expired")
		WorkshopService.stealCancel(s.thief)
		-- the lock button must be reachable
		s.victimRoot.Position = pos(90)
		s.now += 100
		local far, farWhy = WorkshopService.lockForge(s.victim)
		assert(not far and farWhy == "TooFar")
		-- a thief with no workshop of their own cannot lock one
		assert(select(2, WorkshopService.lockForge(select(1, fakePlayer(-9004, "Nobody", 0)))) == "NoWorkshop")
	end)
end

tests["a successful steal starts a personal cooldown"] = function()
	runtime(function(s)
		startCarry(s)
		walk(s, 100) -- delivered
		assert(Economy.weaponCount(s.profiles[s.thief]) == 1)
		-- victim shows a second weapon; the thief tries again straight away
		s.profiles[s.victim].showcase[2] = "w2"
		s.thiefRoot.Position = pos(0)
		local ok, why = WorkshopService.stealBegin(s.thief, 1, 2)
		assert(not ok and why == "StealCooldown")
		s.now += Logic.STEAL_COOLDOWN_SEC + 1
		assert(WorkshopService.stealBegin(s.thief, 1, 2), "allowed after the cooldown")
	end)
end

-- Display income and collector through the service --------------------------------------------------------

tests["collector and buy-pad actions need the player to be at the building"] = function()
	runtime(function(s)
		local data = s.profiles[s.thief]
		data.bank = 500.5
		s.thiefRoot.Position = pos(0) -- far from the collector (x = 100)
		local ok, why = WorkshopService.collect(s.thief)
		assert(not ok and why == "TooFar" and data.bank == 500.5)
		s.thiefRoot.Position = pos(100)
		local paid
		ok, paid = WorkshopService.collect(s.thief)
		assert(ok and paid == 500 and data.coins == 500 and data.bank == 0, "whole coins paid, bank emptied")
		-- a magnet pass collects from anywhere
		s.owned.CollectionMagnet = true
		data.bank = 10
		s.thiefRoot.Position = pos(0)
		ok, paid = WorkshopService.collect(s.thief)
		assert(ok and paid == 10)
		-- pads
		data.unlockedTier = 2
		data.coins = 1e6
		ok, why = WorkshopService.buyPad(s.thief, "podiums_1")
		assert(not ok and why == "TooFar", "must stand on the pad")
		s.thiefRoot.Position = pos(100)
		ok = WorkshopService.buyPad(s.thief, "podiums_1")
		assert(ok and data.pads.podiums_1)
		ok, why = WorkshopService.buyPad(s.thief, "podiums_1")
		assert(not ok and why == "AlreadyBuilt")
		ok, why = WorkshopService.buyPad(s.thief, "line_2")
		assert(not ok and why == "PadLocked")
		ok, why = WorkshopService.buyPad(s.thief, 5 :: any)
		assert(not ok and why == "TooFar")
	end)
end

tests["display income ticks into the bank, auto-collects with a magnet, and offline is half rate"] = function()
	runtime(function(s)
		local data = s.profiles[s.victim]
		data.unlockedTier = 32
		data.weapons.w1.v = 100000
		rawset(Players, "GetPlayers", function()
			return { s.victim, s.thief }
		end)
		local rate = 100000 * Balance.display.incomePerSecond
		assert(math.abs(WorkshopService.incomePerSec(s.victim) - rate) < 1e-9)
		WorkshopService.tickIncome(10)
		assert(math.abs(data.bank - rate * 10) < 1e-9, "10 s of income")
		assert(s.profiles[s.thief].bank == 0, "an empty workshop earns nothing")
		s.owned.CollectionMagnet = true
		WorkshopService.tickIncome(5)
		assert(data.bank == 0 or data.bank < 1, "magnet auto-collected")
		assert(data.coins >= rate * 15 - 1)
		s.owned.CollectionMagnet = nil
		local before = data.bank
		WorkshopService.settleOffline(s.victim, 100)
		assert(math.abs(data.bank - before - rate * 50) < 1e-6, "100 s offline at 50 percent efficiency")
		WorkshopService.settleOffline(s.victim, -5)
		assert(math.abs(data.bank - before - rate * 50) < 1e-6)
		assert(WorkshopService.incomePerSec({}) == 0, "unknown player earns nothing")
	end)
end

-- Review remediation (PR #5): value-based holds, pinned weapons, teleports, workshop hand-over,
-- durable transfers and the stolen-weapon value cap. ---------------------------------------------

local Steal = require(Shared.Steal)
local ForgeMath = require(Shared.ForgeMath)

-- Copies of a weapon (by value) in the places one can be one can be: victim and thief backpacks, the victim's outbox
-- (being delivered) and anything already applied from a message. Used to prove conservation.
local function countCopies(profiles: { any }, v: number): number
	local n = 0
	for _, p in profiles do
		for _, w in p.weapons do
			if w.v == v then
				n += 1
			end
		end
		for _, entry in (p.outbox or {}) do
			if entry.w.v == v then
				n += 1
			end
		end
	end
	return n
end

tests["hold time follows weapon value on a log scale, 2 to 8 seconds"] = function()
	local cases = {
		{ 0, 2 }, { 67, 2 }, { 1000, 2 }, { 3.78e3, 2.5 }, { 3e4, 2.5 }, { 1e6, 3.5 },
		{ 1e8, 4.5 }, { 5e8, 4.5 }, { 1e11, 5.5 }, { 1e12, 6 }, { 1e15, 7.5 }, { 6e15, 8 }, { 4e16, 8 }, { math.huge, 8 },
	}
	for _, case in cases do
		local got = Steal.holdSeconds(case[1])
		assert(got == case[2], string.format("value %g: expected %s got %s", case[1], case[2], got))
	end
	assert(Steal.holdSeconds(-5) == 2 and Steal.holdSeconds(0 / 0) == 2 and Steal.holdSeconds("x") == 2, "bad values get the minimum")
	local last = 0
	for e = 0, 20, 0.25 do
		local h = Steal.holdSeconds(10 ^ e)
		assert(h >= last and h >= 2 and h <= 8, "monotonic and bounded")
		last = h
	end
end

tests["the server enforces the value-based hold and a client cannot shorten it"] = function()
	runtime(function(s)
		local victimData = s.profiles[s.victim]
		victimData.weapons.w1.v = 1e15 -- endgame weapon: 7.5 s
		s.thiefRoot.Position = pos(0)
		local ok, info = WorkshopService.stealBegin(s.thief, 1, 1)
		assert(ok and info.holdSec == 7.5, "begin tells the client the real hold")
		local told = false
		for _, note in s.notes do
			if note.player == s.victim and note.text:find("is stealing your") then told = true end
		end
		assert(told, "the owner is alerted when the hold starts")
		s.now += 2.5 -- a spoofed client that pretends the hold was the old 2.5 s
		local early, why = WorkshopService.stealCommit(s.thief, 1, 1)
		assert(not early and why == "TooFast")
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		s.now += 7.5 - Logic.STEAL_HOLD_TOLERANCE
		assert(WorkshopService.stealCommit(s.thief, 1, 1), "a full hold (within latency tolerance) succeeds")
	end)
end

tests["moving, replacing or removing the displayed weapon during a hold steals nothing"] = function()
	runtime(function(s)
		local victimData = s.profiles[s.victim]
		victimData.showcase[2] = "w2"
		s.thiefRoot.Position = pos(0)
		-- swap the podium to a cheaper weapon mid-hold: the heartbeat cancels the hold
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		victimData.showcase[1], victimData.showcase[2] = "w2", "w1"
		WorkshopService.stepIntents()
		assert(WorkshopService.intentOf(s.thief) == nil, "hold cancelled")
		s.now += 3
		assert(select(2, WorkshopService.stealCommit(s.thief, 1, 1)) == "NoIntent")
		-- swap faster than the heartbeat: the commit itself refuses
		victimData.showcase[1], victimData.showcase[2] = "w1", "w2"
		s.now += Logic.STEAL_COOLDOWN_SEC
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		victimData.showcase[1] = "w2"
		s.now += Logic.holdSec(victimData.weapons.w1)
		local ok, why = WorkshopService.stealCommit(s.thief, 1, 1)
		assert(not ok and why == "Moved", tostring(why))
		-- the same id now pointing at a different weapon (replaced) is refused too
		victimData.showcase[1] = "w1"
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		victimData.weapons.w1 = { id = "w1", m = 1, c = 4, q = 1, r = 1, d = "dagger_basic", v = 20, ts = 99 }
		s.now += Logic.holdSec({ v = 5000 })
		ok, why = WorkshopService.stealCommit(s.thief, 1, 1)
		assert(not ok and why == "Moved", tostring(why))
		-- removed (sold) mid-hold
		victimData.weapons.w1 = weapon("w1", 5000)
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		victimData.weapons.w1 = nil
		victimData.showcase[1] = ""
		s.now += Logic.holdSec({ v = 5000 })
		ok, why = WorkshopService.stealCommit(s.thief, 1, 1)
		assert(not ok and why == "EmptySlot", tostring(why))
		assert(Economy.weaponCount(s.profiles[s.thief]) == 0 and WorkshopService.carryOf(s.thief) == nil, "nothing stolen")
	end)
end

tests["letting go, walking off, dying or the owner locking cancels a hold"] = function()
	runtime(function(s)
		s.thiefRoot.Position = pos(0)
		-- released the key: the client cancels
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		WorkshopService.stealCancel(s.thief)
		s.now += 3
		assert(select(2, WorkshopService.stealCommit(s.thief, 1, 1)) == "NoIntent")
		-- walked off (a client that never sends cancel)
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		s.thiefRoot.Position = pos(30)
		WorkshopService.stepIntents()
		s.thiefRoot.Position = pos(0)
		s.now += 3
		assert(select(2, WorkshopService.stealCommit(s.thief, 1, 1)) == "NoIntent", "walking away cancels")
		-- died
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		local hp = s.thief.Character:FindFirstChildOfClass("Humanoid")
		hp.Health = 0
		WorkshopService.stepIntents()
		hp.Health = 100
		s.now += 3
		assert(select(2, WorkshopService.stealCommit(s.thief, 1, 1)) == "NoIntent", "dying cancels")
		-- the owner locks mid-hold
		assert(WorkshopService.stealBegin(s.thief, 1, 1))
		assert(WorkshopService.lockForge(s.victim))
		s.now += 3
		assert(select(2, WorkshopService.stealCommit(s.thief, 1, 1)) == "NoIntent", "locking cancels")
		assert(Economy.weaponCount(s.profiles[s.thief]) == 0)
	end)
end

tests["teleporting home with a carried weapon is rejected and the weapon goes back"] = function()
	runtime(function(s)
		local victimData, thiefData = s.profiles[s.victim], s.profiles[s.thief]
		startCarry(s)
		s.now += 0.2
		s.thiefRoot.Position = pos(100) -- 100 studs in one 0.2 s heartbeat
		WorkshopService.stepCarries()
		assert(WorkshopService.carryOf(s.thief) == nil, "carry ended")
		assert(victimData.weapons.w1 ~= nil and victimData.showcase[1] == "w1" and Economy.weaponCount(thiefData) == 0, "weapon stayed home")
		-- hopping in short teleports is caught too
		s.now += 1000
		s.thiefRoot.Position = pos(0)
		startCarry(s)
		local at = 0
		local caught = false
		for _ = 1, 10 do
			at += 15
			s.now += 0.2 -- 75 studs/s
			s.thiefRoot.Position = pos(at)
			WorkshopService.stepCarries()
			if WorkshopService.carryOf(s.thief) == nil then
				caught = true
				break
			end
		end
		assert(caught and Economy.weaponCount(thiefData) == 0, "speed hack caught before reaching home")
		-- a lag spike that delivers 2 s of normal walking at once is fine
		s.now += 1000
		s.thiefRoot.Position = pos(0)
		startCarry(s)
		s.now += 1.5
		s.thiefRoot.Position = pos(30)
		WorkshopService.stepCarries()
		assert(WorkshopService.carryOf(s.thief) ~= nil, "lag spike tolerated")
	end)
end

tests["a workshop's lock and lock cooldown are cleared when it changes hands"] = function()
	runtime(function(s)
		assert(WorkshopService.lockForge(s.victim))
		local lock = WorkshopService.lockState(1)
		assert(lock.lockedUntil > s.now and lock.nextLockAt > s.now)
		s.thiefRoot.Position = pos(0)
		-- the owner leaves and the plot is released; a new owner joins
		WorkshopService.resetPlot(1)
		lock = WorkshopService.lockState(1)
		assert(lock.lockedUntil == 0 and lock.nextLockAt == 0, "clean lock for the next owner")
		assert(WorkshopService.lockForge(s.victim), "the new owner can lock right away")
	end)
end

tests["durable transfer: the victim save failing puts the weapon back"] = function()
	runtime(function(s)
		local victimData, thiefData = s.profiles[s.victim], s.profiles[s.thief]
		s.saveFails = { [s.victim] = true }
		startCarry(s)
		walk(s, 100)
		assert(victimData.weapons.w1 ~= nil and victimData.showcase[1] == "w1", "restored to its podium")
		assert(next(victimData.outbox or {}) == nil and Economy.weaponCount(thiefData) == 0, "nothing delivered")
		assert((victimData.weaponsLost or 0) == 0)
	end)
end

tests["durable transfer: a crash at any stage never duplicates or destroys the weapon"] = function()
	runtime(function(s)
		local ts = 5000 -- w1's value identifies its copies
		-- Stage A: crash after the victim's save but before the thief received anything.
		s.persisted[s.victim] = deepCopy(s.profiles[s.victim])
		s.persisted[s.thief] = deepCopy(s.profiles[s.thief])
		s.saveFails = { [s.thief] = true }
		startCarry(s)
		walk(s, 100)
		assert(next(s.persisted[s.victim].outbox) ~= nil and s.persisted[s.victim].weapons.w1 == nil, "victim saved with the weapon parked in the outbox")
		assert(countCopies({ s.persisted[s.victim], s.persisted[s.thief] }, ts) == 1, "exactly one durable copy")
		-- crash: both reload from what was saved
		s.profiles[s.victim] = deepCopy(s.persisted[s.victim])
		s.profiles[s.thief] = deepCopy(s.persisted[s.thief])
		s.saveFails = nil
		WorkshopService.retryOutbox(s.victim) -- the victim's profile loads on a new server
		assert(Economy.weaponCount(s.profiles[s.thief]) == 1, "the thief receives it")
		assert(next(s.profiles[s.victim].outbox) == nil, "outbox acknowledged")
		assert(countCopies({ s.persisted[s.victim], s.persisted[s.thief] }, ts) <= 2 and countCopies({ s.profiles[s.victim], s.profiles[s.thief] }, ts) == 1)
		-- Stage B: the outbox entry is re-sent again (e.g. the ack never saved): no duplicate.
		local entryId, entry = next(s.persisted[s.victim].outbox)
		s.profiles[s.victim].outbox = { [entryId] = deepCopy(entry) }
		WorkshopService.retryOutbox(s.victim)
		assert(Economy.weaponCount(s.profiles[s.thief]) == 1, "re-delivery is ignored")
		-- Stage C: the thief is not on this server: the delivery goes to their saved profile.
		s.profiles[s.victim].outbox = { [entryId] = deepCopy(entry) }
		s.thief.Parent = nil
		WorkshopService.retryOutbox(s.victim)
		assert(#s.messages == 1 and s.messages[1].to == s.thief.UserId, "queued as a profile message")
		assert(next(s.profiles[s.victim].outbox) == nil)
		-- the thief loads and processes the message (twice: crash before it was marked processed)
		local fresh = s.profiles[s.thief]
		assert(WorkshopService.onMessage(s.thief, fresh, s.messages[1].message))
		assert(WorkshopService.onMessage(s.thief, fresh, s.messages[1].message))
		assert(Economy.weaponCount(fresh) == 1, "the message is applied once")
		-- a message for a thief who never had it applies exactly once
		local other = Economy.newProfile()
		assert(WorkshopService.onMessage(s.thief, other, s.messages[1].message))
		assert(WorkshopService.onMessage(s.thief, other, s.messages[1].message))
		assert(Economy.weaponCount(other) == 1 and other.weapons[next(other.weapons)].st == 1)
		assert(not WorkshopService.onMessage(s.thief, other, { kind = "other" }), "unknown messages are not consumed")
	end)
end

tests["durable transfer: a victim who left mid-save keeps whatever their final save holds"] = function()
	runtime(function(s)
		local victimData = s.profiles[s.victim]
		-- the victim's confirmation never arrives because their session is being released
		s.onSave = function(player)
			if player == s.victim then
				s.profiles[s.victim] = nil
				return false
			end
		end
		startCarry(s)
		walk(s, 100)
		assert(victimData.weapons.w1 == nil and next(victimData.outbox) ~= nil, "the released data carries the weapon in its outbox")
		assert(Economy.weaponCount(s.profiles[s.thief]) == 0, "nothing given without a confirmed victim save")
		-- the victim rejoins later; their saved outbox is delivered exactly once
		s.onSave = nil
		s.profiles[s.victim] = victimData
		WorkshopService.retryOutbox(s.victim)
		WorkshopService.retryOutbox(s.victim)
		assert(Economy.weaponCount(s.profiles[s.thief]) == 1 and next(victimData.outbox) == nil)
	end)
end

tests["stolen weapons keep their full value; old trophies above your metal sell like your best metal"] = function()
	local holder = Economy.newProfile()
	holder.unlockedTier = 3
	local top = ForgeMath.rollWeapon({ NextNumber = function() return 0.999 end } :: any, 20, 2, 5, { id = "s", mult = 7 })
	local stolen = table.clone(top)
	stolen.st = 1
	assert(Economy.usableValue(holder, stolen, 1) == top.v, "a stolen weapon sells for its full value")
	holder.weapons.s = stolen
	local ok, sold = Economy.sellWeapons(holder, { "s" }, nil, 1)
	assert(ok and sold.coins == top.v and holder.coins == top.v, "the booth pays the full value")
	-- an own trophy above the current metal (kept through an evolution) is capped
	local cap = ForgeMath.valueFor(3, top.r, top.q, top.t ~= nil, 0, top.c, 1)
	assert(Economy.usableValue(holder, top, 1) == cap and cap < top.v, "own trophy above the current metal is capped")
	local own = table.clone(top)
	own.m, own.v = 3, 1234
	assert(Economy.usableValue(holder, own, 1) == 1234, "own weapons in unlocked metals are worth their full value")
	holder.unlockedTier = 20
	assert(Economy.usableValue(holder, top, 1) == top.v, "reaching the metal again restores the full value")
	-- display income for a stolen weapon uses its value with the normal current-tier cap
	holder.unlockedTier = 3
	assert(math.abs(Economy.displayIncome(holder, stolen, 1) - math.min(top.v, ForgeMath.maxValue(3, 1)) * Balance.display.incomePerSecond) < 1e-6)
end

return tests
