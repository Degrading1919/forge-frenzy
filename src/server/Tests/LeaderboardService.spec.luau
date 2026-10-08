-- Leaderboard encoding, write throttling, failure handling and server rankings.

local Services = script.Parent.Parent:WaitForChild("Services")

local function fresh()
	return require(Services:WaitForChild("LeaderboardService"):Clone())
end

local Logic = require(Services:WaitForChild("LeaderboardService")).Logic
local wealth = Logic.Metrics[1]
local forged = Logic.Metrics[2]

-- Fake OrderedDataStore that records writes and can be told to fail.
local function fakeStore(log: { any }, fail: boolean?)
	local data = {}
	return {
		SetAsync = function(_, key, value)
			if fail then
				error("403 StudioAccessToApisNotAllowed")
			end
			data[key] = value
			table.insert(log, { key = key, value = value })
		end,
		GetSortedAsync = function(_, ascending, size)
			local rows = {}
			for key, value in data do
				table.insert(rows, { key = key, value = value })
			end
			table.sort(rows, function(a, b)
				return if ascending then a.value < b.value else a.value > b.value
			end)
			return {
				GetCurrentPage = function()
					return table.move(rows, 1, math.min(size, #rows), 1, {})
				end,
			}
		end,
	}
end

local tests = {}

tests["four documented metrics"] = function()
	local fields = {}
	for _, metric in Logic.Metrics do
		fields[metric.field] = true
	end
	assert(fields.lifetimeCoins and fields.weaponsForged and fields.evolutionRank and fields.highestWeaponValue)
end

tests["log encoding round-trips and fits OrderedDataStore integers"] = function()
	local values = { 1, 12, 216, 999, 123456, 12516238278, 9.4e15, 3.3e18 }
	for _, v in values do
		local encoded = Logic.encode(wealth, v)
		assert(encoded == math.floor(encoded) and encoded < 2 ^ 53, "not a safe integer for " .. v)
		local decoded = Logic.decode(wealth, encoded)
		assert(math.abs(decoded - v) / v < 1e-9, `{v} decoded to {decoded}`)
	end
	assert(Logic.decode(wealth, Logic.encode(wealth, 216)) == 216)
end

tests["encoding preserves order"] = function()
	local rng = Random.new(77)
	for _ = 1, 2000 do
		local a = math.floor(10 ^ rng:NextNumber(0, 16))
		local b = a + 1 + math.floor(rng:NextNumber() * a)
		assert(Logic.encode(wealth, a) <= Logic.encode(wealth, b))
	end
	assert(Logic.encode(wealth, 1000) < Logic.encode(wealth, 1001))
end

tests["bad values encode as zero and are never written"] = function()
	assert(Logic.encode(wealth, 0 / 0) == 0 and Logic.encode(wealth, -5) == 0 and Logic.encode(forged, 0) == 0)
	assert(not Logic.shouldWrite({}, 0, 0, true))
end

tests["writes are throttled and skip unchanged values"] = function()
	local state = {}
	assert(Logic.shouldWrite(state, 10, 0))
	state.lastWritten, state.lastAt = 10, 0
	assert(not Logic.shouldWrite(state, 10, 1000), "unchanged value rewritten")
	assert(not Logic.shouldWrite(state, 11, 60), "write inside interval")
	assert(Logic.shouldWrite(state, 11, 120))
	assert(Logic.shouldWrite(state, 12, 1, true), "force flush on leave")
end

tests["flush writes each changed metric once per interval"] = function()
	local Service = fresh()
	local log = {}
	local stores = {}
	local t = 0
	local data = { lifetimeCoins = 5000, weaponsForged = 40, evolutionRank = 0, highestWeaponValue = 300 }
	local player = { UserId = 42 }
	Service._inject({
		getProfile = function()
			return data
		end,
		getStore = function(name)
			stores[name] = stores[name] or fakeStore(log)
			return stores[name]
		end,
		clock = function()
			return t
		end,
	})
	Service.flush(player)
	assert(#log == 3, "evolutionRank 0 should be skipped, got " .. #log)
	data.weaponsForged = 41
	t = 30
	Service.flush(player)
	assert(#log == 3, "wrote inside the interval")
	t = 200
	Service.flush(player)
	assert(#log == 4 and log[4].value == 41)
	Service.flush(player, true)
	assert(#log == 4, "forced flush rewrote unchanged values")
end

tests["guest or unloaded players are skipped"] = function()
	local Service = fresh()
	local log = {}
	Service._inject({
		getProfile = function(player)
			return if player.UserId == 1 then nil else { weaponsForged = 3 }
		end,
		getStore = function()
			return fakeStore(log)
		end,
	})
	Service.flush({ UserId = 1 }, true)
	Service.flush({ UserId = -5 }, true)
	assert(#log == 0)
end

tests["store failures disable global boards without erroring"] = function()
	local Service = fresh()
	local log = {}
	Service._inject({
		getProfile = function()
			return { weaponsForged = 3 }
		end,
		getStore = function()
			return fakeStore(log, true)
		end,
	})
	Service.flush({ UserId = 7 }, true)
	assert(not Service.isGlobalEnabled())
	Service.refresh("forged")
	assert(#Service.getTop("forged") == 0)

	local NoApi = fresh()
	NoApi._inject({
		getProfile = function()
			return { weaponsForged = 3 }
		end,
		getStore = function()
			error("You must publish this place to the web to access DataStore.")
		end,
	})
	NoApi.flush({ UserId = 7 }, true)
	assert(not NoApi.isGlobalEnabled())
end

tests["refresh caches decoded top lists with names"] = function()
	local Service = fresh()
	local log = {}
	local store = fakeStore(log)
	local profiles = {
		[1] = { lifetimeCoins = 100 },
		[2] = { lifetimeCoins = 12516238278 },
		[3] = { lifetimeCoins = 5000 },
	}
	Service._inject({
		getProfile = function(player)
			return profiles[player.UserId]
		end,
		getStore = function()
			return store
		end,
		nameFor = function(userId)
			if userId == 3 then
				error("name lookup failed")
			end
			return "smith" .. userId
		end,
	})
	for id in profiles do
		Service.flush({ UserId = id }, true)
	end
	Service.refresh("wealth")
	local top = Service.getTop("wealth", 2)
	assert(#top == 2 and top[1].userId == 2 and top[1].value == 12516238278 and top[1].name == "smith2")
	assert(Service.getTop("wealth")[2].name == "Blacksmith 3", "fallback name for failed lookups")
end

tests["server top ranks live profiles"] = function()
	local Service = fresh()
	local players = {
		{ UserId = 1, Name = "a", DisplayName = "Ann" },
		{ UserId = 2, Name = "b", DisplayName = "Bo" },
		{ UserId = 3, Name = "c", DisplayName = "Cy" },
	}
	local values = { [1] = 10, [2] = 30, [3] = 10 }
	Service._inject({
		players = function()
			return players
		end,
		getProfile = function(player)
			return { weaponsForged = values[player.UserId] }
		end,
	})
	local top = Service.getServerTop("forged")
	assert(top[1].name == "Bo" and top[2].userId == 1 and top[3].userId == 3)
	assert(#Service.getServerTop("nope") == 0)
end

return tests
