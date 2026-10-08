--!strict
-- Session-locked saves. Studio NEVER writes production keys; missing storage fails closed.
local Players = game:GetService("Players")
local Economy = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Economy"))
local DataService = {}
DataService.STORE_NAME = "ForgeFrenzy_Player_v2"
DataService.STUDIO_SUFFIX = "_StudioPlaytest"
DataService.KEY_PREFIX = "Player_"
DataService.profileChanged = Instance.new("BindableEvent")
DataService.profileLoaded = Instance.new("BindableEvent")
local sessions: {[any]: any} = {}
local loading: {[any]: boolean} = {}
local extraDefaults, releaseHooks = {}, {}
local store: any = nil
local initialized, started, closing = false, false, false
local mode, storeName, apiState = "Unavailable", DataService.STORE_NAME, "NotReady"
local deps: any = {
	clock = os.clock, now = os.time, wait = task.wait,
	isStudio = function() return game:GetService("RunService"):IsStudio() end,
	forceMock = function() return game:GetAttribute("ForgeFrenzyForceMock") == true end,
	setGameAttribute = function(key, value) game:SetAttribute(key, value) end,
	setPlayerAttribute = function(player, key, value) player:SetAttribute(key, value) end,
	settleOffline = function(player)
		require(script.Parent:WaitForChild("ProductionService")).settleOffline(player)
	end,
	getLibrary = function()
		return require(script.Parent.Parent:WaitForChild("Packages"):WaitForChild("ProfileStore", 10))
	end,
}
local function deepCopy(value: any): any
	if type(value) ~= "table" then return value end
	local out = {}
	for key, child in value do out[key] = deepCopy(child) end
	return out
end
local function playerStatus(player: any, state: string)
	local session = sessions[player]
	if session then session.saveState = state end
	pcall(deps.setPlayerAttribute, player, "FFSaveState", state)
end
local function applyDefaults(data: any)
	Economy.reconcile(data)
	for key, value in extraDefaults do
		if data[key] == nil then data[key] = deepCopy(value) end
	end
end
function DataService.registerDefaults(defaults: {[string]: any})
	for key, value in defaults do extraDefaults[key] = deepCopy(value) end
	for _, session in sessions do applyDefaults(session.data) end
end
-- Called once before release. Hooks must capture data before yielding, and must not
-- depend on PlayerRemoving callback order. Names sort so forge refunds precede boards.
function DataService.registerReleaseHook(name: string, callback: (any, any, string) -> ())
	releaseHooks[name] = callback
end
local function runReleaseHooks(player: any, session: any, reason: string)
	if session.hooksCalled then return end
	session.hooksCalled = true
	local names = {}
	for name in releaseHooks do table.insert(names, name) end
	table.sort(names)
	for _, name in names do
		local ok, err = pcall(releaseHooks[name], player, session.data, reason)
		if not ok then warn(`[DataService] release hook {name}: {err}`) end
	end
end
function DataService.get(player: any): any?
	local session = sessions[player]
	if not session or session.releasing or closing then return nil end
	if session.profile and not session.profile:IsActive() then return nil end
	return session.data
end
function DataService.getStatus(player: any?): any
	local session = if player then sessions[player] else nil
	return { mode = mode, storeName = storeName, apiState = apiState,
		persistent = mode == "Production" or mode == "StudioPersistent",
		saveState = if session then (if session.releasing then "Releasing" else session.saveState or "Loaded") else "NotLoaded",
		lastSavedAt = if session then session.lastSavedAt else nil }
end
function DataService.waitFor(player: any, timeoutSec: number?): any?
	local deadline = deps.clock() + (timeoutSec or 60)
	repeat
		local data = DataService.get(player)
		if data then return data end
		if player.Parent ~= Players or closing or deps.clock() >= deadline then return nil end
		deps.wait()
	until false
end
function DataService.markDirty(player: any)
	local data = DataService.get(player)
	if data then DataService.profileChanged:Fire(player, data) end
end
-- Profile:Save starts an asynchronous job; confirm its saved revision before success.
function DataService.saveNow(player: any, timeoutSec: number?, predicate: ((any) -> boolean)?): boolean
	local session = sessions[player]
	if not DataService.get(player) or not session or not session.profile then return false end
	local profile = session.profile
	local lastSaved = profile.LastSavedData
	local revision = math.max(tonumber(session.data._saveRevision) or 0,
		if type(lastSaved) == "table" then tonumber(lastSaved._saveRevision) or 0 else 0) + 1
	session.data._saveRevision = revision
	playerStatus(player, "Saving")
	if not pcall(profile.Save, profile) then playerStatus(player, "SaveDelayed"); return false end
	local deadline = deps.clock() + (timeoutSec or 15)
	repeat
		if not profile:IsActive() then break end
		local saved = profile.LastSavedData
		if type(saved) == "table" and (tonumber(saved._saveRevision) or 0) >= revision
			and (not predicate or predicate(saved)) then
			playerStatus(player, "Saved")
			return true
		end
		if not profile:IsActive() or deps.clock() >= deadline then break end
		deps.wait(0.05)
	until false
	playerStatus(player, "SaveDelayed")
	return false
end
function DataService.update(player: any, mutate: (any) -> ...any): ...any
	local data = DataService.get(player)
	if not data then return false, "NotLoaded" end
	local results = table.pack(mutate(data))
	DataService.markDirty(player)
	return table.unpack(results, 1, results.n)
