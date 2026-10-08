-- Core economy services (v2) driven with an in-memory profile and a fake player.
-- Runs in Studio and under Lune; restores every override it makes.

local Services = script.Parent.Parent.Services
local DataService = require(Services.DataService)
local ProductionService = require(Services.ProductionService)
local ForgeService = require(Services.ForgeService)
local UpgradeService = require(Services.UpgradeService)
local Shared = game:GetService("ReplicatedStorage").Shared
local Economy = require(Shared.Economy)
local Balance = require(Shared.Config.Balance)
local Materials = require(Shared.Config.Materials)

local Players = game:GetService("Players")

type Fixture = {
	now: number,
	timers: { () -> () },
	owned: { [string]: boolean },
	cash: number?,
}

-- opts.setup runs on the fresh profile before it is registered (so reconcile sees pads).
local function withForge(fn: (any, Fixture, any) -> (), opts: { setup: ((any) -> ())?, owned: { [string]: boolean }?, cash: number? }?)
	local options = opts or {}
	local player = { UserId = -4242, Name = "SpecSmith", Parent = Players }
	local state: Fixture = { now = 1000, timers = {}, owned = options.owned or {}, cash = options.cash }
	local saved = {
		clock = ForgeService.clock,
		delay = ForgeService.delay,
		rng = ForgeService.rng,
		near = ForgeService.nearStation,
		serverTime = ForgeService.serverTime,
		service = ProductionService._service,
	}
	ProductionService._service = function(name)
		if name == "MonetizationService" then
			return { owns = function(_, key) return state.owned[key] == true end }
		elseif name == "EvolutionService" and state.cash then
			return { bonuses = function() return { production = 0, prep = 0, cash = state.cash } end }
		end
		return saved.service(name)
	end
	ForgeService.clock = function()
		return state.now
	end
	ForgeService.delay = function(_, callback) -- tests run queued timers explicitly
		table.insert(state.timers, callback)
	end
	ForgeService.rng = Random.new(31337)
	ForgeService.serverTime = function()
		return state.now
	end
	local profile = Economy.newProfile()
	if options.setup then
		options.setup(profile)
	end
	DataService._setForTest(player, profile)
	local ok, err = pcall(fn, player, state, DataService.get(player))
	ForgeService.stopAuto(player)
	ForgeService.clock, ForgeService.delay, ForgeService.rng, ForgeService.nearStation = saved.clock, saved.delay, saved.rng, saved.near
	ForgeService.serverTime = saved.serverTime
	ProductionService._service = saved.service
	DataService._setForTest(player, nil)
	if not ok then
		error(err, 0)
	end
end

-- Auto Forge unlocks after a few forges (the tutorial teaches it).
local function autoReady(p: any)
	p.weaponsForged = Balance.forge.autoUnlockAfterForges
end

local tests = {}

tests["lifecycle start() with no player is a harmless no-op"] = function()
	local ok = ForgeService.start()
	assert(ok == true)
end

