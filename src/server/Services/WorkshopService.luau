--!strict
--[[
	WorkshopService — the social tycoon layer of a workshop (docs/21 §8-11, docs/22):
	build pads, display income and its cash collector, Forge Lock and weapon stealing.

	Profile fields used: pads, showcase, weapons, bank (Economy), weaponsForged.
	Session-only state (never saved): lock timers and in-flight steals.

	Stealing is playful and recoverable:
	  * A thief walks into another workshop, holds the steal prompt on a podium for
	    STEAL_HOLD_SEC (server-timed between StealBegin and StealCommit), and then carries the
	    weapon, slowed down, with a glowing marker over their head.
	  * The owner gets an alert. Touching the thief (within TAG_RANGE) returns the weapon to its
	    podium. So does the thief dying, leaving, or not getting home within CARRY_SEC.
	  * Only when the thief reaches their own workshop does ownership transfer: the weapon leaves
	    the victim's profile and enters the thief's backpack in one non-yielding step.
	  * While a weapon is being carried it stays in the victim's profile (it cannot be sold or
	    moved), so a disconnect at any moment can never duplicate or destroy it.
	  * Locked workshops, new players (shield) and full backpacks cannot be stolen from/into.

	Forge Lock: the owner presses the lock button; red lasers close the workshop for LOCK_SEC.
	Anyone else inside is pushed out and nobody else can enter or start a steal. The lock can be
	used again LOCK_COOLDOWN_SEC after it ends.

	`Logic` holds the pure rules so specs can run them without Studio. World geometry and
	characters are supplied through WorkshopService.world (set by Net/Plots).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))

local WorkshopService = {}
local Logic = {}
WorkshopService.Logic = Logic

Logic.LOCK_SEC = 30
Logic.LOCK_COOLDOWN_SEC = 60
Logic.STEAL_HOLD_SEC = 2.5
Logic.STEAL_HOLD_TOLERANCE = 0.3
Logic.CARRY_SEC = 40
Logic.TAG_RANGE = 7
Logic.STEAL_COOLDOWN_SEC = 20
Logic.SLOT_COOLDOWN_SEC = 90
-- Players who have forged fewer weapons than this cannot be stolen from (new player shield).
Logic.SHIELD_FORGES = 25
Logic.CARRY_SPEED_MULT = 0.7

WorkshopService.changed = Instance.new("BindableEvent") -- (kind, payload) for the world glue
WorkshopService.notify = Instance.new("BindableEvent") -- (player, text, kind)

--------------------------------------------------------------------------------
-- Pure rules
--------------------------------------------------------------------------------

export type LockState = { lockedUntil: number, nextLockAt: number }

function Logic.newLock(): LockState
	return { lockedUntil = 0, nextLockAt = 0 }
end

function Logic.isLocked(lock: LockState, now: number): boolean
	return now < lock.lockedUntil
end

function Logic.lock(lock: LockState, now: number): (boolean, any)
	if now < lock.lockedUntil then
		return false, "AlreadyLocked"
	end
	if now < lock.nextLockAt then
		return false, "LockCooldown"
	end
	lock.lockedUntil = now + Logic.LOCK_SEC
	lock.nextLockAt = lock.lockedUntil + Logic.LOCK_COOLDOWN_SEC
	return true, lock.lockedUntil
end

function Logic.shielded(profile: any): boolean
	return (profile.weaponsForged or 0) < Logic.SHIELD_FORGES
end

export type Carry = {
	thief: any,
	victim: any,
	victimPlot: number,
	slot: number,
	weaponId: string,
	weapon: any,
	startedAt: number,
	deadline: number,
}

