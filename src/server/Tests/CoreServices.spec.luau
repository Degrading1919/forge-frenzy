-- Core economy services driven with an in-memory profile and a fake player.
-- Runs in Studio and under Lune; restores every override it makes.

local Services = script.Parent.Parent.Services
local DataService = require(Services.DataService)
local ProductionService = require(Services.ProductionService)
local ForgeService = require(Services.ForgeService)
local UpgradeService = require(Services.UpgradeService)
local Economy = require(game:GetService("ReplicatedStorage").Shared.Economy)

local Players = game:GetService("Players")

local function withForge(fn: (any, { now: number }) -> (), owned: { [string]: boolean }?)
	local player = { UserId = -4242, Name = "SpecSmith", Parent = Players }
	local clock = { now = 1000 }
	local saved = { clock = ForgeService.clock, delay = ForgeService.delay, rng = ForgeService.rng, service = ProductionService._service }
	if owned then
		ProductionService._service = function(name)
			if name == "MonetizationService" then
				return { owns = function(_, key) return owned[key] == true end }
			end
			return saved.service(name)
		end
	end
	ForgeService.clock = function()
		return clock.now
	end
	ForgeService.delay = function() end -- tests complete sessions explicitly
	ForgeService.rng = Random.new(31337)
	DataService._setForTest(player, Economy.newProfile())
	local ok, err = pcall(fn, player, clock)
	ForgeService.clock, ForgeService.delay, ForgeService.rng = saved.clock, saved.delay, saved.rng
	ProductionService._service = saved.service
	DataService._setForTest(player, nil)
	if not ok then
		error(err, 0)
	end
end

local tests = {}

tests["lifecycle start() with no player is a harmless no-op"] = function()
	local ok = ForgeService.start()
	assert(ok == true)
end

tests["manual forge counts only window strikes and rolls server luck"] = function()
	withForge(function(player, clock)
		local ok, info = ForgeService.start(player, 1, 1, "manual")
		assert(ok, info)
		assert(info.heatSec == 2 and info.windowSec == 6 and info.revealSec == 1.5, "timing")
		assert(not ForgeService.strike(player, info.sessionId), "strike during heat counted")
		local busy, code = ForgeService.start(player, 1, 1, "manual")
		assert(not busy and code == "Busy", "second session allowed")
		-- 5 strikes per second for the full window -> 2.5x
		for i = 0, 29 do
			clock.now = 1000 + 2 + i * 0.2
			assert(ForgeService.strike(player, info.sessionId), "window strike rejected")
		end
		assert(not ForgeService.strike(player, info.sessionId .. "x"), "wrong session id accepted")
		assert(type(info.sessionId) == "string", "session ids are strings for the Strike remote")
		local luckSeen
		local conn = ForgeService.completed.Event:Connect(function(_, _, luck)
			luckSeen = luck
		end)
		clock.now = 1000 + 2 + 6 + 0.35
		ForgeService._completeNow(player)
		task.wait() -- Studio's deferred signal mode runs handlers at the next resumption point
		conn:Disconnect()
		assert(math.abs(luckSeen - 2.5) < 1e-9, "luck " .. tostring(luckSeen))
		local data = DataService.get(player)
		assert(data.pending and data.ingots[1] == Economy.STARTER_INGOTS - 1, "result stored, ingot spent")
		assert(not ForgeService.strike(player, info.sessionId), "strike after completion")
		-- reveal must finish before the next forge
		assert(not ForgeService.start(player, 1, 1, "manual"), "started during reveal")
		clock.now += 1.5
		assert(ForgeService.start(player, 1, 1, "manual"), "could not start after reveal")
	end)
end

tests["resolve sells once and keep moves to inventory"] = function()
	withForge(function(player)
		assert(ForgeService.start(player, 2, 1, "free"))
		ForgeService._completeNow(player)
		local data = DataService.get(player)
		local value = data.pending.v
		local ok, result = ForgeService.resolve(player, "sell")
		assert(ok and result.coins == value and data.coins == value)
		local again = ForgeService.resolve(player, "sell")
		assert(not again and data.coins == value, "paid twice")
	end)
end

