--!strict
--[[
	WorkshopService — the social tycoon layer of a workshop (docs/21 §8-11, docs/22):
	build pads, display income and its cash collector, Forge Lock and weapon stealing.

	Profile fields used: pads, showcase, weapons, bank (Economy), weaponsForged, and the steal
	ledger: outbox (weapons stolen from this player that are still being delivered) and xferIn
	(ids of stolen weapons this player already received).
	Session-only state (never saved): lock timers, steal holds and carries.

	Stealing is playful and recoverable:
	  * A thief holds the steal prompt on a podium. The hold time grows with the weapon's value
	    (Shared/Steal: 2 s for starter weapons up to 8 s for the best endgame weapons). The server
	    times the hold from StealBegin to StealCommit and pins the exact weapon at StealBegin: if
	    that weapon is moved, replaced, sold or locked away, or the thief walks off or dies, the
	    hold is cancelled and nothing can be stolen.
	  * The thief then carries the weapon, slowed down, with a glowing marker over their head.
	    The owner gets an alert when the hold starts and when the weapon is grabbed. Touching the
	    thief (within TAG_RANGE) returns it. So does the thief dying, leaving, moving faster than
	    a running carrier can (teleporting), or not getting home within CARRY_SEC.
	  * While a weapon is carried it stays in the victim's profile (it cannot be sold or moved).
	  * Delivery is a durable two-step transfer (see "Steal ledger" below), so a failed save, a
	    disconnect or a server crash can delay a stolen weapon but never duplicate or destroy it.
	  * Locked workshops, new players (shield) and full backpacks cannot be stolen from/into.

	Forge Lock: the owner presses the lock button; red lasers close the workshop for LOCK_SEC.
	Anyone else inside is pushed out and nobody else can enter or start a steal; holds already in
	progress are cancelled. The lock can be used again LOCK_COOLDOWN_SEC after it ends. Lock state
	belongs to the workshop's current owner: it is cleared whenever a workshop changes hands.

	`Logic` holds the pure rules so specs can run them without Studio. World geometry and
	characters are supplied through WorkshopService.world (set by Net/Plots).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local Steal = require(Shared:WaitForChild("Steal"))
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))

local WorkshopService = {}
local Logic = {}
WorkshopService.Logic = Logic

Logic.LOCK_SEC = 30
Logic.LOCK_COOLDOWN_SEC = 60
-- Hold to steal: Steal.holdSeconds(value), 2..8 s. The server accepts a commit this much early
-- (network latency) and up to HOLD_LATE_SEC late.
Logic.STEAL_HOLD_TOLERANCE = 0.3
Logic.HOLD_LATE_SEC = 5
-- How close to the podium the thief must stay for the whole hold.
Logic.HOLD_RANGE = 12
Logic.CARRY_SEC = 40
Logic.TAG_RANGE = 7
Logic.STEAL_COOLDOWN_SEC = 20
Logic.SLOT_COOLDOWN_SEC = 90
-- Players who have forged fewer weapons than this cannot be stolen from (new player shield).
Logic.SHIELD_FORGES = 25
Logic.CARRY_SPEED_MULT = 0.7
-- Carry movement check (horizontal studs). A carrier walks at 28 * 0.7 = 19.6 studs/s. The
-- allowance refills at MAX_CARRY_SPEED and can bank up to MOVE_BURST studs, so a lag spike that
-- replicates about a second and a half of walking at once is fine, but a teleport is not.
Logic.MAX_CARRY_SPEED = 30
Logic.MOVE_BURST = 30
Logic.MOVE_SLACK = 10
-- A carry is never delivered sooner than this, even between neighbouring workshops, so there is
-- always a moment to tag the thief.
Logic.MIN_CARRY_SEC = 2
-- Stolen-weapon ids a profile remembers so a re-sent delivery is never applied twice.
Logic.LEDGER_SIZE = 1000
-- A thief's pending steal whose victim never saved it is forgotten after this long. It is far
-- longer than any save in flight (saves time out after 15 s; final release saves retry briefly).
Logic.PENDING_EXPIRE_SEC = 30 * 60
-- How often an online thief re-checks pending steals against the victim's saved profile.
Logic.PENDING_CHECK_SEC = 5 * 60

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