--[[
	Validates a steal before the carry begins. `thiefProfile`, `victimProfile` are the live
	profiles; `slot` the victim's podium. Returns (true, weapon) or (false, code).
]]
function Logic.canSteal(thiefProfile: any, victimProfile: any, slot: any, lock: LockState, now: number, carriedIds: { [string]: boolean }, slotCooldownUntil: number?): (boolean, any)
	if thiefProfile == victimProfile then
		return false, "OwnWeapon"
	end
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > Balance.inventory.showcaseSlots then
		return false, "InvalidSlot"
	end
	if Logic.isLocked(lock, now) then
		return false, "ForgeLocked"
	end
	if Logic.shielded(victimProfile) then
		return false, "Shielded"
	end
	if slotCooldownUntil and now < slotCooldownUntil then
		return false, "SlotCooldown"
	end
	local id = victimProfile.showcase[slot]
	local weapon = if type(id) == "string" and id ~= "" then victimProfile.weapons[id] else nil
	if not weapon then
		return false, "EmptySlot"
	end
	if carriedIds[id] then
		return false, "AlreadyCarried"
	end
	if not Economy.hasRoom(thiefProfile) then
		return false, "InventoryFull"
	end
	return true, weapon
end

--[[
	Completes a delivered steal atomically: the weapon leaves the victim (backpack and podium)
	and enters the thief's backpack under a fresh id. Returns (true, newWeapon) or (false, code)
	when the weapon no longer exists in the victim's profile.
]]
function Logic.transfer(thiefProfile: any, victimProfile: any, carry: Carry, thiefName: string?, victimName: string?): (boolean, any)
	local weapon = victimProfile.weapons[carry.weaponId]
	if not weapon then
		return false, "Gone"
	end
	if not Economy.hasRoom(thiefProfile) then
		return false, "InventoryFull"
	end
	victimProfile.weapons[carry.weaponId] = nil
	local at = table.find(victimProfile.showcase, carry.weaponId)
	if at then
		victimProfile.showcase[at] = ""
	end
	local copy = table.clone(weapon)
	copy.id = Economy.nextWeaponId(thiefProfile)
	copy.sf = victimName -- "stolen from", shown on the weapon card
	thiefProfile.weapons[copy.id] = copy
	thiefProfile.weaponsStolen = (thiefProfile.weaponsStolen or 0) + 1
	victimProfile.weaponsLost = (victimProfile.weaponsLost or 0) + 1
	thiefProfile.highestWeaponValue = math.max(thiefProfile.highestWeaponValue or 0, copy.v)
	return true, copy
end

--------------------------------------------------------------------------------
-- Runtime
--------------------------------------------------------------------------------

local deps: any = {
	getProfile = function(_player: any): any
		return nil
	end,
	markDirty = function(_player: any) end,
	saveNow = function(_player: any) end,
	now = function(): number
		return workspace:GetServerTimeNow()
	end,
	owns = function(_player: any, _key: string): boolean
		return false
	end,
	cashMultiplier = function(_player: any): number
		return 1
	end,
}

--[[
	World hooks, set by Net/Plots:
	  plotOf(player) -> plotIndex (0 when none)
	  ownerOf(plotIndex) -> Player?
	  inPlot(plotIndex, position) -> boolean
	  podiumPosition(plotIndex, slot) -> Vector3?
	  padPosition(plotIndex, padId) -> Vector3?
	  collectorPosition(plotIndex) -> Vector3?
	  lockButtonPosition(plotIndex) -> Vector3?
	  eject(plotIndex, character) pushes a character out of the workshop
]]
WorkshopService.world = {
	plotOf = function(_player: any): number
		return 0
	end,
	ownerOf = function(_plot: number): any
		return nil
	end,
	inPlot = function(_plot: number, _position: Vector3): boolean
		return false
	end,
	podiumPosition = function(_plot: number, _slot: number): Vector3?
		return nil
	end,
	padPosition = function(_plot: number, _padId: string): Vector3?
		return nil
	end,
	collectorPosition = function(_plot: number): Vector3?
		return nil
	end,
	lockButtonPosition = function(_plot: number): Vector3?
		return nil
	end,
	eject = function(_plot: number, _character: Model) end,
} :: any