tests["manual forge counts only window strikes and rolls server luck"] = function()
	withForge(function(player, state)
		local ok, info = ForgeService.start(player, 1, "manual")
		assert(ok, info)
		assert(info.station == 1 and info.heatSec == 2 and info.windowSec == 6 and info.revealSec == 1.5, "timing")
		assert(type(info.sessionId) == "string", "session ids are strings for the Strike remote")
		assert(not ForgeService.strike(player, info.sessionId), "strike during heat counted")
		local busy, code = ForgeService.start(player, 1, "manual")
		assert(not busy and code == "Busy", "second session allowed")
		-- 5 strikes per second for the full window -> 2.5x
		for i = 0, 29 do
			state.now = 1000 + 2 + i * 0.2
			assert(ForgeService.strike(player, info.sessionId), "window strike rejected")
		end
		assert(not ForgeService.strike(player, info.sessionId .. "x"), "wrong session id accepted")
		local payload
		local conn = ForgeService.completed.Event:Connect(function(_, p)
			payload = p
		end)
		state.now = 1000 + 2 + 6 + 0.35
		ForgeService._completeNow(player, 1)
		task.wait() -- Studio's deferred signal mode runs handlers at the next resumption point
		conn:Disconnect()
		assert(payload and math.abs(payload.luck - 2.5) < 1e-9, "luck " .. tostring(payload and payload.luck))
		assert(payload.station == 1 and payload.mode == "manual" and payload.auto == false and payload.strikes == 30)
		assert(#payload.results == 1 and payload.results[1].sold == false)
		local data = DataService.get(player)
		local weapon = payload.results[1].weapon
		assert(data.weapons[weapon.id] == weapon, "manual results always go to the backpack")
		assert(data.ingots[1] == Economy.STARTER_INGOTS - 1 and data.weaponsForged == 1, "ingot spent")
		assert(data.pending == nil)
		assert(not ForgeService.strike(player, info.sessionId), "strike after completion")
		-- reveal must finish before the next forge
		local during, duringCode = ForgeService.start(player, 1, "manual")
		assert(not during and duringCode == "Busy", "started during reveal")
		state.now += 1.5
		assert(ForgeService.start(player, 1, "manual"), "could not start after reveal")
	end)
end

tests["manual forge needs the player at the station"] = function()
	withForge(function(player, state)
		local asked
		ForgeService.nearStation = function(who, station)
			asked = { who, station }
			return false
		end
		local ok, code = ForgeService.start(player, 1, "manual")
		assert(not ok and code == "TooFar" and asked and asked[1] == player and asked[2] == 1)
		assert(DataService.get(player).ingots[1] == Economy.STARTER_INGOTS and ForgeService.session(player, 1) == nil, "nothing started")
		-- Auto Forge runs anywhere: it never asks
		autoReady(DataService.get(player))
		asked = nil
		assert(ForgeService.start(player, 1, "free"))
		assert(asked == nil, "auto forge must not depend on proximity")
		ForgeService.stopAuto(player, 1)
		ForgeService.nearStation = function()
			return true
		end
		assert(ForgeService.start(player, 1, "manual"), "near enough")
		assert(state.now == 1000)
	end)
end

tests["Auto Forge is locked until a few forges have been done by hand"] = function()
	assert(Balance.forge.autoUnlockAfterForges == 3)
	withForge(function(player, state)
		local data = DataService.get(player)
		for forged = 0, Balance.forge.autoUnlockAfterForges - 1 do
			data.weaponsForged = forged
			local ok, code = ForgeService.start(player, 1, "free")
			assert(not ok and code == "AutoLocked", "forged " .. forged)
			assert(ForgeService.session(player, 1) == nil)
		end
		-- the manual forge is available from the start and counts toward the unlock
		data.weaponsForged = 0
		for _ = 1, Balance.forge.autoUnlockAfterForges do
			assert(ForgeService.start(player, 1, "manual"))
			ForgeService._completeNow(player, 1)
			state.now += 10
		end
		assert(data.weaponsForged == 3)
		local ok, info = ForgeService.start(player, 1, "free")
		assert(ok and info.sessionId, "three forges unlock Auto Forge")
	end)
end

tests["start validates mode, station and premium entitlement"] = function()
	withForge(function(player)
		autoReady(DataService.get(player))
		local hasMonetization = Services:FindFirstChild("MonetizationService") ~= nil
		local ok, code = ForgeService.start(player, 1, "premium")
		if not hasMonetization then
			assert(not ok and code == "NotOwned", "premium without entitlement")
		end
		local bad, badCode = ForgeService.start(player, 1, "turbo")
		assert(not bad and badCode == "InvalidMode")
		for _, station in { 2, 0, -1, 1.5, "1", false } do
			local nope, why = ForgeService.start(player, station, "manual")
			assert(not nope and why == "InvalidStation", "station " .. tostring(station))
		end
		local ghost, ghostWhy = ForgeService.start(player, nil, "manual")
		assert(not ghost and ghostWhy == "InvalidStation")
	end)
end

tests["auto forge keeps forging until the ingots run out, then waits instead of stopping"] = function()
	withForge(function(player, state)
		local data = DataService.get(player)
		local stoppedWith
		local conn = ForgeService.stopped.Event:Connect(function(_, _, why)
			stoppedWith = why
		end)
		assert(ForgeService.start(player, 1, "free"))
		local guard = 0
		while #state.timers > 0 and guard < 80 do
			guard += 1
			state.now += 20
			table.remove(state.timers, 1)()
		end
		task.wait() -- flush deferred signal handlers in Studio
		conn:Disconnect()
		assert(data.weaponsForged == 3 + Economy.STARTER_INGOTS, "forged " .. data.weaponsForged)
		assert(data.ingots[1] == 0)
		assert(stoppedWith == nil, "an empty vault must not stop the loop, got " .. tostring(stoppedWith))
		local session = ForgeService.session(player, 1)
		assert(session and session.auto and session.waiting, "waiting for ingots")
		assert(ForgeService.status(player)[1].waiting == true and ForgeService.status(player)[1].phase == "waiting")
	end, { setup = autoReady })
end

tests["a waiting auto forge resumes by itself when the ore line delivers ingots"] = function()
	withForge(function(player, state)
		local data = DataService.get(player)
		local phases = {}
		local conn = ForgeService.phase.Event:Connect(function(_, info)
			table.insert(phases, info.phase)
		end)
		local ok, info = ForgeService.start(player, 1, "free")
		assert(ok and info.waiting == true and info.sessionId, "starting with no ingots waits")
		assert(data.weaponsForged == 3 and phases[#phases] == "waiting")
		-- still empty: the retry just waits again
		state.now += 5
		table.remove(state.timers, 1)()
		assert(ForgeService.session(player, 1).waiting and ForgeService.session(player, 1).auto)
		-- the ore line produces an ingot
		data.ingots[1] = 2
		state.now += 5
		table.remove(state.timers, 1)()
		local session = ForgeService.session(player, 1)
		assert(session.auto and not session.waiting and session.phaseName == "heat", "resumed into a real forge")
		ForgeService._completeNow(player, 1)
		task.wait()
		conn:Disconnect()
		assert(data.weaponsForged == 4 and data.ingots[1] == 1)
		assert(table.find(phases, "heat") and table.find(phases, "quench"))
	end, { setup = function(p)
		autoReady(p)
		p.ingots[1] = 0
	end })
end

tests["configuring a station stops its auto loop cleanly instead of answering Busy"] = function()
	withForge(function(player, state)
		local data = DataService.get(player)
		data.unlockedTier = 2
		local reason
		local conn = ForgeService.stopped.Event:Connect(function(_, station, why)
			reason = { station, why }
		end)
		assert(ForgeService.start(player, 1, "free"))
		local ok, result = ForgeService.configure(player, 1, 2, 1, 6)
		assert(ok, tostring(result))
		task.wait()
		conn:Disconnect()
		assert(result.stoppedAuto == true and result.station == data.stations[1])
		assert(data.stations[1].m == 2 and data.stations[1].c == 1 and data.stations[1].keep == 6)
		assert(reason and reason[1] == 1 and reason[2] == "Reconfigured")
		local session = ForgeService.session(player, 1)
		assert(not session.auto and session.done, "loop stopped")
		-- stale timers cannot restart or complete the old forge
		for _, callback in state.timers do
			state.now += 20
			callback()
		end
		assert(data.weaponsForged == 3 and data.ingots[1] == Economy.STARTER_INGOTS, "stopped loop spent ingots")
		-- invalid configurations are refused and leave a running loop alone
		data.stations[1].m = 1
		assert(ForgeService.start(player, 1, "free"))
		local bad, code = ForgeService.configure(player, 1, 9, 1, 6)
		assert(not bad and code == "MaterialLocked" and ForgeService.session(player, 1).auto, "failed configure must not stop auto")
		bad, code = ForgeService.configure(player, 3, 1, 1, 4)
		assert(not bad and code == "InvalidStation")
		bad, code = ForgeService.configure(player, 1, 40, 1, 4)
		assert(not bad and code == "InvalidMaterial")
		bad, code = ForgeService.configure(player, 1, 1, 9, 4)
		assert(not bad and code == "InvalidClass")
		bad, code = ForgeService.configure(player, 1, 1, 1, 9)
		assert(not bad and code == "InvalidSetting")
		assert(ForgeService.session(player, 1).auto, "refused configures leave the loop running")
		-- a configure with no loop running reports no stop
		ForgeService.stopAuto(player)
		ok, result = ForgeService.configure(player, 1, 1, 4, 4)
		assert(ok and result.stoppedAuto == false)
	end, { setup = autoReady })
end

tests["configure does not interrupt a manual forge in progress"] = function()
	withForge(function(player)
		assert(ForgeService.start(player, 1, "manual"))
		local ok, code = ForgeService.configure(player, 1, 1, 1, 4)
		assert(not ok and code == "Busy")
		assert(DataService.get(player).stations[1].c == Economy.STARTER_CLASS, "recipe unchanged during a manual forge")
	end)
end

tests["stopAuto abandons the forge in progress without spending anything"] = function()
	withForge(function(player, state)
		local data = DataService.get(player)
		local stops = {}
		local conn = ForgeService.stopped.Event:Connect(function(_, station, why)
			table.insert(stops, { station, why })
		end)
		local nothing, why = ForgeService.stopAuto(player)
		assert(not nothing and why == "NotAuto")
		assert(ForgeService.start(player, 1, "free"))
		local ok = ForgeService.stopAuto(player, 1)
		assert(ok)
		task.wait()
		conn:Disconnect()
		assert(#stops == 1 and stops[1][1] == 1 and stops[1][2] == "Stopped")
		ForgeService._completeNow(player, 1)
		for _, callback in state.timers do
			state.now += 20
			callback()
		end
		assert(data.weaponsForged == 3 and data.ingots[1] == Economy.STARTER_INGOTS and next(data.weapons) == nil, "abandoned forge cost ingots or produced a weapon")
		local session = ForgeService.session(player, 1)
		assert(session.done and not session.auto, "loop stays stopped after queued timers fire")
		-- stopping again is a clean no-op
		local again, againWhy = ForgeService.stopAuto(player, 1)
		assert(not again and againWhy == "NotAuto")
		-- a finished batch is kept when the loop is stopped during the reveal
		state.timers = {}
		assert(ForgeService.start(player, 1, "free"))
		ForgeService._completeNow(player, 1)
		assert(data.weaponsForged == 4)
		assert(ForgeService.stopAuto(player, 1))
		state.now += 30
		for _, callback in table.clone(state.timers) do
			callback()
		end
		assert(data.weaponsForged == 4, "stopped loop must not start the next forge")
		assert(ForgeService.session(player, 1).auto == false)
	end, { setup = autoReady })
end

tests["a station's keep rule sells low rarities at once and everything on 7"] = function()
	withForge(function(player)
		local data = DataService.get(player)
		data.ingots[1] = 40
		local seen = { sold = 0, kept = 0 }
		local conn = ForgeService.completed.Event:Connect(function(_, payload)
			for _, result in payload.results do
				if result.sold then
					seen.sold += 1
				else
					seen.kept += 1
				end
			end
		end)
		-- keep 7: everything sells and pays
		assert(ForgeService.configure(player, 1, 1, 4, 7))
		for _ = 1, 5 do
			assert(ForgeService.start(player, 1, "free"))
			ForgeService._completeNow(player, 1)
		end
		task.wait()
		assert(seen.kept == 0 and seen.sold == 5 and next(data.weapons) == nil and data.coins > 0 and data.weaponsSold == 5)
		assert(data.lifetimeCoins == data.coins, "sales count as earned cash")
		-- keep 1: nothing sells
		assert(ForgeService.configure(player, 1, 1, 4, 1))
		for _ = 1, 5 do
			assert(ForgeService.start(player, 1, "free"))
			ForgeService._completeNow(player, 1)
		end
		task.wait()
		conn:Disconnect()
		assert(seen.kept == 5 and Economy.weaponCount(data) == 5)
	end, { setup = autoReady })
end

tests["a full backpack makes auto forges sell and refuses manual ones"] = function()
	withForge(function(player, state)
		local data = DataService.get(player)
		for i = 1, Balance.inventory.maxWeapons do
			data.weapons["old" .. i] = { id = "old" .. i, m = 1, c = 1, q = 1, r = 1, d = "x", v = 1, ts = 0 }
		end
		data.stations[1].keep = 1
		local ok, code = ForgeService.start(player, 1, "manual")
		assert(not ok and code == "InventoryFull")
		assert(ForgeService.start(player, 1, "free"))
		ForgeService._completeNow(player, 1)
		assert(Economy.weaponCount(data) == Balance.inventory.maxWeapons, "cap never exceeded")
		assert(data.weaponsSold == 1 and data.coins > 0 and data.weaponsForged == 4, "auto result sold instead of lost")
		assert(state.now == 1000)
	end, { setup = autoReady })
end

tests["the evolution cash multiplier raises every forged value within the scaled band"] = function()
	withForge(function(player)
		assert(ForgeService.cashMultiplier(player) == 2.5)
		local data = DataService.get(player)
		data.ingots[1] = 30
		data.stations[1].keep = 1
		local lo = math.floor(Materials[1].priceMin * Balance.weaponClasses[4].valueMult * 2.5 + 0.5)
		local hi = math.floor(Materials[1].priceMax * Balance.weaponClasses[4].valueMult * 2.5 + 0.5)
		for _ = 1, 10 do
			assert(ForgeService.start(player, 1, "free"))
			ForgeService._completeNow(player, 1)
		end
		for _, w in data.weapons do
			assert(w.v >= lo and w.v <= hi, `value {w.v} outside [{lo}, {hi}]`)
		end
	end, { cash = 2.5, setup = autoReady })
	withForge(function(player)
		assert(ForgeService.cashMultiplier(player) == 1, "no multiplier without evolution")
	end)
end

tests["selling goes through the service and respects protection"] = function()
	withForge(function(player)
		local data = DataService.get(player)
		data.weapons.a = { id = "a", m = 1, c = 1, q = 1, r = 1, d = "x", v = 25, ts = 0 }
		data.weapons.b = { id = "b", m = 1, c = 1, q = 1, r = 3, d = "x", v = 75, ts = 0 }
		data.weapons.c = { id = "c", m = 1, c = 1, q = 1, r = 1, d = "x", v = 10, ts = 0 }
		assert(Economy.setShowcase(data, 1, "c"))
		local ok, result = ForgeService.sellWeapons(player, { "a", "c" }, { b = true })
		assert(ok and result.coins == 25 and data.coins == 25 and data.weapons.c ~= nil, "displayed weapon sold")
		local again = ForgeService.sellWeapons(player, { "a" })
		assert(not again and data.coins == 25, "paid twice")
		local all, allResult = ForgeService.sellAll(player, nil, { b = true })
		assert(not all and allResult == "NothingSold", "protected and displayed weapons stay")
		all, allResult = ForgeService.sellAll(player)
		assert(all and allResult.coins == 75 and data.weapons.b == nil and data.weapons.c ~= nil)
	end)
end

tests["production, unlocks and upgrades go through the services"] = function()
	withForge(function(player)
		local data = DataService.get(player)
		data.ingots[1] = 0
		local ore = ProductionService.tickPlayer(player, 12)
		assert(ore == 4, "ore " .. ore)
		local rates = ProductionService.rates(player)
		assert(rates and rates.capacity == 25 and rates.lines == 1)
		local ok, code = ProductionService.selectMaterial(player, 2)
		assert(not ok and code == "MaterialLocked")
		ok, code = ProductionService.setLineMaterial(player, 2, 1)
		assert(not ok and code == "InvalidLine")
		ok, code = ProductionService.unlockMaterial(player, 3)
		assert(not ok and code == "UnlockPrevious")
		assert(ProductionService.unlockCost(player) == Materials[2].unlockCost)
		ok, code = ProductionService.unlockNextMaterial(player)
		assert(not ok and code == "NotEnoughCoins")
		data.coins = Materials[2].unlockCost
		local unlocked
		local conn = ProductionService.materialUnlocked.Event:Connect(function(_, index)
			unlocked = index
		end)
		assert(ProductionService.unlockNextMaterial(player) and data.unlockedTier == 2 and data.lines[1].m == 2 and data.coins == 0)
		task.wait()
		conn:Disconnect()
		assert(unlocked == 2 and data.highestTierEver == 2)
		assert(ProductionService.setLineMaterial(player, 1, 1) and data.lines[1].m == 1)
		data.coins = Balance.upgradeCost("StorageCapacity", 0) :: number
		assert(UpgradeService.buy(player, "StorageCapacity") and data.levels.StorageCapacity == 1)
		assert(ProductionService.rates(player).capacity == 35)
		assert(UpgradeService.cost(player, "ExtractorOutput") == 150)
		assert(UpgradeService.cost(player, "Nope") == false)
		local list = UpgradeService.list(player)
		assert(list and #list == 8, "8 tracks listed")
		assert(select(2, UpgradeService.buy(player, "Hammer")) == "NotEnoughCoins")
	end)
end

tests["glue helpers: timings, odds and status"] = function()
	withForge(function(player)
		autoReady(DataService.get(player))
		local t = ForgeService.timings(player)
		assert(t and t.heatSec == 2 and t.windowSec == 6 and t.revealSec == 1.5)
		assert(ForgeService.odds("free").luck == Balance.forge.auto.freeLuck)
		assert(ForgeService.odds("manual").luck == Balance.forge.manual.maxLuck)
		assert(next(ForgeService.status(player)) == nil, "no sessions yet")
		assert(ForgeService.start(player, 1, "free"))
		local status = ForgeService.status(player)[1]
		assert(status.mode == "free" and status.auto == true and status.phase == "heat" and status.sessionId)
	end)
end

tests["calls for unloaded players fail without erroring"] = function()
	local ghost = { UserId = -1, Name = "Ghost", Parent = Players }
	assert(select(2, ForgeService.start(ghost, 1, "manual")) == "NotLoaded")
	assert(select(2, ForgeService.configure(ghost, 1, 1, 1, 4)) == "NotLoaded")
	assert(select(2, ForgeService.sellAll(ghost)) == "NotLoaded")
	assert(select(2, ForgeService.sellWeapons(ghost, { "a" })) == "NotLoaded")
	assert(select(2, ForgeService.stopAuto(ghost)) == "NotAuto")
	assert(select(2, UpgradeService.buy(ghost, "Hammer")) == "NotLoaded")
	assert(select(2, ProductionService.unlockNextMaterial(ghost)) == "NotLoaded")
	assert(select(2, ProductionService.setLineMaterial(ghost, 1, 1)) == "NotLoaded")
	assert(ProductionService.rates(ghost) == nil and ForgeService.timings(ghost) == nil)
end

return tests
