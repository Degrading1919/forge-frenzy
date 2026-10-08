-- Save lifecycle regression specs. No Roblox DataStore calls or production keys.
local Services = script.Parent.Parent:WaitForChild("Services")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Players = game:GetService("Players")
local function fresh()
	local service = require(Services:WaitForChild("DataService"):Clone())
	service._inject({setGameAttribute = function() end, setPlayerAttribute = function() end,
		settleOffline = function() end, forceMock = function() return false end})
	return service
end
local function player(id)
	return { UserId = id or 77, Parent = Players, Kick = function(self, message) self.kicked = message end }
end
local function fakeProfile(data)
	local profile = { Data = data or Economy.newProfile(), LastSavedData = {}, active = true, ends = 0 }
	for _, key in { "OnSave", "OnLastSave", "OnAfterSave", "OnSessionEnd" } do
		profile[key .. "Event"] = Instance.new("BindableEvent")
		profile[key] = profile[key .. "Event"].Event
	end
	profile.AddUserId = function() end
	profile.Reconcile = function() end
	profile.IsActive = function(self) return self.active end
	profile.Save = function() end
	profile.EndSession = function(self)
		self.ends += 1
		self.OnSaveEvent:Fire()
		self.OnLastSaveEvent:Fire("Manual")
		self.active = false
		self.OnSessionEndEvent:Fire()
	end
	return profile
end
local tests = {}

tests["Studio uses isolated persistent name and original player key"] = function()
	local service, p, saved = fresh(), player(), fakeProfile()
	local names, keys = {}, {}
	local fake = { StartSessionAsync = function(_, key) table.insert(keys, key); return saved end }
	service._inject({isStudio = function() return true end, getLibrary = function()
		return { DataStoreState = "Access", New = function(name)
			table.insert(names, name)
			return fake
		end }
	end})
	service.init()
	service._loadForTest(p)
	assert(names[1] == "ForgeFrenzy_Player_v2_StudioPlaytest")
	assert(keys[1] == "Player_77")
	assert(service.getStatus().mode == "StudioPersistent" and service.getStatus().persistent)
	assert(service.get(p) == saved.Data)
end

tests["live keeps existing store and key"] = function()
	local service, name = fresh(), nil
	service._inject({isStudio = function() return false end, getLibrary = function()
		return {DataStoreState = "Access", New = function(storeName) name = storeName; return {} end}
	end})
	service.init()
	assert(name == "ForgeFrenzy_Player_v2" and service.getStatus().mode == "Production")
end

tests["API unavailable Studio is explicit session mock"] = function()
	local service, usedMock = fresh(), false
	service._inject({isStudio = function() return true end, getLibrary = function()
		return {DataStoreState = "NoAccess", New = function()
			return {Mock = {StartSessionAsync = function() usedMock = true; return fakeProfile() end}}
		end}
	end})
	service.init()
	service._loadForTest(player())
	assert(usedMock and service.getStatus().mode == "StudioMock" and not service.getStatus().persistent)
end

tests["live unavailable API never creates a replacement profile"] = function()
	local service, made = fresh(), false
	service._inject({isStudio = function() return false end, getLibrary = function()
		return {DataStoreState = "NoInternet", New = function() made = true; return {} end}
	end})
	service.init()
	local p = player()
	service._loadForTest(p)
	assert(not made and service.get(p) == nil and p.kicked)
end

tests["package failure fails closed"] = function()
	local service = fresh()
	service._inject({isStudio = function() return true end, getLibrary = function() error("package unavailable") end})
	service.init()
	local p = player()
	service._loadForTest(p)
	assert(service.get(p) == nil and p.kicked and service.getStatus().mode == "Unavailable")
end

tests["failed offline hook releases the original unmodified save"] = function()
	local service, p, profile = fresh(), player(), fakeProfile()
	profile.Data.coins = 2468
	local endedCoins
	local originalEnd = profile.EndSession
	profile.EndSession = function(self) endedCoins = self.Data.coins; originalEnd(self) end
	service._inject({isStudio = function() return true end,
		settleOffline = function() profile.Data.coins = 999999; error("offline hook failed") end,
		getLibrary = function() return {DataStoreState = "Access", New = function()
			return {StartSessionAsync = function() return profile end}
		end} end})
	service.init()
	service._loadForTest(p)
	assert(service.get(p) == nil and p.kicked and endedCoins == 2468, "Partial load was persisted")
end

tests["API readiness timeout is bounded and fails closed"] = function()
	local service, clock, made = fresh(), 0, false
	service._inject({isStudio = function() return true end,
		clock = function() return clock end,
		wait = function(dt) clock += dt end,
		getLibrary = function() return {DataStoreState = "NotReady", New = function() made = true end} end})
	service.init()
	assert(clock >= 20 and clock < 21 and not made and service.getStatus().mode == "Unavailable")
