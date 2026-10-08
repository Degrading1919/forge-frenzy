-- Multiple forge stations (build pads): per-station sessions, recipes and auto loops.
-- Fake player, in-memory profile; every override is restored.

local Services = script.Parent.Parent.Services
local Forge = require(Services.ForgeService)
local Data = require(Services.DataService)
local Production = require(Services.ProductionService)
local Shared = game:GetService("ReplicatedStorage").Shared
local Economy = require(Shared.Economy)
local Balance = require(Shared.Config.Balance)
local Players = game:GetService("Players")

local function fixture(fn)
	local player = { UserId = -6100, Name = "TwoForgeSmith", Parent = Players }
	local p = Economy.newProfile()
	p.unlockedTier = 4
	p.pads.forge_2 = true
	p.pads.forge_3 = true -- ignoring the tier gate: this is a raw profile
	p.weaponsForged = Balance.forge.autoUnlockAfterForges
	for i = 1, 4 do p.ingots[i] = 30 end
	local state = { now = 1000, timers = {} }
	local saved = { clock = Forge.clock, delay = Forge.delay, rng = Forge.rng, serverTime = Forge.serverTime, service = Production._service, near = Forge.nearStation }
	Forge.clock = function() return state.now end
	Forge.serverTime = function() return state.now end
	Forge.delay = function(_, callback) table.insert(state.timers, callback) end
	Forge.rng = Random.new(606)
	Production._service = function() return nil end
	Data._setForTest(player, p)
	local ok, err = pcall(fn, player, p, state)
	Forge.stopAuto(player)
	Forge.clock, Forge.delay, Forge.rng, Forge.serverTime, Forge.nearStation = saved.clock, saved.delay, saved.rng, saved.serverTime, saved.near
	Production._service = saved.service
	Data._setForTest(player, nil)
	if not ok then error(err, 0) end
end

local tests = {}

tests["owned pads give the player that many forge stations"] = function()
	fixture(function(player, p)
		assert(#p.stations == 3 and Economy.forgeCount(p) == 3)
		assert(Forge.begin(player, 3, "manual"))
		local ok, why = Forge.begin(player, 4, "manual")
		assert(not ok and why == "InvalidStation", "a fourth forge does not exist")
	end)
end

tests["only one manual forge at a time, but auto loops run alongside it on other stations"] = function()
	fixture(function(player, p)
		assert(Forge.begin(player, 1, "manual"))
		local ok, why = Forge.begin(player, 2, "manual")
		assert(not ok and why == "Busy", "hands are busy at station 1")
		assert(Forge.begin(player, 2, "free"), "auto forge on station 2 while hammering station 1")
		assert(Forge.begin(player, 3, "free"))
		local status = Forge.status(player)
		assert(status[1].mode == "manual" and status[2].auto and status[3].auto)
		-- once station 1 is finished, the player can hammer elsewhere
		Forge._completeNow(player, 1)
		assert(Forge.session(player, 1).done)
	end)
end

tests["each station forges its own recipe and completes independently"] = function()
	fixture(function(player, p)
		assert(Forge.configure(player, 1, 1, 4, 1)) -- Copper Dagger, 1 ingot
		assert(Forge.configure(player, 2, 3, 3, 1)) -- Bronze Axe, 3 ingots
		assert(Forge.configure(player, 3, 4, 2, 1)) -- Iron Greatsword, 5 ingots
		for station = 1, 3 do
			assert(Forge.begin(player, station, "free"))
		end
		local before = { p.ingots[1], p.ingots[3], p.ingots[4] }
		Forge._completeNow(player, 2)
		assert(p.ingots[3] == before[2] - 3 and p.ingots[1] == before[1] and p.ingots[4] == before[3], "only station 2's recipe was charged")
		Forge._completeNow(player, 3)
		assert(p.ingots[4] == before[3] - 5 and p.ingots[1] == before[1])
		Forge._completeNow(player, 1)
		assert(p.ingots[1] == before[1] - 1)
		assert(p.weaponsForged == Balance.forge.autoUnlockAfterForges + 3)
		local classes = {}
		for _, w in p.weapons do classes[w.c] = (classes[w.c] or 0) + 1 end
		assert(classes[4] == 1 and classes[3] == 1 and classes[2] == 1, "one weapon per recipe")
		assert(Forge.session(player, 1).id ~= Forge.session(player, 2).id)
	end)
end

tests["the completed event names the station"] = function()
	fixture(function(player)
		local stations = {}
		local conn = Forge.completed.Event:Connect(function(_, payload)
			table.insert(stations, payload.station)
		end)
		assert(Forge.begin(player, 2, "free"))
		assert(Forge.begin(player, 3, "free"))
		Forge._completeNow(player, 3)
		Forge._completeNow(player, 2)
		task.wait()
		conn:Disconnect()
		assert(#stations == 2 and stations[1] == 3 and stations[2] == 2)
	end)
end

tests["reconfiguring or stopping one station leaves the others running"] = function()
	fixture(function(player)
		for station = 1, 3 do assert(Forge.begin(player, station, "free")) end
		local ok, result = Forge.configure(player, 2, 2, 1, 4)
		assert(ok and result.stoppedAuto)
		assert(Forge.session(player, 1).auto and not Forge.session(player, 2).auto and Forge.session(player, 3).auto)
		assert(Forge.stopAuto(player, 3))
		assert(Forge.session(player, 1).auto and not Forge.session(player, 3).auto)
		assert(select(2, Forge.stopAuto(player, 3)) == "NotAuto")
		assert(select(2, Forge.stopAuto(player, 2)) == "NotAuto")
		assert(Forge.stopAuto(player))
		assert(not Forge.session(player, 1).auto, "stopAuto with no station stops them all")
	end)
end

tests["a waiting station does not block the others and waits independently"] = function()
	fixture(function(player, p, state)
		p.ingots[1] = 0
		p.ingots[3] = 30
		assert(Forge.configure(player, 1, 1, 4, 1))
		assert(Forge.configure(player, 2, 3, 4, 1))
		local ok, info = Forge.begin(player, 1, "free")
		assert(ok and info.waiting)
		ok, info = Forge.begin(player, 2, "free")
		assert(ok and not info.waiting and info.heatSec)
		Forge._completeNow(player, 2)
		assert(p.weaponsForged == Balance.forge.autoUnlockAfterForges + 1)
		assert(Forge.session(player, 1).waiting, "station 1 is still waiting for Copper")
		p.ingots[1] = 1
		state.now += 5
		for _, callback in table.clone(state.timers) do callback() end
		assert(not Forge.session(player, 1).waiting, "station 1 resumed once Copper arrived")
	end)
end

tests["evolution cancels every station's session"] = function()
	fixture(function(player, p)
		local forged = p.weaponsForged
		for station = 1, 3 do assert(Forge.begin(player, station, "free")) end
		p.evolutionRank = 1
		for station = 1, 3 do Forge._completeNow(player, station) end
		assert(p.weaponsForged == forged)
		for station = 1, 3 do
			assert(not Forge.session(player, station).auto, "station " .. station .. " still looping")
		end
	end)
end

return tests