-- Seconds of holding needed to steal `weapon` (shared with the client prompt).
function Logic.holdSec(weapon: any): number
	return Steal.holdSeconds(weapon and weapon.v)
end

-- Horizontal distance between two positions (falling or jumping never counts as travel).
function Logic.flat(a: any, b: any): number
	if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	return (a - b).Magnitude
end

export type Move = { pos: any, at: number, budget: number }

function Logic.newMove(pos: any, now: number): Move
	return { pos = pos, at = now, budget = Logic.MOVE_BURST }
end

-- Records a new position sample. False when the carrier covered more ground than running allows.
function Logic.moveOk(move: Move, pos: any, now: number): boolean
	local dt = math.max(0, now - move.at)
	move.budget = math.min(Logic.MOVE_BURST, move.budget + Logic.MAX_CARRY_SPEED * dt) - Logic.flat(pos, move.pos)
	move.pos, move.at = pos, now
	return move.budget >= -Logic.MOVE_SLACK
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
	move: Move?,
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

-- True when podium `slot` still shows exactly the weapon pinned at the start of a hold.
function Logic.sameWeapon(victimProfile: any, slot: number, weaponId: string, pinned: any): boolean
	if victimProfile.showcase[slot] ~= weaponId then
		return false
	end
	local weapon = victimProfile.weapons[weaponId]
	return weapon ~= nil and weapon.v == pinned.v and weapon.ts == pinned.ts and weapon.m == pinned.m and weapon.r == pinned.r
end

--[[
	Steal ledger. Two profiles cannot be saved in one atomic write, so a delivered steal moves the
	weapon in three durable steps. Neither player has to come back for the thief to get it.

	  0. markPending (thief): thief.xferPending[id] = { from = victim UserId, wid, at } is saved
	     and confirmed first. Until then the weapon stays in the victim's backpack, protected like
	     a carried weapon (it cannot be sold, moved or earn).
	  1. beginTransfer (victim): the weapon leaves the victim's backpack and podium and is parked
	     in victim.outbox[id] with the thief's UserId. The victim's save is confirmed. If it fails
	     while the victim is still here, cancelTransfer puts the weapon back.
	  2. receive (thief): the weapon is added to the thief's backpack and the id is recorded in
	     thief.xferIn (and removed from xferPending) in the same profile, so receiving the same id
	     twice does nothing. Once the thief's save is confirmed (or the delivery was queued as a
	     ProfileStore message to the thief's saved profile), ack removes the outbox entry.

	Recovery runs from both sides:
	  * the victim's profile re-sends its outbox when it loads and every 30 s while loaded;
	  * the thief's profile, when it loads and every few minutes, reads the victim's saved profile
	    (ProfileStore:GetAsync, read-only) for each pending id and receives the weapon from the
	    victim's outbox. So a thief always gets a committed steal even if the victim never plays
	    again. A pending id whose victim never committed (no outbox entry) expires after
	    PENDING_EXPIRE_SEC.

	At every point a weapon is in exactly one durable place: the victim's saved backpack (step 1
	never saved), the victim's saved outbox, or the thief's saved backpack with its id in xferIn
	(any re-delivery is ignored).
]]
function Logic.beginTransfer(victimProfile: any, carry: Carry, transferId: string, toUserId: number, toName: string?, fromName: string?, now: number): (boolean, any)
	local weapon = victimProfile.weapons[carry.weaponId]
	if not weapon or (carry.weapon and (weapon.v ~= carry.weapon.v or weapon.ts ~= carry.weapon.ts)) then
		return false, "Gone"
	end
	victimProfile.outbox = if type(victimProfile.outbox) == "table" then victimProfile.outbox else {}
	if victimProfile.outbox[transferId] then
		return false, "Duplicate"
	end
	victimProfile.weapons[carry.weaponId] = nil
	local at = table.find(victimProfile.showcase, carry.weaponId)
	if at then
		victimProfile.showcase[at] = ""
	end
	local entry = { w = table.clone(weapon), to = toUserId, toName = toName, fromName = fromName, slot = at or carry.slot, at = now }
	victimProfile.outbox[transferId] = entry
	victimProfile.weaponsLost = (victimProfile.weaponsLost or 0) + 1
	return true, entry
