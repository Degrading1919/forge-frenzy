--!strict
--[[
	DataService — session-locked player profiles (ProfileStore 1.0.3, Apache-2.0, vendored in
	src/server/Packages).

	get(player) / waitFor(player) return the live profile data table (see Economy.Profile).
	Other services mutate it synchronously and then call markDirty(player), which fires
	profileChanged(player, data) for replication. ProfileStore saves every 300 s, on leave and
	on shutdown. In Studio without API access ProfileStore switches to its mock store on its
	own; if the package cannot load at all, profiles fall back to in-memory tables so play
	testing never errors.

	Profile fields owned by the core economy are created by Economy.newProfile(). Other threads
	add their own fields by registering defaults with DataService.registerDefaults() during their
	init(); defaults are filled into every loaded profile without overwriting saved values.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))

local DataService = {}

-- Bump only with a migration; changing it starts every player on a fresh store.
DataService.STORE_NAME = "ForgeFrenzy_Player_v1"
DataService.KEY_PREFIX = "Player_"

DataService.profileChanged = Instance.new("BindableEvent") -- (player, data)
DataService.profileLoaded = Instance.new("BindableEvent") -- (player, data)

type Session = { data: Economy.Profile, profile: any? }

local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local extraDefaults: { [string]: any } = {}
local store: any = nil

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

local function applyDefaults(data: Economy.Profile)
	Economy.reconcile(data)
	for key, value in extraDefaults do
		if data[key] == nil then
			data[key] = deepCopy(value)
		end
	end
end

-- Registers default values for profile fields another service owns ({ pets = {}, ... }).
function DataService.registerDefaults(defaults: { [string]: any })
	for key, value in defaults do
		extraDefaults[key] = deepCopy(value)
	end
	for _, session in sessions do
		applyDefaults(session.data)
	end
end

function DataService.get(player: Player): Economy.Profile?
	local session = sessions[player]
	return if session then session.data else nil
end

-- Yields until the player's profile is loaded; nil if they leave or loading gives up.
function DataService.waitFor(player: Player, timeoutSec: number?): Economy.Profile?
	local deadline = os.clock() + (timeoutSec or 60)
	while not sessions[player] do
		if player.Parent ~= Players or os.clock() > deadline then
			return nil
		end
		task.wait()
	end
	return sessions[player].data
end

function DataService.markDirty(player: Player)
	local session = sessions[player]
	if session then
		DataService.profileChanged:Fire(player, session.data)
	end
end

-- Saves the player's profile now (e.g. right after a purchase receipt). No-op for in-memory profiles.
function DataService.saveNow(player: Player): boolean
	local session = sessions[player]
	if session and session.profile then
		session.profile:Save()
		return true
	end
	return false
end

-- Runs `mutate(data)` and marks the profile dirty if the player is loaded. Returns its results.
function DataService.update(player: Player, mutate: (Economy.Profile) -> ...any): ...any
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	local results = table.pack(mutate(data))
	DataService.markDirty(player)
	return table.unpack(results, 1, results.n)
end

local function finishLoad(player: Player, session: Session)
	applyDefaults(session.data)
	sessions[player] = session
	-- Offline production is settled by ProductionService (required lazily to avoid a cycle).
	local okProd, ProductionService = pcall(require, script.Parent:FindFirstChild("ProductionService"))
	local production: any = if okProd then ProductionService else nil
	if production and production.settleOffline then
		production.settleOffline(player)
	else
		session.data.lastSeen = os.time()
	end
	DataService.profileLoaded:Fire(player, session.data)
	DataService.markDirty(player)
end

local function loadPlayer(player: Player)
	if sessions[player] or loading[player] then
		return
	end
	loading[player] = true
	if not store then
		finishLoad(player, { data = Economy.newProfile() })
		loading[player] = nil
		return
	end
	local profile = store:StartSessionAsync(DataService.KEY_PREFIX .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	loading[player] = nil
	if profile == nil then
		if player.Parent == Players then
			player:Kick("Forge Frenzy couldn't load your save. Please rejoin.")
		end
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		sessions[player] = nil
		if player.Parent == Players then
			player:Kick("Your save was opened on another server. Please rejoin.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	finishLoad(player, { data = profile.Data, profile = profile })
end

local function releasePlayer(player: Player)
	local session = sessions[player]
	sessions[player] = nil
	if session then
		session.data.lastSeen = os.time()
		if session.profile then
			session.profile:EndSession()
		end
	end
end

function DataService.init()
	local packages = script.Parent.Parent:FindFirstChild("Packages")
	local module = packages and packages:FindFirstChild("ProfileStore")
	if module then
		local ok, ProfileStore = pcall(require, module)
		if ok then
			local okStore, created = pcall(ProfileStore.New, DataService.STORE_NAME, Economy.newProfile())
			if okStore then
				store = created
			else
				warn("[DataService] ProfileStore.New failed, using in-memory profiles:", created)
			end
		else
			warn("[DataService] ProfileStore failed to load, using in-memory profiles:", ProfileStore)
		end
	else
		warn("[DataService] Packages.ProfileStore missing, using in-memory profiles")
	end
end

function DataService.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadPlayer, player)
	end)
	Players.PlayerRemoving:Connect(releasePlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
end

-- Test hook: installs an in-memory profile for a player-like object (no DataStore involved).
function DataService._setForTest(player: any, data: Economy.Profile?)
	if data then
		applyDefaults(data)
		sessions[player] = { data = data }
	else
		sessions[player] = nil
	end
end

return DataService