tests["premium auto forge needs the entitlement"] = function()
	withForge(function(player)
		local hasMonetization = Services:FindFirstChild("MonetizationService") ~= nil
		local ok, code = ForgeService.start(player, 1, 1, "premium")
		if not hasMonetization then
			assert(not ok and code == "NotOwned", "premium without entitlement")
		end
		local bad, badCode = ForgeService.start(player, 1, 1, "turbo")
		assert(not bad and badCode == "InvalidMode")
	end)
end

tests["auto forge stops when ingots run out"] = function()
	withForge(function(player, clock)
		local queued = {}
		ForgeService.delay = function(_, fn)
			table.insert(queued, fn)
		end
		local reason
		local conn = ForgeService.stopped.Event:Connect(function(_, why)
			reason = why
		end)
		assert(ForgeService.start(player, 1, 1, "free"))
		local guard = 0
		while #queued > 0 and guard < 50 do
			guard += 1
			clock.now += 20
			table.remove(queued, 1)()
		end
		task.wait() -- flush deferred signal handlers in Studio
		conn:Disconnect()
		local data = DataService.get(player)
		assert(data.weaponsForged == Economy.STARTER_INGOTS, "forged " .. data.weaponsForged)
		assert(reason == "NoMaterial", "stop reason " .. tostring(reason))
		assert(data.pending ~= nil and Economy.weaponCount(data) == Economy.STARTER_INGOTS - 1, "previous results auto-kept")
	end)
end

tests["production, unlocks and upgrades go through the services"] = function()
	withForge(function(player)
		local data = DataService.get(player)
		data.ingots[1] = 0
		local ore = ProductionService.tickPlayer(player, 12)
		assert(ore == 2, "ore " .. ore)
		local rates = ProductionService.rates(player)
		assert(rates and rates.capacity == 30)
		local ok, code = ProductionService.selectMaterial(player, 2)
		assert(not ok and code == "MaterialLocked")
		data.coins = 1000
		assert(ProductionService.unlockNextMaterial(player) and data.unlockedTier == 2)
		assert(UpgradeService.buy(player, "StorageCapacity") and data.levels.StorageCapacity == 1)
		assert(ProductionService.rates(player).capacity == 40)
		local list = UpgradeService.list(player)
		assert(list and #list == 8, "8 tracks listed")
	end)
end

tests["auto-sell setting sells low rarities on completion"] = function()
	withForge(function(player)
		local data = DataService.get(player)
		data.settings = { autoSellBelow = 7 } -- sells every rarity
		assert(ForgeService.start(player, 1, 1, "free"))
		ForgeService._completeNow(player)
		assert(data.pending == nil and data.coins > 0 and data.weaponsSold == 1, "not auto-sold")
	end, { CollectionMagnet = true })
end

tests["glue helpers: timings, costs, sellKept, showcase slots"] = function()
	withForge(function(player)
		local data = DataService.get(player)
		local t = ForgeService.timings(player)
		assert(t and t.heatSec == 2 and t.windowSec == 6 and t.revealSec == 1.5)
		assert(ProductionService.unlockCost(player) == 414)
		assert(UpgradeService.cost(player, "ExtractorOutput") == 40)
		assert(UpgradeService.cost(player, "Nope") == false)
		data.weapons.k = { id = "k", m = 1, c = 1, q = 1, r = 1, d = "x", v = 25, ts = 0 }
		assert(ForgeService.setShowcase(player, 2, "k") and data.showcase[2] == "k")
		assert(not ForgeService.sellKept(player, "k"), "showcased weapon sold")
		assert(ForgeService.setShowcase(player, 2, nil) and data.showcase[2] == "")
		local ok, result = ForgeService.sellKept(player, "k")
		assert(ok and result.coins == 25 and data.coins == 25)
	end)
end

tests["calls for unloaded players fail without erroring"] = function()
	local ghost = { UserId = -1, Name = "Ghost", Parent = Players }
	assert(select(2, ForgeService.start(ghost, 1, 1, "manual")) == "NotLoaded")
	assert(select(2, ForgeService.resolve(ghost, "sell")) == "NotLoaded")
	assert(select(2, UpgradeService.buy(ghost, "Hammer")) == "NotLoaded")
	assert(select(2, ProductionService.unlockNextMaterial(ghost)) == "NotLoaded")
	assert(ProductionService.rates(ghost) == nil)
end

return tests