end

-- Undoes step 1 while the transfer has not been delivered. Returns the restored weapon or nil.
function Logic.cancelTransfer(victimProfile: any, transferId: string): any?
	local entry = type(victimProfile.outbox) == "table" and victimProfile.outbox[transferId]
	if not entry then
		return nil
	end
	victimProfile.outbox[transferId] = nil
	local weapon = table.clone(entry.w)
	if victimProfile.weapons[weapon.id] ~= nil then
		weapon.id = Economy.nextWeaponId(victimProfile)
	end
	victimProfile.weapons[weapon.id] = weapon
	local slot = entry.slot
	if type(slot) == "number" and slot <= Economy.showcaseSlots(victimProfile) and victimProfile.showcase[slot] == "" then
		victimProfile.showcase[slot] = weapon.id
	end
	victimProfile.weaponsLost = math.max(0, (victimProfile.weaponsLost or 0) - 1)
	return weapon
end

-- Step 2: gives the thief the weapon once per transfer id. Returns (true, weapon) or
-- (false, "Duplicate") when this id was already received. A full backpack never loses a
-- delivered weapon: it may go over the limit until the player sells.
-- Step 0: the thief's profile remembers a steal it is owed before the victim gives it up.
function Logic.markPending(thiefProfile: any, transferId: string, fromUserId: number, weaponId: string, now: number)
	thiefProfile.xferPending = if type(thiefProfile.xferPending) == "table" then thiefProfile.xferPending else {}
	thiefProfile.xferPending[transferId] = { from = fromUserId, wid = weaponId, at = now }
end

function Logic.clearPending(thiefProfile: any, transferId: string)
	if type(thiefProfile.xferPending) == "table" then
		thiefProfile.xferPending[transferId] = nil
	end
end

--[[
	Thief-side recovery for one pending steal, given the victim's saved profile data (`victimSaved`,
	read-only; {} when the victim has no save). Returns "received" (weapon added), "waiting" (not
	resolvable yet), "expired" (the victim never committed; pending dropped) or "done".
]]
function Logic.resolvePending(thiefProfile: any, transferId: string, victimSaved: any, now: number): (string, any)
	local pending = type(thiefProfile.xferPending) == "table" and thiefProfile.xferPending[transferId]
	if not pending then
		return "done", nil
	end
	if type(thiefProfile.xferIn) == "table" and thiefProfile.xferIn[transferId] then
		thiefProfile.xferPending[transferId] = nil
		return "done", nil
	end
	local entry = type(victimSaved) == "table" and type(victimSaved.outbox) == "table" and victimSaved.outbox[transferId]
	if type(entry) == "table" and type(entry.w) == "table" then
		local received, copy = Logic.receive(thiefProfile, transferId, entry, now)
		return if received then "received" else "done", copy
	end
	if now - (tonumber(pending.at) or 0) > Logic.PENDING_EXPIRE_SEC then
		thiefProfile.xferPending[transferId] = nil
		return "expired", nil
	end
	return "waiting", nil
end

function Logic.receive(thiefProfile: any, transferId: string, entry: any, now: number): (boolean, any)
	thiefProfile.xferIn = if type(thiefProfile.xferIn) == "table" then thiefProfile.xferIn else {}
	Logic.clearPending(thiefProfile, transferId)
	if thiefProfile.xferIn[transferId] then
		return false, "Duplicate"
	end
	local copy = table.clone(entry.w)
	copy.id = Economy.nextWeaponId(thiefProfile)
	copy.sf = entry.fromName or copy.sf -- "stolen from", shown on the weapon card
	copy.st = 1 -- stolen: always sells for its full value (Economy.usableValue)
	thiefProfile.weapons[copy.id] = copy
	thiefProfile.weaponsStolen = (thiefProfile.weaponsStolen or 0) + 1
	thiefProfile.xferIn[transferId] = now
	-- Keep the ledger bounded: forget the oldest ids first.
	local count, oldestId, oldestAt = 0, nil, math.huge
	for id, at in thiefProfile.xferIn do
		count += 1
		if at < oldestAt then
			oldestId, oldestAt = id, at
		end
	end
	if count > Logic.LEDGER_SIZE and oldestId then
		thiefProfile.xferIn[oldestId] = nil
	end
	return true, copy
