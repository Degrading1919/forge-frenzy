--!strict
--[[
	LeaderboardService: the four Hall of Blacksmiths boards (docs/06).

	  wealth     profile.lifetimeCoins       lifetime coins earned (not current coins)
	  forged     profile.weaponsForged
	  evolutions profile.evolutionRank
	  bestWeapon profile.highestWeaponValue

	Global boards use OrderedDataStores. Writes are throttled per player (only when a value
	changed, at most once per WRITE_INTERVAL, plus a flush on leave and shutdown) and top
	lists are cached and refreshed every READ_INTERVAL, so nothing writes per click.

	Coin metrics can exceed 2^53 late game and OrderedDataStore needs integers, so they are
	stored as round(log10(v + 1) * 1e12), which keeps ordering and decodes to within display
	precision. Count metrics are stored as-is.

	Transient failures back off per metric and retry; monotonic UpdateAsync prevents an old
	server from lowering a record. Studio uses separate ordered stores. Mock sessions use
	server boards only. Departure snapshots come from DataService, avoiding callback races.
]]

local LeaderboardService = {}
local Logic = {}
LeaderboardService.Logic = Logic

local WRITE_INTERVAL = 120
local READ_INTERVAL = 60
local TOP_SIZE = 50
local STORE_VERSION = "v1"
local LOG_SCALE = 1e12

export type Metric = { key: string, field: string, label: string, logEncoded: boolean }

Logic.Metrics = {
	{ key = "wealth", field = "lifetimeCoins", label = "Lifetime Wealth", logEncoded = true },
	{ key = "forged", field = "weaponsForged", label = "Weapons Forged", logEncoded = false },
	{ key = "evolutions", field = "evolutionRank", label = "Evolutions", logEncoded = false },
	{ key = "bestWeapon", field = "highestWeaponValue", label = "Best Weapon", logEncoded = true },
} :: { Metric }

local metricByKey: { [string]: Metric } = {}
for _, metric in Logic.Metrics do
	metricByKey[metric.key] = metric
end

