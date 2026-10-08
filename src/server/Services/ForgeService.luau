--!strict
--[[
	ForgeService — server-owned forging sessions, one per forge station (v2, docs/22).

	Flow per forge: heat (heatSec) -> strike window (windowSec) -> server rolls -> reveal
	(revealSec) -> next forge allowed. Ingots are checked at start and spent at the roll, so an
	abandoned or cancelled session costs nothing and nothing is ever refunded.

	Each workshop owns 1-3 forge stations (build pads). A station has a recipe (material +
	weapon type) and an automatic keep rule stored in profile.stations. A player can hammer
	manually at one station at a time, standing next to it; any station can run Auto Forge.

	Luck comes only from the server: manual luck from strikes counted inside the window
	(ForgeMath strike state: window-bounded, rate-guarded, clamped 1..5); auto modes use fixed
	luck (free 1.5, premium 4). Clients only send intent (begin / strike / stop / configure).

	Auto modes loop until stopped, the station is reconfigured, or the player leaves. When the
	vault runs out of a recipe's ingots the station waits (it does not stop) and resumes as soon
	as the ore line refills it. Auto results below the station's keep rarity are sold at once
	(the Auto Sell exception); everything else goes to the backpack.
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

-- (player, { station, results = { { weapon, sold, coins } }, luck, auto, strikes })
ForgeService.completed = Instance.new("BindableEvent")
ForgeService.stopped = Instance.new("BindableEvent") -- (player, station, reason) when an auto loop ends
-- (player, { station, sessionId, phase = "heat"|"strike"|"quench"|"done"|"cancelled"|"stopped"|"waiting", reason?, endsAt?, mode })
ForgeService.phase = Instance.new("BindableEvent")

-- Overridable for tests.
ForgeService.rng = Random.new()
ForgeService.clock = os.clock
-- Server time clients can compare against (workspace:GetServerTimeNow on the client).
ForgeService.serverTime = function(): number
	return workspace:GetServerTimeNow()
end
ForgeService.delay = function(seconds: number, fn: () -> ())
	task.delay(seconds, fn)
end
-- Set by the world glue: true when the player stands close enough to hammer at `station`.
ForgeService.nearStation = function(_player: Player, _station: number): boolean
	return true
end
-- How often a waiting auto forge re-checks the vault.
ForgeService.WAIT_RETRY_SEC = 1

type Mode = "manual" | "free" | "premium"

type Session = {
	id: string,
	station: number,
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
	waiting: boolean,
	profile: Economy.Profile,
	evolutionRank: number,
	rolls: number,
	endsAt: number, -- server time the current phase ends (for client countdowns)
	phaseName: string,
}

-- Timer jitter allowance so an auto loop firing right at readyAt is not rejected as Busy.
local READY_TOLERANCE_SEC = 0.05

local sessions: { [Player]: { [number]: Session } } = {}
local nextSessionId = 0

local function stationsOf(player: Player): { [number]: Session }
	local list = sessions[player]
	if not list then
		list = {}
		sessions[player] = list
	end
	return list
end

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

-- Permanent cash multiplier from evolution (weapons are worth more forever).
local function cashMultiplier(player: Player): number
	local evolution = ProductionService._service("EvolutionService")
	if evolution and type(evolution.bonuses) == "function" then
		local ok, bonuses = pcall(evolution.bonuses, player)
		if ok and type(bonuses) == "table" and type(bonuses.cash) == "number" then
			return math.max(1, bonuses.cash)
		end
	end
	return 1
end
ForgeService.cashMultiplier = cashMultiplier

local function isValidMode(mode: any): boolean
	return mode == "manual" or mode == "free" or mode == "premium"
end

local complete: (Player, number, string) -> ()

local function firePhase(player: Player, session: Session, phase: string, reason: string?, duration: number?)
	session.phaseName = phase
	session.endsAt = if duration then ForgeService.serverTime() + duration else 0
	ForgeService.phase:Fire(player, {
		station = session.station,
		sessionId = session.id,
		phase = phase,
		reason = reason,
		endsAt = session.endsAt,
		mode = session.mode,
		auto = session.auto,
	})
end

local function autoAllowed(data: Economy.Profile): boolean
	return (data.weaponsForged or 0) >= Balance.forge.autoUnlockAfterForges
end

local begin: (Player, any, any, Session?) -> (boolean, any)

-- Re-checks the vault for a waiting auto forge until it can start or is stopped.
local function scheduleWait(player: Player, station: number, mode: string, waiting: Session)
	ForgeService.delay(ForgeService.WAIT_RETRY_SEC, function()
		local list = sessions[player]
		if not list or list[station] ~= waiting or not waiting.auto or player.Parent ~= Players then
			return
		end
		local ok, err = begin(player, station, mode, waiting)
		if not ok then
			waiting.auto = false
			ForgeService.stopped:Fire(player, station, err)
			firePhase(player, waiting, "stopped", err)
		end
	end)
end

begin = function(player: Player, station: any, mode: any, resumeOf: Session?): (boolean, any)
	if not isValidMode(mode) then
		return false, "InvalidMode"
	end
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	if type(station) ~= "number" or data.stations[station] == nil then
		return false, "InvalidStation"
	end
	if mode == "premium" and not owns(player, "PremiumAutoForge") then
		return false, "NotOwned"
	end
	if mode ~= "manual" and not autoAllowed(data) then
		return false, "AutoLocked"
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
	local list = stationsOf(player)
	local now = ForgeService.clock()
	local current = list[station]
	if current and current ~= resumeOf then
		local running = not current.done or now < current.readyAt - READY_TOLERANCE_SEC
		if running and current.mode == "manual" then
			return false, "Busy"
		end
		if running or current.auto then
			-- Starting something new on a station replaces its auto loop cleanly.
			current.auto = false
			current.done = true
			firePhase(player, current, "cancelled", "Replaced")
		end
	end
	if mode == "manual" then
		if not ForgeService.nearStation(player, station) then
			return false, "TooFar"
		end
		for index, other in list do
			if index ~= station and other.mode == "manual" and not other.done then
				return false, "Busy"
			end
		end
	end
	local recipe = data.stations[station]
	local ok, err = Economy.canForge(data, recipe.m, recipe.c, mode ~= "manual")
	if not ok then
		if mode ~= "manual" and err == "NoMaterial" then
			-- Auto waits for ingots instead of stopping.
			if resumeOf and resumeOf.waiting and list[station] == resumeOf then
				scheduleWait(player, station, mode, resumeOf)
				return true, { sessionId = resumeOf.id, station = station, waiting = true }
			end
			nextSessionId += 1
			local waiting: Session = {
				id = "f" .. nextSessionId,
				station = station,
				mode = mode,
				materialIndex = recipe.m,
				classIndex = recipe.c,
				timing = Economy.forgeTiming(data, mode, ProductionService.bonuses(player)),
				windowStart = now,
				completeAt = now,
				readyAt = now,
				strikes = nil,
				done = true,
				auto = true,
				waiting = true,
				profile = data,
				evolutionRank = data.evolutionRank or 0,
				rolls = 1,
				endsAt = 0,
				phaseName = "waiting",
			}
			list[station] = waiting
			recipe.auto = mode
			firePhase(player, waiting, "waiting", "NoMaterial")
			scheduleWait(player, station, mode, waiting)
			return true, { sessionId = waiting.id, station = station, waiting = true }
		end
		return false, err
	end

	local timing = Economy.forgeTiming(data, mode, ProductionService.bonuses(player))
	nextSessionId += 1
	local windowStart = now + timing.heatSec
	local windowEnd = windowStart + timing.windowSec
	local grace = if mode == "manual" then Balance.forge.manual.latencyGraceSec else 0
	local session: Session = {
		id = "f" .. nextSessionId,
		station = station,
		mode = mode,
		materialIndex = recipe.m,
		classIndex = recipe.c,
		timing = timing,
		windowStart = windowStart,
		completeAt = windowEnd + grace,
		readyAt = math.huge,
		strikes = if mode == "manual" then ForgeMath.newStrikeState(windowStart, timing.windowSec) else nil,
		done = false,
		auto = mode ~= "manual",
		waiting = false,
		profile = data,
		evolutionRank = data.evolutionRank or 0,
		rolls = if paidAllowed and owns(player, "MultiForge") then 2 else 1,
		endsAt = 0,
		phaseName = "heat",
	}
	list[station] = session
	recipe.auto = if mode ~= "manual" then mode else nil
	firePhase(player, session, "heat", nil, timing.heatSec)
	ForgeService.delay(timing.heatSec, function()
		if list[station] == session and not session.done then
			firePhase(player, session, "strike", nil, timing.windowSec)
		end
	end)
	ForgeService.delay(session.completeAt - now, function()
		complete(player, station, session.id)
	end)
	return true, {
		sessionId = session.id,
		station = station,
		heatSec = timing.heatSec,
		windowSec = timing.windowSec,
		revealSec = timing.revealSec,
	}
end

--[[
	Starts a forge at `station`. mode: "manual" | "free" | "premium" (premium needs the
	PremiumAutoForge entitlement). Returns (true, { sessionId, station, heatSec, windowSec,
	revealSec } or { waiting = true }) or (false, code): InvalidMode, NotLoaded, InvalidStation,
	NotOwned, AutoLocked, Busy, TooFar, InvalidMaterial, InvalidClass, NoMaterial, InventoryFull.

	Main.server.luau also calls every service's start() with no arguments as its lifecycle hook;
	that call is a no-op here. `ForgeService.begin` is the same function without the clash.
]]
function ForgeService.start(player: Player?, station: any, mode: any): (boolean, any)
	if player == nil then
		return true, nil -- lifecycle start(): nothing to do
	end
	return begin(player, station, mode)
end
ForgeService.begin = function(player: Player, station: any, mode: any): (boolean, any)
	return begin(player, station, mode)
end

-- Registers one hammer strike for the player's current manual session. Returns (counted, validCount).
function ForgeService.strike(player: Player, sessionId: any): (boolean, any)
	for _, session in stationsOf(player) do
		if session.id == sessionId and not session.done and session.strikes then
			local counted = ForgeMath.registerStrike(session.strikes, ForgeService.clock())
			return counted, session.strikes.valid
		end
	end
	return false, "NoSession"
end

local function stopWith(player: Player, session: Session, reason: string)
	if session.auto then
		session.auto = false
		ForgeService.stopped:Fire(player, session.station, reason)
		firePhase(player, session, "stopped", reason)
	end
end

complete = function(player: Player, station: number, sessionId: string)
	local list = stationsOf(player)
	local session = list[station]
	if not session or session.id ~= sessionId or session.done then
		return
	end
	session.done = true
	session.readyAt = math.huge -- a yielding policy check cannot open a second forge

	local data = DataService.get(player)
	if not data then
		list[station] = nil
		return
	end
	local function cancel(reason: string)
		session.readyAt = ForgeService.clock()
		firePhase(player, session, "cancelled", reason)
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
	if list[station] ~= session or DataService.get(player) ~= data or (data.evolutionRank or 0) ~= session.evolutionRank then
		cancel("ProgressReset")
		return
	end
	local luck = if session.strikes
		then ForgeMath.strikeLuck(session.strikes)
		else ForgeMath.autoLuck(session.mode) :: number
	local recipe = data.stations[station]
	local rolls = if session.rolls > 1 and paidAllowed and owns(player, "MultiForge") then 2 else 1
	local ok, batch = Economy.completeForgeBatch(data, session.materialIndex, session.classIndex, luck, ForgeService.rng, os.time(), rolls, {
		mult = cashMultiplier(player),
		keepFrom = if session.mode ~= "manual" and recipe then recipe.keep else nil,
		allowFullBackpack = session.mode ~= "manual",
	})
	if not ok then
		if session.auto and batch == "NoMaterial" then
			-- Ingots were used elsewhere mid-forge: wait for more instead of stopping.
			session.readyAt = ForgeService.clock()
			local okNext = begin(player, station, session.mode, session)
			if not okNext then
				stopWith(player, session, batch)
			end
			return
		end
		cancel(batch)
		return
	end
	session.readyAt = ForgeService.clock() + session.timing.revealSec
	DataService.markDirty(player)
	firePhase(player, session, "quench", nil, session.timing.revealSec)
	ForgeService.completed:Fire(player, {
		station = station,
		results = batch.results,
		luck = luck,
		auto = session.mode ~= "manual",
		mode = session.mode,
		strikes = if session.strikes then session.strikes.valid else 0,
	})
	ForgeService.delay(session.timing.revealSec, function()
		if list[station] == session and not session.auto then
			firePhase(player, session, "done")
		end
	end)

	if session.auto then
		ForgeService.delay(session.timing.revealSec, function()
			if list[station] ~= session or not session.auto or player.Parent ~= Players then
				return
			end
			local okNext, err = begin(player, station, session.mode, session)
			if not okNext then
				stopWith(player, session, err)
			end
		end)
	end
end

-- Test hook: completes the station's current session immediately (timers are not awaited).
function ForgeService._completeNow(player: Player, station: number?)
	local list = stationsOf(player)
	local index = station or 1
	local session = list[index]
	if session then
		complete(player, index, session.id)
	end
end

function ForgeService.session(player: Player, station: number?): Session?
	return stationsOf(player)[station or 1]
end

-- Ends a station's auto loop at once (all stations when nil). The forge in progress is
-- abandoned, so no ingots are spent for it.
function ForgeService.stopAuto(player: Player, station: any): (boolean, any)
	local list = stationsOf(player)
	local stopped = false
	local data = DataService.get(player)
	if data then
		for index, recipe in data.stations do
			if station == nil or index == station then
				recipe.auto = nil
			end
		end
	end
	for index, session in list do
		if (station == nil or index == station) and session.auto then
			session.done = true
			session.readyAt = ForgeService.clock()
			stopWith(player, session, "Stopped")
			stopped = true
		end
	end
	if not stopped then
		return false, "NotAuto"
	end
	return true, nil
end

--[[
	Changes a station's recipe (material, weapon type) and auto keep rule. Any auto loop on the
	station stops cleanly first, so changing settings never answers "busy". A manual forge in
	progress is not interrupted.
]]
function ForgeService.configure(player: Player, station: any, materialIndex: any, classIndex: any, keep: any): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	local list = stationsOf(player)
	local session = if type(station) == "number" then list[station] else nil
	if session and session.mode == "manual" and not session.done then
		return false, "Busy"
	end
	local ok, result = Economy.configureStation(data, station, materialIndex, classIndex, keep)
	if not ok then
		return false, result
	end
	local wasAuto = session ~= nil and session.auto
	result.auto = nil
	if session and session.auto then
		session.done = true
		session.readyAt = ForgeService.clock()
		stopWith(player, session, "Reconfigured")
	end
	DataService.markDirty(player)
	return true, { station = result, stoppedAuto = wasAuto }
end

-- Per-station state for the client snapshot.
function ForgeService.status(player: Player): { [number]: any }
	local out = {}
	for index, session in stationsOf(player) do
		out[index] = {
			mode = session.mode,
			auto = session.auto,
			waiting = session.waiting and session.auto,
			phase = session.phaseName,
			endsAt = session.endsAt,
			sessionId = session.id,
		}
	end
	return out
end

-- Sells kept weapons by id (displayed ones are skipped). Returns { sold = {id}, coins }.
function ForgeService.sellWeapons(player: Player, ids: any, protected: { [string]: boolean }?): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	local ok, result = Economy.sellWeapons(data, ids, protected)
	if ok then
		DataService.markDirty(player)
	end
	return ok, result
end

-- Sells every backpack weapon below `keepFrom` (nil = all) except displayed ones.
function ForgeService.sellAll(player: Player, keepFrom: any, protected: { [string]: boolean }?): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	local ok, result = Economy.sellAll(data, keepFrom, protected)
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

-- Exact odds for the disclosure UI at the luck a mode implies (manual shows the 5x ceiling).
function ForgeService.odds(mode: any): ForgeMath.OddsTable
	return ForgeMath.oddsTable(ForgeMath.autoLuck(mode) or ForgeMath.MAX_LUCK)
end

-- Restarts the auto forges a player left running (called when their profile loads).
function ForgeService.resumeAuto(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	for index, recipe in data.stations do
		local mode = recipe.auto
		if mode == "free" or mode == "premium" then
			local ok = begin(player, index, mode)
			if not ok then
				recipe.auto = nil
			end
		end
	end
end

function ForgeService.init()
	DataService.profileLoaded.Event:Connect(function(player)
		task.delay(2, function()
			if player.Parent == Players then
				ForgeService.resumeAuto(player)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local list = sessions[player]
		if list then
			for _, session in list do
				session.auto = false
				session.done = true
			end
		end
		sessions[player] = nil
	end)
end

return ForgeService