end

function Logic.ack(victimProfile: any, transferId: string)
	if type(victimProfile.outbox) == "table" then
		victimProfile.outbox[transferId] = nil
	end
end

-- The whole transfer in one step (both profiles in memory, no saves): used by specs and tools.
function Logic.transfer(thiefProfile: any, victimProfile: any, carry: Carry, thiefName: string?, victimName: string?): (boolean, any)
	if not victimProfile.weapons[carry.weaponId] then
		return false, "Gone"
	end
	if not Economy.hasRoom(thiefProfile) then
		return false, "InventoryFull"
	end
	local id = "local-" .. tostring(carry.weaponId) .. "-" .. tostring(thiefProfile.nextWeaponId)
	local ok, entry = Logic.beginTransfer(victimProfile, carry, id, 0, thiefName, victimName, 0)
	if not ok then
		return false, entry
	end
	local received, copy = Logic.receive(thiefProfile, id, entry, 0)
	Logic.ack(victimProfile, id)
	return received, copy
end

--------------------------------------------------------------------------------
-- Runtime
--------------------------------------------------------------------------------

local deps: any = {
	getProfile = function(_player: any): any
		return nil
	end,
	markDirty = function(_player: any) end,
	-- Saves and waits for the save to be confirmed. Returns true only when it was.
	saveNow = function(_player: any): boolean
		return false
	end,
	-- Queues a message to a player's saved profile (ProfileStore:MessageAsync). Returns success.
	sendMessage = function(_userId: number, _message: any): boolean
		return false
	end,
	-- Reads another player's saved profile data (read-only, ProfileStore:GetAsync). Returns the
	-- data table, {} when they have no save, or nil when the read failed.
	viewProfile = function(_userId: number): any
		return nil
	end,
	playerByUserId = function(userId: number): any
		return Players:GetPlayerByUserId(userId)
	end,
	newId = function(): string
		return game:GetService("HttpService"):GenerateGUID(false)
	end,
	spawn = function(fn: (...any) -> (), ...: any)
		task.spawn(fn, ...)
	end,
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

type Intent = { plot: number, slot: number, victim: any, weaponId: string, weapon: any, at: number, holdSec: number }

local locks: { [number]: LockState } = {}
local carries: { [any]: Carry } = {} -- thief -> carry
local stealIntent: { [any]: Intent } = {}
local lastSteal: { [any]: number } = {}
local slotCooldown: { [string]: number } = {} -- "victimUserId:slot" -> until
local inFlight: { [string]: boolean } = {} -- transfer ids being saved/delivered right now
-- Delivered steals whose thief's pending record is still being saved: the weapon is still in the
-- victim's backpack and protected like a carried weapon.
local securing: { [string]: { victim: any, weaponId: string } } = {}

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

local function alive(player: any): boolean
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and rootPart(player) ~= nil
end

-- Ids of weapons currently being carried away from `victim`.
function WorkshopService.carriedFrom(victim: any): { [string]: boolean }
	local ids = {}
	for _, carry in carries do
		if carry.victim == victim then
			ids[carry.weaponId] = true
		end
	end
	for _, hold in securing do
		if hold.victim == victim then
			ids[hold.weaponId] = true
		end
	end
	return ids
end

function WorkshopService.carryOf(thief: any): Carry?
	return carries[thief]
end

function WorkshopService.intentOf(thief: any): Intent?
	return stealIntent[thief]
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

local function userIdOf(player: any): number
	return if player then (player.UserId or 0) else 0
end

local function endCarry(thief: any, outcome: string)
	local carry = carries[thief]
	if not carry then
		return
	end
	carries[thief] = nil
	setCarryVisual(thief, nil)
	WorkshopService.changed:Fire("carry", { thief = thief, victim = carry.victim, slot = carry.slot, outcome = outcome })
	local victimName = if carry.victim then carry.victim.DisplayName else "the owner"
	local thiefName = if thief then thief.DisplayName else "A thief"
	if outcome == "Returned" then
		WorkshopService.notify:Fire(thief, "Caught! The weapon went back to " .. victimName, "bad")
		WorkshopService.notify:Fire(carry.victim, "You got your weapon back!", "good")
	elseif outcome == "Timeout" or outcome == "ThiefLost" then
		WorkshopService.notify:Fire(thief, "Too slow! The weapon flew back home", "bad")
		WorkshopService.notify:Fire(carry.victim, "Your weapon came back home", "good")
	elseif outcome == "Invalid" then
		WorkshopService.notify:Fire(thief, "The weapon slipped away and flew back home", "bad")
		WorkshopService.notify:Fire(carry.victim, "Your weapon came back home", "good")
	elseif outcome == "Stolen" then
		WorkshopService.notify:Fire(carry.victim, thiefName .. " stole your weapon! Lock your forge to stay safe", "bad")
	end
	slotCooldown[tostring(userIdOf(carry.victim)) .. ":" .. carry.slot] = deps.now() + Logic.SLOT_COOLDOWN_SEC
	deps.markDirty(thief)
	deps.markDirty(carry.victim)
end

local function cancelIntent(thief: any, text: string?)
	if stealIntent[thief] then
		stealIntent[thief] = nil
		if text then
			WorkshopService.notify:Fire(thief, text, "bad")
		end
	end
end

-- The thief started holding the steal prompt on `plot` podium `slot`. Pins the exact weapon and
-- returns the hold time the server will enforce.
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
	if not near(thief, WorkshopService.world.podiumPosition(plot, slot), Logic.HOLD_RANGE) then
		return false, "TooFar"
	end
	local thiefProfile, victimProfile = deps.getProfile(thief), deps.getProfile(victim)
	if not thiefProfile or not victimProfile then
		return false, "NotLoaded"
	end
	local ok, weapon = Logic.canSteal(thiefProfile, victimProfile, slot, lockOf(plot), now, WorkshopService.carriedFrom(victim), slotCooldown[userIdOf(victim) .. ":" .. slot])
	if not ok then
		return false, weapon
	end
	local holdSec = Logic.holdSec(weapon)
	stealIntent[thief] = {
		plot = plot,
		slot = slot,
		victim = victim,
		weaponId = victimProfile.showcase[slot],
		weapon = table.clone(weapon),
		at = now,
		holdSec = holdSec,
	}
	WorkshopService.notify:Fire(victim, string.format("%s is stealing your %s! Lock your forge or chase them!", thief.DisplayName, ForgeMath.weaponName(weapon)), "bad")
	return true, { holdSec = holdSec }
end

-- The thief finished holding the prompt. Starts the carry only if the very same weapon is still
-- there and everything else still holds.
function WorkshopService.stealCommit(thief: any, plot: any, slot: any): (boolean, any)
	local intent = stealIntent[thief]
	stealIntent[thief] = nil
	if not intent or intent.plot ~= plot or intent.slot ~= slot then
		return false, "NoIntent"
	end
	local now = deps.now()
	if now - intent.at < intent.holdSec - Logic.STEAL_HOLD_TOLERANCE then
		return false, "TooFast"
	end
	if now - intent.at > intent.holdSec + Logic.HOLD_LATE_SEC then
		return false, "TooSlow"
	end
	local victim = WorkshopService.world.ownerOf(plot)
	if not victim or victim ~= intent.victim or victim == thief or carries[thief] then
		return false, "Moved"
	end
	if not alive(thief) or not near(thief, WorkshopService.world.podiumPosition(plot, slot), Logic.HOLD_RANGE) then
		return false, "TooFar"
	end
	local thiefProfile, victimProfile = deps.getProfile(thief), deps.getProfile(victim)
	if not thiefProfile or not victimProfile then
		return false, "NotLoaded"
	end
	local ok, weapon = Logic.canSteal(thiefProfile, victimProfile, slot, lockOf(plot), now, WorkshopService.carriedFrom(victim), slotCooldown[userIdOf(victim) .. ":" .. slot])
	if not ok then
		return false, weapon
	end
	if not Logic.sameWeapon(victimProfile, slot, intent.weaponId, intent.weapon) then
		return false, "Moved"
	end
	lastSteal[thief] = now
	local root = rootPart(thief)
	local carry: Carry = {
		thief = thief,
		victim = victim,
		victimPlot = plot,
		slot = slot,
		weaponId = intent.weaponId,
		weapon = table.clone(weapon),
		startedAt = now,
		deadline = now + Logic.CARRY_SEC,
		move = if root then Logic.newMove(root.Position, now) else nil,
	}
	carries[thief] = carry
	setCarryVisual(thief, carry)
	WorkshopService.changed:Fire("carry", { thief = thief, victim = victim, slot = slot, outcome = "Started", weapon = carry.weapon, deadline = carry.deadline })
	WorkshopService.notify:Fire(victim, thief.DisplayName .. " grabbed your " .. ForgeMath.weaponName(weapon) .. "! Tag them to get it back!", "bad")
	WorkshopService.notify:Fire(thief, "Run home to keep it!", "good")
	return true, { weapon = carry.weapon, deadline = carry.deadline }
end

-- The thief let go. A real ProximityPrompt fires its hold-ended event (sent as StealCancel) at the
-- moment the hold completes, before Triggered (StealCommit) arrives. So a cancel only counts while
-- the hold is still short of its full time; after that it is the completion, and the commit that
-- follows decides.
function WorkshopService.stealCancel(thief: any)
	local intent = stealIntent[thief]
	if intent and deps.now() - intent.at < intent.holdSec - Logic.STEAL_HOLD_TOLERANCE then
		stealIntent[thief] = nil
	end
end

-- Cancels holds that can no longer succeed: the thief walked off or died, the workshop changed
-- hands or locked, or the pinned weapon moved. Called by the heartbeat loop.
function WorkshopService.stepIntents()
	local now = deps.now()
	for thief, intent in stealIntent do
		if thief.Parent ~= Players or not alive(thief) then
			stealIntent[thief] = nil
		elseif not near(thief, WorkshopService.world.podiumPosition(intent.plot, intent.slot), Logic.HOLD_RANGE) then
			cancelIntent(thief, "You let go of the podium")
		elseif WorkshopService.world.ownerOf(intent.plot) ~= intent.victim or Logic.isLocked(lockOf(intent.plot), now) then
			cancelIntent(thief, "The forge locked!")
		else
			local victimProfile = deps.getProfile(intent.victim)
			if not victimProfile or not Logic.sameWeapon(victimProfile, intent.slot, intent.weaponId, intent.weapon) then
				cancelIntent(thief, "The weapon was moved!")
			elseif now - intent.at > intent.holdSec + Logic.HOLD_LATE_SEC then
				stealIntent[thief] = nil
			end
		end
	end
end

-- Delivers one outbox entry of `victimData` to its thief (step 2 of the steal ledger). Safe to
-- call repeatedly: the thief's ledger ignores ids it already received.
local function deliver(victimData: any, transferId: string)
	local entry = type(victimData.outbox) == "table" and victimData.outbox[transferId]
	if not entry or inFlight[transferId] then
		return
	end
	inFlight[transferId] = true
	local ok, err = pcall(function()
		local thief = deps.playerByUserId(entry.to)
		local thiefData = thief and deps.getProfile(thief)
		if thiefData then
			local received, copy = Logic.receive(thiefData, transferId, entry, deps.now())
			if received then
				WorkshopService.notify:Fire(thief, "Stolen! " .. ForgeMath.weaponName(copy) .. " is in your backpack", "good")
				deps.markDirty(thief)
			end
			if deps.saveNow(thief) then
				Logic.ack(victimData, transferId)
			end
			-- An unconfirmed save keeps the outbox entry; the retry re-delivers and the ledger
			-- drops the duplicate.
		elseif deps.sendMessage(entry.to, { kind = "steal", id = transferId, w = entry.w, from = entry.fromName }) then
			Logic.ack(victimData, transferId)
		end
	end)
	inFlight[transferId] = nil
	if not ok then
		warn("[WorkshopService] deliver", err)
	end
end
WorkshopService._deliver = deliver

-- Steps 0, 1 and 2 of a delivered steal (runs in its own thread: saves yield).
local function finishTransfer(thief: any, victim: any, carry: Carry, transferId: string)
	inFlight[transferId] = true
	securing[transferId] = { victim = victim, weaponId = carry.weaponId }
	local function abandon(text: string?)
		securing[transferId] = nil
		inFlight[transferId] = nil
		deps.markDirty(victim)
		if text then
			WorkshopService.notify:Fire(thief, text, "bad")
		end
	end
	-- Step 0: the thief's save records what it is owed.
	local thiefData = deps.getProfile(thief)
	if not thiefData then
		return abandon(nil)
	end
	Logic.markPending(thiefData, transferId, userIdOf(victim), carry.weaponId, deps.now())
	local okThief, thiefSaved = pcall(deps.saveNow, thief)
	if not (okThief and thiefSaved) then
		if deps.getProfile(thief) == thiefData then
			Logic.clearPending(thiefData, transferId)
		end
		-- If the pending record did reach the save anyway, it expires: the victim keeps the weapon.
		return abandon("The steal couldn't be saved, so the weapon went back home")
	end
	-- Step 1: the victim gives it up and that is saved.
	local victimData = deps.getProfile(victim)
	local ok = victimData ~= nil and Logic.beginTransfer(victimData, carry, transferId, userIdOf(thief), thief.DisplayName, victim.DisplayName, deps.now())
	securing[transferId] = nil
	if not ok then
		if deps.getProfile(thief) == thiefData then
			Logic.clearPending(thiefData, transferId)
		end
		return abandon("The weapon was gone before it could be saved")
	end
	deps.markDirty(victim)
	local okVictim, victimSaved = pcall(deps.saveNow, victim)
	inFlight[transferId] = nil
	if not (okVictim and victimSaved) then
		if deps.getProfile(victim) == victimData and type(victimData.outbox) == "table" and victimData.outbox[transferId] then
			Logic.cancelTransfer(victimData, transferId)
			deps.markDirty(victim)
			if deps.getProfile(thief) == thiefData then
				Logic.clearPending(thiefData, transferId)
			end
			WorkshopService.notify:Fire(thief, "The steal couldn't be saved, so the weapon went back home", "bad")
		end
		-- Otherwise the victim already left and their final save decides: if it holds the outbox
		-- entry, the thief's pending record collects it (thief-side recovery); if not, the
		-- pending record expires and the victim still has the weapon.
		return
	end
	-- Step 2.
	deliver(victimData, transferId)
end

-- One pass of carry resolution: delivery, tags, teleport checks, timeouts. Called by the
-- heartbeat loop.
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
		if carry.move == nil then
			carry.move = Logic.newMove(thiefRoot.Position, now)
		elseif not Logic.moveOk(carry.move :: Move, thiefRoot.Position, now) then
			endCarry(thief, "Invalid")
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
		if home > 0 and now - carry.startedAt >= Logic.MIN_CARRY_SEC and WorkshopService.world.inPlot(home, thiefRoot.Position) then
			local thiefProfile, victimProfile = deps.getProfile(thief), deps.getProfile(victim)
			if not thiefProfile or not victimProfile then
				endCarry(thief, "ThiefLost")
				continue
			end
			local held = victimProfile.weapons[carry.weaponId]
			if not held or held.v ~= carry.weapon.v or held.ts ~= carry.weapon.ts then
				endCarry(thief, "Gone")
				continue
			end
			local transferId = deps.newId()
			-- Protect the weapon before the carry ends, so there is no moment it could be sold.
			securing[transferId] = { victim = victim, weaponId = carry.weaponId }
			inFlight[transferId] = true
			endCarry(thief, "Stolen")
			WorkshopService.notify:Fire(thief, "Got it! Locking it in your backpack...", "good")
			deps.spawn(finishTransfer, thief, victim, carry, transferId)
		end
	end
end

-- Re-delivers every outbox entry of a loaded player (after a failed save, a crash or a rejoin).
function WorkshopService.retryOutbox(player: any)
	local data = deps.getProfile(player)
	if not data or type(data.outbox) ~= "table" then
		return
	end
	for transferId in data.outbox do
		if not inFlight[transferId] then
			deps.spawn(deliver, data, transferId)
		end
	end
end

-- Thief-side recovery: collects pending steals from the victims' saved profiles. Runs when the
-- thief's profile loads and every PENDING_CHECK_SEC while they play.
function WorkshopService.resolvePending(player: any)
	local data = deps.getProfile(player)
	if not data or type(data.xferPending) ~= "table" then
		return
	end
	for transferId, pending in data.xferPending do
		if inFlight[transferId] then
			continue -- this server is still delivering it
		end
		local view = deps.viewProfile(tonumber(pending.from) or 0)
		if view == nil then
			continue -- read failed: try again later
		end
		if deps.getProfile(player) ~= data then
			return -- the session ended while reading
		end
		local result, copy = Logic.resolvePending(data, transferId, view, deps.now())
		if result == "received" then
			WorkshopService.notify:Fire(player, "You kept your loot: " .. ForgeMath.weaponName(copy), "good")
		end
		if result ~= "waiting" then
			deps.markDirty(player)
		end
	end
end

-- A delivery queued to this player's saved profile while they were elsewhere.
function WorkshopService.onMessage(player: any, data: any, message: any): boolean
	if type(message) ~= "table" or message.kind ~= "steal" or type(message.id) ~= "string" or type(message.w) ~= "table" then
		return false
	end
	local received, copy = Logic.receive(data, message.id, { w = message.w, fromName = message.from }, deps.now())
	if received then
		WorkshopService.notify:Fire(player, "You kept your loot: " .. ForgeMath.weaponName(copy), "good")
		deps.markDirty(player)
	end
	return true
end

-- Clears a workshop's lock, cooldown and holds when it changes hands (owner left or joined).
function WorkshopService.resetPlot(plot: number)
	locks[plot] = nil
	for thief, intent in stealIntent do
		if intent.plot == plot then
			cancelIntent(thief, "That workshop's owner left")
		end
	end
	publishLock(plot)
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
		for thief, intent in stealIntent do
			if intent.plot == plot then
				cancelIntent(thief, "The forge locked!")
			end
		end
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
						-- A server teleport is not the carrier's own movement.
						local carry = carries[other]
						if carry then
							carry.move = nil
						end
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
	table.clear(inFlight)
	table.clear(securing)
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
		local ok, saved = pcall(DataService.saveNow, player, 15)
		return ok and saved == true
	end
	deps.sendMessage = function(userId, message)
		return DataService.sendMessage(userId, message)
	end
	deps.viewProfile = function(userId)
		return DataService.viewProfile(userId)
	end
	DataService.registerMessageHandler("steal", WorkshopService.onMessage)
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
		-- Weapons stolen from this player that were never confirmed delivered, and steals this
		-- player is still owed.
		WorkshopService.retryOutbox(player)
		task.spawn(WorkshopService.resolvePending, player)
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
		for thief, intent in stealIntent do
			if intent.victim == player then
				stealIntent[thief] = nil
			end
		end
	end)
	task.spawn(function()
		local last = os.clock()
		local acc, retryAcc, pendingAcc = 0, 0, 0
		while true do
			task.wait(0.2)
			local now = os.clock()
			local dt = now - last
			last = now
			local ok, err = pcall(WorkshopService.stepCarries)
			if not ok then
				warn("[WorkshopService] carries", err)
			end
			ok, err = pcall(WorkshopService.stepIntents)
			if not ok then
				warn("[WorkshopService] holds", err)
			end
			ok, err = pcall(WorkshopService.enforceLocks)
			if not ok then
				warn("[WorkshopService] locks", err)
			end
			pendingAcc += dt
			if pendingAcc >= Logic.PENDING_CHECK_SEC then
				pendingAcc = 0
				for _, player in Players:GetPlayers() do
					task.spawn(pcall, WorkshopService.resolvePending, player)
				end
			end
			retryAcc += dt
			if retryAcc >= 30 then
				retryAcc = 0
				for _, player in Players:GetPlayers() do
					pcall(WorkshopService.retryOutbox, player)
				end
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