local locks: { [number]: LockState } = {}
local carries: { [any]: Carry } = {} -- thief -> carry
local stealIntent: { [any]: { plot: number, slot: number, at: number } } = {}
local lastSteal: { [any]: number } = {}
local slotCooldown: { [string]: number } = {} -- "victimUserId:slot" -> until

local function lockOf(plot: number): LockState
	local lock = locks[plot]
	if not lock then
		lock = Logic.newLock()
		locks[plot] = lock
	end
	return lock
end

local function rootPart(player: any): BasePart?
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function near(player: any, position: Vector3?, range: number): boolean
	local root = rootPart(player)
	return root ~= nil and position ~= nil and (root.Position - position).Magnitude <= range
end
WorkshopService.near = near

-- Ids of weapons currently being carried away from `victim`.
function WorkshopService.carriedFrom(victim: any): { [string]: boolean }
	local ids = {}
	for _, carry in carries do
		if carry.victim == victim then
			ids[carry.weaponId] = true
		end
	end
	return ids
end

function WorkshopService.carryOf(thief: any): Carry?
	return carries[thief]
end

function WorkshopService.lockState(plot: number): LockState
	return lockOf(plot)
end

local function publishLock(plot: number)
	WorkshopService.changed:Fire("lock", { plot = plot, lockedUntil = lockOf(plot).lockedUntil, nextLockAt = lockOf(plot).nextLockAt })
end

local function setCarryVisual(thief: any, carry: Carry?)
	if typeof(thief) ~= "Instance" then
		return
	end
	if carry then
		local w = carry.weapon
		thief:SetAttribute("Carrying", string.format("%d,%d,%d,%s", w.m, w.c, w.r, w.d))
	else
		thief:SetAttribute("Carrying", nil)
	end
	local character = thief.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local base = thief:GetAttribute("BaseWalkSpeed") or humanoid.WalkSpeed
		humanoid.WalkSpeed = if carry then base * Logic.CARRY_SPEED_MULT else base
	end
end

local function endCarry(thief: any, outcome: string)
	local carry = carries[thief]
	if not carry then
		return
	end
	carries[thief] = nil
	setCarryVisual(thief, nil)
	WorkshopService.changed:Fire("carry", { thief = thief, victim = carry.victim, slot = carry.slot, outcome = outcome })
	local victimName = if typeof(carry.victim) == "Instance" then carry.victim.DisplayName else "the owner"
	local thiefName = if typeof(thief) == "Instance" then thief.DisplayName else "A thief"
	if outcome == "Returned" then
		WorkshopService.notify:Fire(thief, "Caught! The weapon went back to " .. victimName, "bad")
		WorkshopService.notify:Fire(carry.victim, "You got your weapon back!", "good")
	elseif outcome == "Timeout" or outcome == "ThiefLost" then
		WorkshopService.notify:Fire(thief, "Too slow! The weapon flew back home", "bad")
		WorkshopService.notify:Fire(carry.victim, "Your weapon came back home", "good")
	elseif outcome == "Stolen" then
		WorkshopService.notify:Fire(carry.victim, thiefName .. " stole your weapon! Lock your forge to stay safe", "bad")
	end
	slotCooldown[tostring(if typeof(carry.victim) == "Instance" then carry.victim.UserId else 0) .. ":" .. carry.slot] = deps.now() + Logic.SLOT_COOLDOWN_SEC
	if typeof(thief) == "Instance" then
		deps.markDirty(thief)
	end
	if typeof(carry.victim) == "Instance" then
		deps.markDirty(carry.victim)
	end
end

