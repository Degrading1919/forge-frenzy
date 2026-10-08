-- Standalone EDIT-MODE MCP/command-bar export. Original hierarchy remains untouched;
-- only temporary clones are serialized. Requires the local devsync server on port 34873.
-- This is a service-container .rbxm, NOT a complete .rbxl place or cloud publication.
local Http = game:GetService("HttpService")
local Serialization = game:GetService("SerializationService")
assert(not game:GetService("RunService"):IsRunning(), "Stop playtesting before exporting the edit place")
local SERVICES = { "Workspace", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "StarterGui", "Lighting", "SoundService" }
local EXCLUDED = { SpecRun = true, SaveTemp = true, LiveSaveTemp = true, FFPersistenceRun = true, PersistenceSpecRun = true }
local SETTINGS = {
	Workspace = { "Gravity", "FallenPartsDestroyHeight", "StreamingEnabled", "StreamingMinRadius", "StreamingTargetRadius", "AirDensity", "GlobalWind" },
	ServerScriptService = { "LoadStringEnabled" },
	StarterPlayer = { "CameraMaxZoomDistance", "CameraMinZoomDistance", "CameraMode", "CharacterWalkSpeed", "CharacterJumpHeight", "CharacterJumpPower", "CharacterUseJumpPower", "DevComputerCameraMode", "DevComputerMovementMode", "DevTouchCameraMode", "DevTouchMovementMode", "EnableMouseLockOption" },
	StarterGui = { "ScreenOrientation", "ResetPlayerGuiOnSpawn" },
	Lighting = { "Technology", "Brightness", "ClockTime", "Ambient", "OutdoorAmbient", "GlobalShadows", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "ExposureCompensation", "FogStart", "FogEnd", "FogColor", "ColorShift_Top", "ColorShift_Bottom", "GeographicLatitude", "ShadowSoftness" },
	SoundService = { "RespectFilteringEnabled", "AmbientReverb", "DistanceFactor", "DopplerScale", "RolloffScale" },
}
local ATTRIBUTES = { "ForgeFrenzyForceMock", "ForgeFrenzyDataMode", "ForgeFrenzyDataStore", "ForgeFrenzyDataPersistent" }
local originalHttp = Http.HttpEnabled
local root = Instance.new("Folder")
root.Name = "ForgeFrenzy_1_0_ServiceContainers"
local decoded = {}
local function cloneContent(child)
	-- These built-in containers cannot be cloned. Preserve their children under a
	-- named Folder wrapper, just as the service containers are represented below.
	if child:IsA("StarterPlayerScripts") or child:IsA("StarterCharacterScripts") then
		local wrapper = Instance.new("Folder")
		wrapper.Name = child.Name
		for _, nested in child:GetChildren() do cloneContent(nested).Parent = wrapper end
		return wrapper
	end
	return child:Clone()
end
local function portable(value)
	local kind = typeof(value)
	if kind == "Color3" then return { type = kind, r = value.R, g = value.G, b = value.B } end
	if kind == "Vector3" then return { type = kind, x = value.X, y = value.Y, z = value.Z } end
	if kind == "EnumItem" then return tostring(value) end
	if kind == "boolean" or kind == "string" or kind == "number" then return value end
	return tostring(value)