end
local function releasePlayer(player: any, reason: string?)
	local session = sessions[player]
	if not session or session.releasing then return end
	session.data.lastSeen = deps.now()
	runReleaseHooks(player, session, reason or "Leave")
	session.releasing = true
	playerStatus(player, "Releasing")
	sessions[player] = nil
	if session.profile then session.profile:EndSession() end
end
local function attachProfile(player: any, profile: any)
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	local session: any = { data = profile.Data, profile = profile }
	profile.OnSave:Connect(function() session.data.lastSeen = deps.now() end)
	profile.OnLastSave:Connect(function(reason)
		if session.loaded then runReleaseHooks(player, session, reason) end
	end)
	profile.OnAfterSave:Connect(function()
		session.lastSavedAt = deps.now()
		pcall(deps.setPlayerAttribute, player, "FFLastSavedAt", session.lastSavedAt)
		playerStatus(player, if session.releasing then "Released" else "Saved")
	end)
	profile.OnSessionEnd:Connect(function()
		if sessions[player] == session then sessions[player] = nil end
		if not session.releasing and not closing and player.Parent == Players then
			player:Kick("Your save session ended. Please rejoin to protect your progress.")
		end
	end)
	if player.Parent ~= Players or closing or not profile:IsActive() then profile:EndSession(); return end
	applyDefaults(session.data)
	sessions[player] = session
	local ok, err = pcall(deps.settleOffline, player)
	if not ok then
		error("Offline settlement failed: " .. tostring(err))
	end
	session.loaded = true
	playerStatus(player, "Loaded")
	DataService.profileLoaded:Fire(player, session.data)
	DataService.markDirty(player)
end
local function loadPlayer(player: any)
	if sessions[player] or loading[player] or closing then return end
	loading[player] = true
	playerStatus(player, "Loading")
	local ok, profile = pcall(function()
		if not store then error("Profile storage is unavailable") end
		return store:StartSessionAsync(DataService.KEY_PREFIX .. player.UserId, {
			Cancel = function() return player.Parent ~= Players or closing end,
		})
	end)
	loading[player] = nil
	if not ok or not profile then
		playerStatus(player, "LoadFailed")
		if not ok then warn("[DataService] load failed:", profile) end
		if player.Parent == Players then player:Kick("Forge Frenzy couldn't load your save. Please rejoin.") end
		return
	end
	-- Reconciliation/offline hooks may fail on malformed legacy data. Release the
	-- untouched loaded snapshot rather than saving a partially repaired profile.
	local original = deepCopy(profile.Data)
	local attached, err = pcall(attachProfile, player, profile)
	if not attached then
		warn("[DataService] restore failed:", err)
		sessions[player] = nil
		profile.Data = original
		profile:EndSession()
		if player.Parent == Players then player:Kick("Forge Frenzy couldn't restore your save. Please rejoin.") end
	end
end
function DataService.init()
	if initialized then return end
	initialized = true
	local studio = deps.isStudio()
	storeName = DataService.STORE_NAME .. (if studio then DataService.STUDIO_SUFFIX else "")
	local ok, result = pcall(function()
		local library = deps.getLibrary()
		local deadline = deps.clock() + 20
		while library.DataStoreState == "NotReady" and deps.clock() < deadline do deps.wait(0.05) end
		apiState = library.DataStoreState
		if not studio and apiState ~= "Access" then error(`DataStore API is {apiState}`) end
		if apiState == "NotReady" then error("DataStore availability check timed out") end
		local created = library.New(storeName, Economy.newProfile())
		if studio and (apiState ~= "Access" or deps.forceMock()) then
			mode = "StudioMock"
			return created.Mock
		end
		mode = if studio then "StudioPersistent" else "Production"
		return created
	end)
	if ok then store = result else mode = "Unavailable"; warn("[DataService] storage unavailable:", result) end
	deps.setGameAttribute("ForgeFrenzyDataMode", mode)
	deps.setGameAttribute("ForgeFrenzyDataStore", storeName)
	deps.setGameAttribute("ForgeFrenzyDataPersistent", mode == "Production" or mode == "StudioPersistent")
	print(`[DataService] {mode}; store={storeName}; API={apiState}`)
end
function DataService.start()
	if started then return end
	started = true
	Players.PlayerAdded:Connect(function(player) task.spawn(loadPlayer, player) end)
	Players.PlayerRemoving:Connect(function(player) releasePlayer(player, "Leave") end)
	-- ProfileStore owns the shutdown wait for final saves. OnLastSave runs hooks even
	-- if its BindToClose callback wins the race with this callback.
	game:BindToClose(DataService.prepareShutdown)
	for _, player in Players:GetPlayers() do task.spawn(loadPlayer, player) end
end
-- Leaderboard shutdown uses the same preparation before draining its departure queue.
function DataService.prepareShutdown()
	for player in sessions do releasePlayer(player, "Shutdown") end
	closing = true
end
-- Controlled injection for isolated specs. These hooks never select live data stores.
function DataService._inject(overrides: any)
	for key, value in overrides do deps[key] = value end
end
function DataService._setForTest(player: any, data: any?, profile: any?)
	if data then applyDefaults(data); sessions[player] = { data = data, profile = profile }
	else sessions[player] = nil end
end
DataService._loadForTest = loadPlayer
DataService._releaseForTest = releasePlayer
DataService._attachForTest = attachProfile
return DataService