-- The thief started holding the steal prompt on `plot` podium `slot`.
function WorkshopService.stealBegin(thief: any, plot: any, slot: any): (boolean, any)
	if type(plot) ~= "number" or type(slot) ~= "number" then
		return false, "InvalidSlot"
	end
	local victim = WorkshopService.world.ownerOf(plot)
	if not victim or victim == thief then
		return false, "OwnWeapon"
	end
	if carries[thief] then
		return false, "AlreadyCarrying"
	end
	local now = deps.now()
	-- The lock is the most important answer, so it comes before personal cooldowns.
	if Logic.isLocked(lockOf(plot), now) then
		return false, "ForgeLocked"
	end
	if lastSteal[thief] and now - lastSteal[thief] < Logic.STEAL_COOLDOWN_SEC then
		return false, "StealCooldown"
	end
	if not near(thief, WorkshopService.world.podiumPosition(plot, slot), 12) then
		return false, "TooFar"
	end
	local thiefProfile, victimProfile = deps.getProfile(thief), deps.getProfile(victim)
	if not thiefProfile or not victimProfile then
		return false, "NotLoaded"
	end
	local ok, err = Logic.canSteal(thiefProfile, victimProfile, slot, lockOf(plot), now, WorkshopService.carriedFrom(victim), slotCooldown[victim.UserId .. ":" .. slot])
	if not ok then
		return false, err
	end
	stealIntent[thief] = { plot = plot, slot = slot, at = now }
	WorkshopService.notify:Fire(victim, thief.DisplayName .. " is stealing from your workshop!", "bad")
	return true, nil
end

-- The thief finished holding the prompt. Starts the carry if everything still holds.
function WorkshopService.stealCommit(thief: any, plot: any, slot: any): (boolean, any)
	local intent = stealIntent[thief]
	stealIntent[thief] = nil
	if not intent or intent.plot ~= plot or intent.slot ~= slot then
		return false, "NoIntent"
	end
	local now = deps.now()
	if now - intent.at < Logic.STEAL_HOLD_SEC - Logic.STEAL_HOLD_TOLERANCE then
		return false, "TooFast"
	end
	if now - intent.at > Logic.STEAL_HOLD_SEC + 5 then
		return false, "TooSlow"
	end
	local victim = WorkshopService.world.ownerOf(plot)
	if not victim or victim == thief or carries[thief] then
		return false, "OwnWeapon"
	end
	if not near(thief, WorkshopService.world.podiumPosition(plot, slot), 12) then
		return false, "TooFar"
	end
	local thiefProfile, victimProfile = deps.getProfile(thief), deps.getProfile(victim)
	if not thiefProfile or not victimProfile then
		return false, "NotLoaded"
	end
	local ok, weapon = Logic.canSteal(thiefProfile, victimProfile, slot, lockOf(plot), now, WorkshopService.carriedFrom(victim), slotCooldown[victim.UserId .. ":" .. slot])
	if not ok then
		return false, weapon
	end
	lastSteal[thief] = now
	local carry: Carry = {
		thief = thief,
		victim = victim,
		victimPlot = plot,
		slot = slot,
		weaponId = victimProfile.showcase[slot],
		weapon = table.clone(weapon),
		startedAt = now,
		deadline = now + Logic.CARRY_SEC,
	}
	carries[thief] = carry
	setCarryVisual(thief, carry)
	WorkshopService.changed:Fire("carry", { thief = thief, victim = victim, slot = slot, outcome = "Started", weapon = carry.weapon, deadline = carry.deadline })
	WorkshopService.notify:Fire(victim, thief.DisplayName .. " grabbed your " .. ForgeMath.weaponName(weapon) .. "! Tag them to get it back!", "bad")
	WorkshopService.notify:Fire(thief, "Run home to keep it!", "good")
	return true, { weapon = carry.weapon, deadline = carry.deadline }
end

function WorkshopService.stealCancel(thief: any)
	stealIntent[thief] = nil
end

