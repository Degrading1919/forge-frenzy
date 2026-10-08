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
	assert(thief.highestWeaponValue == 5000)
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

-- Runs fn with two fake workshops: thief owns plot 2 (x = 100), victim plot 1 (x = 0).
local function runtime(fn: (any) -> ())
	local savedWorld = table.clone(WorkshopService.world)
	local savedPlayers = rawget(Players, "GetPlayers")
	local state: any = { now = 1000, saved = 0, notes = {}, owned = {} }
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
		saveNow = function()
			state.saved += 1
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

-- Walks a steal to the point where the thief is carrying the weapon.
local function startCarry(s: any, slot: number?)
	slot = slot or 1
	s.thiefRoot.Position = pos(0) -- standing at the podium
	assert(WorkshopService.stealBegin(s.thief, 1, slot))
	s.now += Logic.STEAL_HOLD_SEC
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
		s.now += Logic.STEAL_HOLD_SEC
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
		s.thiefRoot.Position = pos(100)
		WorkshopService.stepCarries()
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
		-- the thief may try again after their personal cooldown (the per-podium cooldown is
		-- keyed by the victim's UserId on real Player instances; its rule is covered by canSteal)
		s.victimRoot.Position = pos(0)
		s.thiefRoot.Position = pos(0)
		local soon, soonWhy = WorkshopService.stealBegin(s.thief, 1, 1)
		assert(not soon and soonWhy == "StealCooldown", "a failed attempt still counts toward the thief's cooldown")
		s.now += Logic.STEAL_COOLDOWN_SEC + 1
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
		s.thiefRoot.Position = pos(100)
		WorkshopService.stepCarries()
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
		s.thiefRoot.Position = pos(100)
		WorkshopService.stepCarries() -- delivered
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

return tests