end

tests["departed player cancels loading without reopening a save"] = function()
	local service, p, profile, cancelled = fresh(), player(), fakeProfile(), false
	service._inject({isStudio = function() return true end, getLibrary = function()
		return {DataStoreState = "Access", New = function() return {
			StartSessionAsync = function(_, _, params)
				p.Parent = nil
				cancelled = params.Cancel()
				return profile
			end,
		} end}
	end})
	service.init()
	service._loadForTest(p)
	assert(cancelled and profile.ends == 1 and service.get(p) == nil and not p.kicked)
end

tests["external session end clears profile and prevents further mutations"] = function()
	local service, p, profile = fresh(), player(), fakeProfile()
	service._attachForTest(p, profile)
	profile.active = false
	profile.OnSessionEndEvent:Fire()
	task.wait()
	assert(service.get(p) == nil and p.kicked)
end

tests["shutdown prepares all profiles and hooks once before release"] = function()
	local service, a, b = fresh(), player(1), player(2)
	local pa, pb, calls = fakeProfile(), fakeProfile(), 0
	service._setForTest(a, pa.Data, pa)
	service._setForTest(b, pb.Data, pb)
	service.registerReleaseHook("Leaderboard", function(_, _, reason) assert(reason == "Shutdown"); calls += 1 end)
	service.prepareShutdown()
	service.prepareShutdown()
	assert(pa.ends == 1 and pb.ends == 1 and calls == 2 and service.get(a) == nil and service.get(b) == nil)
end

tests["saveNow waits for confirmed revision rather than scheduling"] = function()
	local service, p, profile = fresh(), player(), fakeProfile()
	local clock, waits = 0, 0
	service._inject({clock = function() return clock end, wait = function(dt)
		clock += dt
		waits += 1
		if waits == 2 then profile.LastSavedData = table.clone(profile.Data) end
	end})
	service._setForTest(p, profile.Data, profile)
	assert(service.saveNow(p, 1) and waits == 2)
	assert(profile.LastSavedData._saveRevision == 1)
end

tests["saveNow timeout does not falsely acknowledge"] = function()
	local service, p, profile = fresh(), player(), fakeProfile()
	local clock = 0
	service._inject({clock = function() return clock end, wait = function(dt) clock += dt end})
	service._setForTest(p, profile.Data, profile)
	assert(not service.saveNow(p, 0.1))
	assert(not service.saveNow(p, 0, function() return true end))
end

tests["saveNow cannot acknowledge an older restored revision"] = function()
	local service, p, profile = fresh(), player(), fakeProfile()
	profile.Data._saveRevision, profile.LastSavedData._saveRevision = 1, 99
	service._setForTest(p, profile.Data, profile)
	assert(not service.saveNow(p, 0) and profile.Data._saveRevision == 100)
end

tests["saveNow checks saved receipt predicate"] = function()
	local service, p, profile = fresh(), player(), fakeProfile()
	profile.Save = function(self) self.LastSavedData = table.clone(self.Data) end
	service._setForTest(p, profile.Data, profile)
	assert(not service.saveNow(p, 0, function(saved) return saved.receipt == "expected" end))
	profile.Data.receipt = "expected"
	assert(service.saveNow(p, 0, function(saved) return saved.receipt == "expected" end))
end

tests["inactive session never exposes mutable profile"] = function()
	local service, p, profile = fresh(), player(), fakeProfile()
	service._setForTest(p, profile.Data, profile)
	profile.active = false
	assert(service.get(p) == nil and not service.saveNow(p))
	local ok, code = service.update(p, function() error("should not mutate") end)
	assert(not ok and code == "NotLoaded")
end

tests["release hook snapshots before removal and runs once"] = function()
	local service, p, profile = fresh(), player(), fakeProfile()
	local called, value = 0, nil
	service._setForTest(p, profile.Data, profile)
	profile.Data.weaponsForged = 123
	service.registerReleaseHook("Leaderboard", function(who, data, reason)
		called += 1
		assert(who == p and service.get(p) == data and reason == "Leave")
		value = data.weaponsForged
	end)
	service._releaseForTest(p)
	service._releaseForTest(p)
	assert(called == 1 and value == 123 and service.get(p) == nil and profile.ends == 1)
end

tests["defaults preserve existing progress and isolate nested tables"] = function()
	local service = fresh()
	service.registerDefaults({custom = {pets = {}}})
	local a, b = player(1), player(2)
	local dataA, dataB = Economy.newProfile(), Economy.newProfile()
	dataA.coins = 12345
	service._setForTest(a, dataA)
	service._setForTest(b, dataB)
	table.insert(dataA.custom.pets, "pet")
	assert(dataA.coins == 12345 and #dataB.custom.pets == 0)
end
return tests