-- One pass of carry resolution: delivery, tags, timeouts. Called by the heartbeat loop.
function WorkshopService.stepCarries()
	local now = deps.now()
	for thief, carry in carries do
		local victim = carry.victim
		if thief.Parent ~= Players then
			endCarry(thief, "ThiefLost")
			continue
		end
		if victim.Parent ~= Players then
			endCarry(thief, "VictimLeft")
			continue
		end
		local thiefRoot, victimRoot = rootPart(thief), rootPart(victim)
		local humanoid = thief.Character and thief.Character:FindFirstChildOfClass("Humanoid")
		if not thiefRoot or not humanoid or humanoid.Health <= 0 then
			endCarry(thief, "ThiefLost")
			continue
		end
		if victimRoot and (victimRoot.Position - thiefRoot.Position).Magnitude <= Logic.TAG_RANGE then
			endCarry(thief, "Returned")
			continue
		end
		if now > carry.deadline then
			endCarry(thief, "Timeout")
			continue
		end
		local home = WorkshopService.world.plotOf(thief)
		if home > 0 and WorkshopService.world.inPlot(home, thiefRoot.Position) then
			local thiefProfile, victimProfile = deps.getProfile(thief), deps.getProfile(victim)
			if thiefProfile and victimProfile then
				local ok, copy = Logic.transfer(thiefProfile, victimProfile, carry, thief.DisplayName, victim.DisplayName)
				if ok then
					WorkshopService.notify:Fire(thief, "Stolen! " .. ForgeMath.weaponName(copy) .. " is in your backpack", "good")
					endCarry(thief, "Stolen")
					task.spawn(deps.saveNow, thief)
					task.spawn(deps.saveNow, victim)
				else
					endCarry(thief, "Gone")
				end
			else
				endCarry(thief, "ThiefLost")
			end
		end
	end
end

-- Owner presses the lock button in their workshop.
function WorkshopService.lockForge(player: any): (boolean, any)
	local plot = WorkshopService.world.plotOf(player)
	if plot <= 0 then
		return false, "NoWorkshop"
	end
	if not near(player, WorkshopService.world.lockButtonPosition(plot), 14) then
		return false, "TooFar"
	end
	local ok, result = Logic.lock(lockOf(plot), deps.now())
	if ok then
		publishLock(plot)
	end
	return ok, result
end

-- Pushes everyone but the owner out of locked workshops. Called by the heartbeat loop.
function WorkshopService.enforceLocks()
	local now = deps.now()
	for plot, lock in locks do
		if Logic.isLocked(lock, now) then
			local owner = WorkshopService.world.ownerOf(plot)
			for _, other in Players:GetPlayers() do
				if other ~= owner then
					local root = rootPart(other)
					if root and WorkshopService.world.inPlot(plot, root.Position) then
						WorkshopService.world.eject(plot, other.Character)
						local left = math.ceil(lock.lockedUntil - now)
						WorkshopService.notify:Fire(other, string.format("Locked! %s's forge opens in %ds", if owner then owner.DisplayName else "This", left), "bad")
					end
				end
			end
		end
	end
end

-- Builds a pad the player is standing on.
function WorkshopService.buyPad(player: any, padId: any): (boolean, any)
	local data = deps.getProfile(player)
	if not data then
		return false, "NotLoaded"
	end
	local plot = WorkshopService.world.plotOf(player)
	if plot <= 0 or type(padId) ~= "string" or not near(player, WorkshopService.world.padPosition(plot, padId), 12) then
		return false, "TooFar"
	end
	local ok, result = Economy.buyPad(data, padId)
	if ok then
		deps.markDirty(player)
		WorkshopService.changed:Fire("pads", { player = player })
	end
	return ok, result
end

-- Collects display cash at the workshop collector.
function WorkshopService.collect(player: any): (boolean, any)
	local data = deps.getProfile(player)
	if not data then
		return false, "NotLoaded"
	end
	local plot = WorkshopService.world.plotOf(player)
	if not deps.owns(player, "CollectionMagnet") and (plot <= 0 or not near(player, WorkshopService.world.collectorPosition(plot), 12)) then
		return false, "TooFar"
	end
	local ok, result = Economy.collectBank(data)
	if ok then
		deps.markDirty(player)
	end
	return ok, result
end

