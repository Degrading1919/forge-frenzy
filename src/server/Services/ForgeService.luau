--!strict
--[[
	ForgeService — server-owned forging sessions.

	Flow per forge: heat (heatSec) -> strike window (windowSec) -> server rolls -> reveal
	(revealSec) -> next forge allowed. Material is checked at start and spent at the roll, so an
	abandoned session costs nothing and nothing is ever refunded.

	Luck comes only from the server: manual luck from strikes counted inside the window
	(ForgeMath strike state: window-bounded, 20 per second max, clamped 1..5); auto modes use
	fixed luck (free 1.5, premium 4). Clients only send intent (start / strike / resolve).

	Auto modes loop until stopAuto, the player leaves, ingots run out or inventory fills; each
	new result auto-keeps the previous pending weapon, and `stopped` fires with the reason.

	profile.settings.autoSellBelow (rarity index, 0 = off) requires CollectionMagnet. Preferences
	are retained when ownership lapses, but ignored. Free automatic modes still use autoKeepFrom.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local DataService = require(script.Parent.DataService)
local ProductionService = require(script.Parent.ProductionService)

local ForgeService = {}

ForgeService.completed = Instance.new("BindableEvent") -- (player, weapon, luck, auto, validStrikes, extraWeapons)
ForgeService.stopped = Instance.new("BindableEvent") -- (player, reason) when an auto loop ends
-- (player, { sessionId, phase = "heat"|"strike"|"quench"|"done"|"cancelled"|"stopped", reason? })
ForgeService.phase = Instance.new("BindableEvent")

-- Overridable for tests.
ForgeService.rng = Random.new()
ForgeService.clock = os.clock
ForgeService.delay = function(seconds: number, fn: () -> ())
	task.delay(seconds, fn)
end

type Mode = "manual" | "free" | "premium"

type Session = {
	id: string,
	mode: Mode,
	materialIndex: number,
	classIndex: number,
	timing: Economy.Timing,
	windowStart: number,
	completeAt: number,
	readyAt: number,
	strikes: ForgeMath.StrikeState?,
	done: boolean,
	auto: boolean,
	profile: Economy.Profile,
	evolutionRank: number,
	rolls: number,
}

-- Timer jitter allowance so an auto loop firing right at readyAt is not rejected as Busy.
local READY_TOLERANCE_SEC = 0.05

local sessions: { [Player]: Session } = {}
local nextSessionId = 0

local function owns(player: Player, key: string): boolean
	local monetization = ProductionService._service("MonetizationService")
	if not monetization or type(monetization.owns) ~= "function" then
		return false
	end
	local ok, owned = pcall(monetization.owns, player, key)
	return ok and owned == true
end

local function canUsePaidRandom(player: Player): boolean
	local monetization = ProductionService._service("MonetizationService")
	if not monetization or type(monetization.canOfferPaidRandom) ~= "function" then
		return false
	end
	local ok, allowed = pcall(monetization.canOfferPaidRandom, player)
	return ok and allowed == true
end

local function isValidMode(mode: any): boolean
	return mode == "manual" or mode == "free" or mode == "premium"
end

local complete: (Player, string) -> ()

local function firePhase(player: Player, sessionId: string, phase: string, reason: string?)
	ForgeService.phase:Fire(player, { sessionId = sessionId, phase = phase, reason = reason })
end

local function begin(player: Player, classIndex: any, materialIndex: any, mode: any): (boolean, any)
	if not isValidMode(mode) then
		return false, "InvalidMode"
	end
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	if mode == "premium" and not owns(player, "PremiumAutoForge") then
		return false, "NotOwned"
	end
	local paidAllowed = false
	if mode == "premium" or owns(player, "MultiForge") then
		paidAllowed = canUsePaidRandom(player)
	end
	if mode == "premium" and not paidAllowed then
		return false, "PaidRandomRestricted"
	end
	-- Optional entitlement/policy hooks may yield. Never start against a released profile.
	if DataService.get(player) ~= data then
		return false, "NotLoaded"
	end
	local now = ForgeService.clock()
	local current = sessions[player]
	if current and (not current.done or now < current.readyAt - READY_TOLERANCE_SEC) then
		return false, "Busy"
	end
	local ok, err = Economy.canForge(data, materialIndex, classIndex)
	if not ok then
		return false, err
	end

	local timing = Economy.forgeTiming(data, mode, ProductionService.bonuses(player))
	nextSessionId += 1
	local windowStart = now + timing.heatSec
	local windowEnd = windowStart + timing.windowSec
	local grace = if mode == "manual" then Balance.forge.manual.latencyGraceSec else 0
	local session: Session = {
		id = "f" .. nextSessionId,
		mode = mode,
		materialIndex = materialIndex,
		classIndex = classIndex,
		timing = timing,
		windowStart = windowStart,
		completeAt = windowEnd + grace,
		readyAt = math.huge,
		strikes = if mode == "manual" then ForgeMath.newStrikeState(windowStart, timing.windowSec) else nil,
		done = false,
		auto = mode ~= "manual",
		profile = data,
		evolutionRank = data.evolutionRank or 0,
		rolls = if paidAllowed and owns(player, "MultiForge") then 2 else 1,
	}
	sessions[player] = session
	local id = session.id
	firePhase(player, id, "heat")
	ForgeService.delay(timing.heatSec, function()
		if sessions[player] == session and not session.done then
			firePhase(player, id, "strike")
		end
	end)
	ForgeService.delay(session.completeAt - now, function()
		complete(player, id)
	end)
	return true, {
		sessionId = id,
		heatSec = timing.heatSec,
		windowSec = timing.windowSec,
		revealSec = timing.revealSec,
	}
end

--[[
	Starts a forge. mode: "manual" | "free" | "premium" (premium needs the PremiumAutoForge
	entitlement). Returns (true, { sessionId, heatSec, windowSec, revealSec }) or (false, code):
	InvalidMode, NotLoaded, NotOwned, Busy, InvalidMaterial, InvalidClass, NoMaterial, InventoryFull.

	Note: Main.server.luau also calls every service's start() with no arguments as its lifecycle
	hook; that call is a no-op here. `ForgeService.begin` is the same function without the clash.
]]
function ForgeService.start(player: Player?, classIndex: any, materialIndex: any, mode: any): (boolean, any)
	if player == nil then
		return true, nil -- lifecycle start(): nothing to do
	end
	return begin(player, classIndex, materialIndex, mode)
end
ForgeService.begin = begin

-- Registers one hammer strike for the player's current manual session. Returns (counted, validCount).
function ForgeService.strike(player: Player, sessionId: any): (boolean, any)
	local session = sessions[player]
	if not session or session.id ~= sessionId or session.done or not session.strikes then
		return false, "NoSession"
	end
	local counted = ForgeMath.registerStrike(session.strikes, ForgeService.clock())
	return counted, session.strikes.valid
end

local function stopWith(player: Player, session: Session, reason: string)
	if session.auto then
		session.auto = false
		ForgeService.stopped:Fire(player, reason)
		firePhase(player, session.id, "stopped", reason)
	end
end

complete = function(player: Player, sessionId: string)
	local session = sessions[player]
	if not session or session.id ~= sessionId or session.done then
		return
	end
	session.done = true
	session.readyAt = math.huge -- a yielding policy check cannot open a second forge

	local data = DataService.get(player)
	if not data then
		sessions[player] = nil
		return
	end
	local function cancel(reason: string)
		session.readyAt = ForgeService.clock()
		firePhase(player, session.id, "cancelled", reason)
		stopWith(player, session, reason)
	end
	if data ~= session.profile or (data.evolutionRank or 0) ~= session.evolutionRank then
		cancel("ProgressReset")
		return
	end
	local paidAllowed = false
	if session.mode == "premium" or session.rolls > 1 then
		paidAllowed = canUsePaidRandom(player)
	end
	if session.mode == "premium" then
		if not owns(player, "PremiumAutoForge") then
			cancel("NotOwned")
			return
		elseif not paidAllowed then
			cancel("PaidRandomRestricted")
			return
		end
	end
	-- Re-check after optional hooks so resets/rejoins cannot spend a new profile's ingots.
	if sessions[player] ~= session or DataService.get(player) ~= data or (data.evolutionRank or 0) ~= session.evolutionRank then
		cancel("ProgressReset")
		return
	end
	local luck = if session.strikes
		then ForgeMath.strikeLuck(session.strikes)
		else ForgeMath.autoLuck(session.mode) :: number
	local settings = data.settings
	local sellBelow = if owns(player, "CollectionMagnet") and type(settings) == "table" then settings.autoSellBelow else nil
	local keepFrom = if type(settings) == "table" and type(settings.autoKeepFrom) == "number" then settings.autoKeepFrom else 4
	local extraSellBelow = if session.mode ~= "manual" then math.max(sellBelow or 0, keepFrom) else sellBelow
	local rolls = if session.rolls > 1 and paidAllowed and owns(player, "MultiForge") then 2 else 1
	local ok, batch = Economy.completeForgeBatch(data, session.materialIndex, session.classIndex, luck, ForgeService.rng, os.time(), rolls, sellBelow, extraSellBelow)
	if not ok then
		cancel(batch)
		return
	end
	local result = batch.weapon
	session.readyAt = ForgeService.clock() + session.timing.revealSec
	DataService.markDirty(player)
	firePhase(player, session.id, "quench")
	ForgeService.completed:Fire(player, result, luck, session.mode ~= "manual", if session.strikes then session.strikes.valid else 0, batch.extraWeapons)
	ForgeService.delay(session.timing.revealSec, function()
		if sessions[player] == session then
			firePhase(player, session.id, "done")
		end
	end)

	if session.auto then
		ForgeService.delay(session.timing.revealSec, function()
			local latest = sessions[player]
			if latest ~= session or not session.auto or player.Parent ~= Players then
				return
			end
			local okNext, err = begin(player, session.classIndex, session.materialIndex, session.mode)
			if not okNext then
				stopWith(player, session, err)
			end
		end)
	end
end

-- Test hook: completes the current session immediately (timers are not awaited).
function ForgeService._completeNow(player: Player)
	local session = sessions[player]
	if session then
		complete(player, session.id)
	end
end

function ForgeService.session(player: Player): Session?
	return sessions[player]
end

-- Ends the auto loop after the current forge finishes.
function ForgeService.stopAuto(player: Player): (boolean, any)
	local session = sessions[player]
	if not session or not session.auto then
		return false, "NotAuto"
	end
	stopWith(player, session, "Stopped")
	return true, nil
end

-- Sells or keeps the pending result. Idempotent: a repeat finds nothing pending.
function ForgeService.resolve(player: Player, action: any): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	local ok, result = Economy.resolvePending(data, action)
	if ok then
		DataService.markDirty(player)
	end
	return ok, result
end

-- Sells kept weapons by id (showcased ones are skipped). Returns { sold = {id}, coins }.
function ForgeService.sellWeapons(player: Player, ids: any): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	local ok, result = Economy.sellWeapons(data, ids)
	if ok then
		DataService.markDirty(player)
	end
	return ok, result
end

-- Sells one kept weapon (the SellWeapon remote). Same rules as sellWeapons.
function ForgeService.sellKept(player: Player, id: any): (boolean, any)
	return ForgeService.sellWeapons(player, { id })
end

-- Places a kept weapon on pedestal `slot`, or clears the slot when id is nil or "".
function ForgeService.setShowcase(player: Player, slot: any, id: any): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	local ok, result = Economy.setShowcase(data, slot, id)
	if ok then
		DataService.markDirty(player)
	end
	return ok, result
end

-- Phase lengths the player's next manual forge would use (for UI before starting).
function ForgeService.timings(player: Player): Economy.Timing?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	return Economy.forgeTiming(data, "manual", ProductionService.bonuses(player))
end

-- Puts a kept weapon on (or takes it off) a workshop showcase pedestal.
function ForgeService.toggleShowcase(player: Player, id: any): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	local ok, result = Economy.toggleShowcase(data, id)
	if ok then
		DataService.markDirty(player)
	end
	return ok, result
end

-- Exact odds for the disclosure UI at the luck a mode implies (manual shows the 5x ceiling).
function ForgeService.odds(mode: any): ForgeMath.OddsTable
	return ForgeMath.oddsTable(ForgeMath.autoLuck(mode) or ForgeMath.MAX_LUCK)
end

function ForgeService.init()
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return ForgeService