end
local function signatures(container)
	local source, worldCount, descendantCount = {}, 0, #container:GetDescendants()
	for _, instance in container:GetDescendants() do
		if instance:IsA("LuaSourceContainer") then
			local path = instance:GetFullName():sub(#container.Name + 2)
			assert(source[path] == nil, "Duplicate script path: " .. path)
			source[path] = { class = instance.ClassName, source = instance.Source }
		end
	end
	local workspaceContainer = container:FindFirstChild("Workspace")
	local world = workspaceContainer and workspaceContainer:FindFirstChild("World")
	if world then worldCount = #world:GetDescendants() end
	return source, worldCount, descendantCount
end
local ok, result = pcall(function()
	local metadata = {
		format = "rbxm-service-containers", placeId = game.PlaceId, gameId = game.GameId,
		placeVersion = game.PlaceVersion, creatorId = game.CreatorId, creatorType = tostring(game.CreatorType),
		exportedAtUtc = DateTime.now():ToIsoDate(), sourceMode = "Edit", httpEnabledBefore = originalHttp,
		serviceSettings = {}, gameAttributes = {}, excluded = {}, containers = {}, scripts = {},
		limitations = { "Not a full .rbxl place; import container children into their corresponding services.", "Terrain, Camera and temporary test/save instances are excluded.", "Service properties, place settings, cloud configuration and player data are not part of the model; selected settings are recorded here." },
	}
	local maxOk, maxPlayers = pcall(function() return game:GetService("Players").MaxPlayers end)
	if maxOk then metadata.maxPlayers = maxPlayers end
	for _, name in ATTRIBUTES do
		local value = game:GetAttribute(name)
		if value ~= nil then metadata.gameAttributes[name] = portable(value) end
	end
	for _, serviceName in SERVICES do
		local service = game:GetService(serviceName)
		local folder = Instance.new("Folder")
		folder.Name = serviceName
		folder.Parent = root
		local settings = {}
		for _, property in SETTINGS[serviceName] or {} do
			local readable, value = pcall(function() return service[property] end)
			if readable then settings[property] = portable(value) end
		end
		metadata.serviceSettings[serviceName] = settings
		for _, child in service:GetChildren() do
			local lower = child.Name:lower()
			local excluded = child:IsA("Terrain") or child:IsA("Camera") or EXCLUDED[child.Name] or lower:find("savetemp", 1, true) ~= nil or child:GetAttribute("ForgeFrenzyTemporary") == true
			if excluded then
				table.insert(metadata.excluded, serviceName .. "." .. child.Name)
			else
				local clone = cloneContent(child)
				assert(clone, "Cannot preserve non-Archivable object: " .. child:GetFullName())
				assert(#clone:GetDescendants() == #child:GetDescendants(), "Clone omitted descendants: " .. child:GetFullName())
				clone.Parent = folder
			end
		end
		table.insert(metadata.containers, { name = serviceName, children = #folder:GetChildren(), descendants = #folder:GetDescendants() })
	end
	local sources, worldCount, count = signatures(root)
	assert(worldCount > 0, "World hierarchy is missing")
	local sourceCount = 0
	for path, record in sources do
		sourceCount += 1
		table.insert(metadata.scripts, { path = path, class = record.class, bytes = #record.source })
	end
	table.sort(metadata.scripts, function(a, b) return a.path < b.path end)
	assert(sourceCount > 0, "No scripts to preserve")
	local content = Serialization:SerializeInstancesAsync({ root })
	decoded = Serialization:DeserializeInstancesAsync(content)
	assert(#decoded == 1 and decoded[1].Parent == nil, "Round-trip must remain unparented")
	local restored, restoredWorld, restoredCount = signatures(decoded[1])
	assert(restoredWorld == worldCount and restoredCount == count, "Round-trip hierarchy count mismatch")
	local restoredScripts = 0
	for path, record in restored do
		restoredScripts += 1
		assert(sources[path] and sources[path].class == record.class and sources[path].source == record.source, "Round-trip script mismatch: " .. path)
	end
	assert(restoredScripts == sourceCount, "Round-trip script count mismatch")
	metadata.verifiedUnparentedRoundTrip = true
	metadata.scriptCount, metadata.worldDescendants, metadata.descendantCount = sourceCount, worldCount, count
	local bytes = buffer.tostring(content)
	local total = #bytes
	local chunkBytes = 200000
	local parts = math.ceil(total / chunkBytes)
	local exportId = Http:GenerateGUID(false)
	metadata.exportId, metadata.totalBytes, metadata.totalParts = exportId, total, parts
	local hex = {}
	for i = 0, 255 do hex[i + 1] = string.format("%02x", i) end
	Http.HttpEnabled = true
	for part = 1, parts do
		local raw = bytes:sub((part - 1) * chunkBytes + 1, math.min(total, part * chunkBytes))
		local modelHex = raw:gsub(".", function(char) return hex[string.byte(char) + 1] end)
		local payload = { kind = "releaseModelPart", exportId = exportId, part = part, totalParts = parts, totalBytes = total, modelHex = modelHex }
		if part == 1 then payload.metadata = metadata end
		Http:PostAsync("http://127.0.0.1:34873/backup", Http:JSONEncode(payload), Enum.HttpContentType.ApplicationJson, false)
	end
	return Http:JSONEncode({ exportId = exportId, totalBytes = total, parts = parts, scriptCount = sourceCount, worldDescendants = worldCount, verified = true })
end)
-- Always restore HTTP and destroy only the temporary clones, even after serialization/HTTP errors.
local restoredHttp, restoreError = pcall(function() Http.HttpEnabled = originalHttp end)
for _, clone in decoded do clone:Destroy() end
root:Destroy()
assert(restoredHttp, restoreError)
assert(ok, result)
return result