function Logic.encode(metric: Metric, value: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value <= 0 then
		return 0
	end
	if metric.logEncoded then
		return math.floor(math.log10(value + 1) * LOG_SCALE + 0.5)
	end
	return math.min(math.floor(value), 2 ^ 53 - 1)
end

function Logic.decode(metric: Metric, stored: number): number
	if metric.logEncoded then
		return math.floor(10 ^ (stored / LOG_SCALE) - 1 + 0.5)
	end
	return stored
end

function Logic.readValue(profile: any, metric: Metric): number
	local value = profile[metric.field]
	if type(value) ~= "number" or value ~= value or value == math.huge or value < 0 then
		return 0
	end
	return value
end

--[[
	Throttle decision for one player and metric.
	state = { lastWritten: number?, lastAt: number? }; returns true when a write is due.
]]
function Logic.shouldWrite(state: any, encoded: number, now: number, force: boolean?): boolean
	if encoded <= 0 or (state.lastWritten and encoded <= state.lastWritten) then
		return false
	end
	if force then
		return true
	end
	return state.lastAt == nil or now - state.lastAt >= WRITE_INTERVAL
end

-- Rank a set of { userId, name, value } entries for the current-server board.
function Logic.rank(entries: { any }, n: number): { any }
	table.sort(entries, function(a: any, b: any)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)
	local out = {}
	for i = 1, math.min(n, #entries) do
		out[i] = entries[i]
	end
	return out
end

--------------------------------------------------------------------------------
-- Service
--------------------------------------------------------------------------------

local deps: { [string]: any } = {
	getProfile = function(_player: any): any
		return nil
	end,
	players = function(): { any }
		return {}
	end,
	getStore = nil, -- (name) -> OrderedDataStore
	nameFor = function(userId: number): string
		return "Blacksmith " .. userId
	end,
	clock = os.clock,
	storeSuffix = "",
	globalAvailable = function() return true end,
	prepareShutdown = function() end,
}

local enabled = true
local stores: { [string]: any } = {}
local writeState: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
local topCache: { [string]: { any } } = {}
local nameCache: { [number]: string } = {}
local failures: { [string]: any } = {}
local pending: { [number]: any } = {}
local stopping = false

local function dataOf(player: any): any
	local profile = deps.getProfile(player)
	if type(profile) ~= "table" then
		return nil
	end
	return if type(profile.Data) == "table" then profile.Data else profile
end

local function failed(metric: Metric, err: any)
	local state = failures[metric.key] or { count = 0 }
	state.count += 1
	state.retryAt = deps.clock() + math.min(120, 5 * 2 ^ math.min(5, state.count - 1))
	failures[metric.key] = state
	if state.count == 1 then warn(`[Leaderboard] {metric.key} temporarily unavailable; retrying: {err}`) end
end

local function storeFor(metric: Metric, force: boolean?): any
	if not enabled or not deps.globalAvailable() or deps.getStore == nil then
		return nil
	end
	local failure = failures[metric.key]
	if failure and not force and deps.clock() < failure.retryAt then return nil end
	local store = stores[metric.key]
	if store == nil then
		local ok, result = pcall(deps.getStore, `FF_{metric.key}_{STORE_VERSION}{deps.storeSuffix}`)
		if not ok then
			failed(metric, result)
			return nil
		end
		store = result
		stores[metric.key] = store
	end
	return store
end

-- Write any due metrics for one player. `force` is used on leave/shutdown.
function LeaderboardService.flush(player: any, force: boolean?, snapshot: any?): boolean
	local profile = snapshot or dataOf(player)
	if profile == nil or type(player.UserId) ~= "number" or player.UserId <= 0 then
		return true
	end
	local now = deps.clock()
	local states = writeState[player]
	if states == nil then
		states = {}
		writeState[player] = states
	end
	local successful = true
	for _, metric in Logic.Metrics do
		local state = states[metric.key] or {}
		states[metric.key] = state
		local encoded = Logic.encode(metric, Logic.readValue(profile, metric))
		-- A departure snapshot must remain queued until its final value is written.
		-- Bypass the periodic interval on retries, while storeFor still honors backoff.
		if Logic.shouldWrite(state, encoded, now, force or snapshot ~= nil) then
			if state.inFlight then successful = false; continue end
			local store = storeFor(metric, force)
			if store == nil then
				successful = false
				continue
			end
			state.inFlight = true
			local ok, result = pcall(store.UpdateAsync, store, tostring(player.UserId), function(old)
				return math.max(if type(old) == "number" then old else 0, encoded)
			end)
			state.inFlight = false
			if ok then
				state.lastWritten = if type(result) == "number" then result else encoded
				state.lastAt = now
				failures[metric.key] = nil
			else
				failed(metric, result)
				successful = false
			end
		end
	end
	return successful
end

-- Capture before the profile disappears; no datastore call/yield in the release hook.
function LeaderboardService.queueDeparture(player: any, profile: any)
	if type(player.UserId) ~= "number" or player.UserId <= 0 or not deps.globalAvailable() then return end
	local snapshot = {}
	local prior = pending[player.UserId]
	for _, metric in Logic.Metrics do
		snapshot[metric.field] = math.max(Logic.readValue(profile, metric),
			if prior then Logic.readValue(prior.profile, metric) else 0)
	end
	pending[player.UserId] = { player = player, profile = snapshot }
end

function LeaderboardService.flushPending(force: boolean?)
	for userId, entry in pending do
		if LeaderboardService.flush(entry.player, force, entry.profile) and pending[userId] == entry then
			pending[userId] = nil
		end
	end
end

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(deps.nameFor, userId)
	local resolved = if ok and type(name) == "string" then name else "Blacksmith " .. userId
	nameCache[userId] = resolved
	return resolved
end

function LeaderboardService.refresh(metricKey: string)
	local metric = metricByKey[metricKey]
	local store = metric and storeFor(metric)
	if store == nil then
		return
	end
	local ok, pages = pcall(store.GetSortedAsync, store, false, TOP_SIZE)
	if not ok then
		failed(metric, pages)
		return
	end
	local okPage, page = pcall(pages.GetCurrentPage, pages)
	if not okPage then
		failed(metric, page)
		return
	end
	local list = {}
	for i, entry in page do
		local userId = tonumber(entry.key)
		if userId then
			list[i] = { userId = userId, name = nameFor(userId), value = Logic.decode(metric, entry.value) }
		end
	end
	topCache[metricKey] = list
	failures[metricKey] = nil
end

-- Cached global top list: { { userId, name, value } }. Empty when boards are disabled.
function LeaderboardService.getTop(metricKey: string, n: number?): { any }
	local list = topCache[metricKey] or {}
	local out = {}
	for i = 1, math.min(n or TOP_SIZE, #list) do
		out[i] = list[i]
	end
	return out
end

-- Live ranking of players in this server, straight from their profiles.
function LeaderboardService.getServerTop(metricKey: string, n: number?): { any }
	local metric = metricByKey[metricKey]
	if metric == nil then
		return {}
	end
	local entries = {}
	for _, player in deps.players() do
		local profile = dataOf(player)
		if profile then
			table.insert(entries, { userId = player.UserId, name = player.DisplayName or player.Name, value = Logic.readValue(profile, metric) })
		end
	end
	return Logic.rank(entries, n or TOP_SIZE)
end

function LeaderboardService.isGlobalEnabled(): boolean
	return enabled and deps.globalAvailable()
end

function LeaderboardService._inject(overrides: { [string]: any })
	for key, value in overrides do
		deps[key] = value
	end
	enabled = true
	table.clear(stores)
	table.clear(writeState)
	table.clear(topCache)
	table.clear(nameCache)
	table.clear(failures)
	table.clear(pending)
end

function LeaderboardService.init()
	local DataService = require(script.Parent:WaitForChild("DataService")) :: any
	local Players = game:GetService("Players")
	local DataStoreService = game:GetService("DataStoreService")
	deps.getProfile = function(player)
		return DataService.get(player)
	end
	deps.players = function()
		return Players:GetPlayers()
	end
	deps.getStore = function(name)
		return DataStoreService:GetOrderedDataStore(name)
	end
	deps.storeSuffix = if game:GetService("RunService"):IsStudio() then DataService.STUDIO_SUFFIX else ""
	deps.globalAvailable = function() return DataService.getStatus().persistent end
	deps.prepareShutdown = DataService.prepareShutdown
	DataService.registerReleaseHook("Leaderboard", function(player, data)
		LeaderboardService.queueDeparture(player, data)
		task.defer(LeaderboardService.flushPending, true)
	end)
	deps.nameFor = function(userId)
		return Players:GetNameFromUserIdAsync(userId)
	end
end

function LeaderboardService.start()
	local Players = game:GetService("Players")
	game:BindToClose(function()
		stopping = true
		deps.prepareShutdown()
		for _, player in Players:GetPlayers() do
			local data = dataOf(player)
			if data then LeaderboardService.queueDeparture(player, data) end
		end
		local deadline = deps.clock() + 25
		repeat
			LeaderboardService.flushPending(true)
			if next(pending) == nil then break end
			task.wait(1)
		until deps.clock() >= deadline
	end)
	task.spawn(function()
		while not stopping do
			LeaderboardService.flushPending(false)
			task.wait(5)
		end
	end)
	task.spawn(function()
		while not stopping do
			for _, player in Players:GetPlayers() do
				LeaderboardService.flush(player, false)
			end
			for _, metric in Logic.Metrics do
				LeaderboardService.refresh(metric.key)
			end
			task.wait(READ_INTERVAL)
		end
	end)
end

return LeaderboardService
