-- Real OrderedDataStore acceptance with GUID-named isolated stores. Production untouched.
-- return require(game.ServerStorage.Build.TestLeaderboards)(positiveCurrentUserId)
return function(userId: number)
	assert(game:GetService("RunService"):IsStudio(), "Acceptance helper is Studio-only")
	assert(type(userId) == "number" and userId > 0 and userId == math.floor(userId), "A positive real current user id is required")
	local root = game:GetService("ServerScriptService"):WaitForChild("Server")
	local library = require(root.Packages.ProfileStore)
	local deadline = os.clock() + 20
	while library.DataStoreState == "NotReady" and os.clock() < deadline do task.wait(0.05) end
	if library.DataStoreState ~= "Access" then
		return {passed = false, skipped = true, apiState = library.DataStoreState, reason = "Real ordered-store test needs existing Studio API Access; settings were not changed."}
	end
	local DataStoreService = game:GetService("DataStoreService")
	local HttpService = game:GetService("HttpService")
	local Players = game:GetService("Players")
	local service = require(root.Services.LeaderboardService:Clone())
	local runId = HttpService:GenerateGUID(false)
	-- Full GUID entropy, with Roblox's 50-character store-name limit respected.
	local namespace = "FFA_" .. runId:gsub("-", "") .. "_"
	local opened, failOnce, injectedFailure = {}, true, false
	local profile = {lifetimeCoins = 12000, weaponsForged = 100, evolutionRank = 2, highestWeaponValue = 500}
	local player = {UserId = userId}
	local clock = os.clock()
	service._inject({
		getProfile = function() return profile end,
		getStore = function(name)
			-- All actual service names are mapped into this unique acceptance namespace.
			assert(name:sub(1, 3) == "FF_", "Unexpected service store name")
			local isolated = namespace .. name:sub(4)
			opened[name] = opened[name] or DataStoreService:GetOrderedDataStore(isolated)
			return {
				UpdateAsync = function(_, key, transform)
					if name == "FF_forged_v1" and failOnce then
						failOnce, injectedFailure = false, true
						error("Acceptance-injected transient failure before any real write")
					end
					return opened[name]:UpdateAsync(key, transform)
				end,
				GetSortedAsync = function(_, ascending, pageSize)
					return opened[name]:GetSortedAsync(ascending, pageSize)
				end,
			}
		end,
		nameFor = function(id) return Players:GetNameFromUserIdAsync(id) end,
		clock = function() return clock end,
	})
	local function eventually(callback, label)
		local stop = os.clock() + 20
		repeat
			if callback() then return end
			assert(os.clock() < stop, "Timed out: " .. label)
			task.wait(1)
			clock += 10
		until false
	end
	assert(not service.flush(player, true) and injectedFailure and service.isGlobalEnabled(), "Transient failure permanently disabled boards")
	clock += 10
	eventually(function() return service.flush(player) end, "retry recovery")
	-- A second player object models a stale server without sharing per-object throttle state.
	profile.weaponsForged = 12
	assert(service.flush({UserId = userId}, true), "Stale server flush failed")
	profile.weaponsForged = 100
	for _, metric in service.Logic.Metrics do
		eventually(function()
			service.refresh(metric.key)
			local top = service.getTop(metric.key, 1)
			return #top == 1 and top[1].userId == userId and math.abs(top[1].value - profile[metric.field]) < 0.001
		end, metric.key .. " global cached read")
	end
	local top = service.getTop("forged")[1]
	assert(top.value == 100, "Stale server lowered global record")
	assert(top.name == Players:GetNameFromUserIdAsync(userId), "Name cache failed")
	local stores = {}
	for name in opened do table.insert(stores, namespace .. name:sub(4)) end
	table.sort(stores)
	return {passed = true, persistent = true, apiState = library.DataStoreState,
		userId = userId, runId = runId, stores = stores,
		checks = {"four actual isolated ordered writes", "transient failure recovery", "monotonic stale-server UpdateAsync", "four global cached ranked reads", "real player name lookup"},
		limitations = "Fresh isolated ordered stores; original global records unchanged. Transient error was deliberately injected before a write."}
end