-- Display income per second for the snapshot (carried weapons earn nothing).
function WorkshopService.incomePerSec(player: any): number
	local data = deps.getProfile(player)
	if not data then
		return 0
	end
	return Economy.displayIncomeTotal(data, deps.cashMultiplier(player), WorkshopService.carriedFrom(player))
end

-- Accrues display income for every loaded player. Called once per second.
function WorkshopService.tickIncome(dt: number)
	for _, player in Players:GetPlayers() do
		local data = deps.getProfile(player)
		if data then
			local added = Economy.accrueDisplay(data, dt, deps.cashMultiplier(player), 1, WorkshopService.carriedFrom(player))
			if added > 0 and deps.owns(player, "CollectionMagnet") then
				Economy.collectBank(data)
			end
		end
	end
end

-- Offline display income on join (at reduced efficiency, capped by the collector size).
function WorkshopService.settleOffline(player: any, seconds: number)
	local data = deps.getProfile(player)
	if data and seconds > 0 then
		Economy.accrueDisplay(data, seconds, deps.cashMultiplier(player), Balance.display.offlineEfficiency)
	end
end

-- A weapon being carried away cannot be moved, displayed elsewhere or sold.
function WorkshopService.isCarried(victim: any, weaponId: string): boolean
	for _, carry in carries do
		if carry.victim == victim and carry.weaponId == weaponId then
			return true
		end
	end
	return false
end

function WorkshopService.publicState(plot: number): any
	local lock = lockOf(plot)
	return { lockedUntil = lock.lockedUntil, nextLockAt = lock.nextLockAt }
end

function WorkshopService._inject(overrides: { [string]: any })
	for key, value in overrides do
		deps[key] = value
	end
end

function WorkshopService._reset()
	table.clear(locks)
	table.clear(carries)
	table.clear(stealIntent)
	table.clear(lastSteal)
	table.clear(slotCooldown)
end

function WorkshopService.init()
	local DataService = require(script.Parent:WaitForChild("DataService")) :: any
	deps.getProfile = function(player)
		return DataService.get(player)
	end
	deps.markDirty = function(player)
		DataService.markDirty(player)
	end
	deps.saveNow = function(player)
		pcall(DataService.saveNow, player, 15)
	end
	deps.owns = function(player, key)
		local found = script.Parent:FindFirstChild("MonetizationService")
		if not found then
			return false
		end
		local ok, owned = pcall((require(found) :: any).owns, player, key)
		return ok and owned == true
	end
	deps.cashMultiplier = function(player)
		local found = script.Parent:FindFirstChild("ForgeService")
		if not found then
			return 1
		end
		return (require(found) :: any).cashMultiplier(player)
	end
	-- Offline display income uses the same lastSeen gap production settled.
	DataService.profileLoaded.Event:Connect(function(player, data)
		local gap = tonumber(data.offlineGap) or 0
		data.offlineGap = nil
		if gap > 0 then
			WorkshopService.settleOffline(player, gap)
		end
	end)
end

function WorkshopService.start()
	Players.PlayerRemoving:Connect(function(player)
		if carries[player] then
			endCarry(player, "ThiefLost")
		end
		for thief, carry in carries do
			if carry.victim == player then
				endCarry(thief, "VictimLeft")
			end
		end
		stealIntent[player] = nil
		lastSteal[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		local acc = 0
		while true do
			task.wait(0.2)
			local now = os.clock()
			local dt = now - last
			last = now
			local ok, err = pcall(WorkshopService.stepCarries)
			if not ok then
				warn("[WorkshopService] carries", err)
			end
			ok, err = pcall(WorkshopService.enforceLocks)
			if not ok then
				warn("[WorkshopService] locks", err)
			end
			acc += dt
			if acc >= 1 then
				ok, err = pcall(WorkshopService.tickIncome, acc)
				if not ok then
					warn("[WorkshopService] income", err)
				end
				acc = 0
			end
		end
	end)
end

return WorkshopService
