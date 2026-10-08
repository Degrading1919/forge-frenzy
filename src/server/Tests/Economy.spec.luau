-- Economy: profile rules for production, upgrades, forging, selling and showcases.
-- Pure; runs in Studio and under Lune.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Balance = require(Shared.Config.Balance)
local Materials = require(Shared.Config.Materials)

local function near(a: number, b: number, eps: number, label: string)
	assert(math.abs(a - b) <= eps, `{label}: expected {b}, got {a}`)
end

local function sum(list: { number }): number
	local s = 0
	for _, n in list do
		s += n
	end
	return s
end

local tests = {}

tests["fresh profile is DataStore-safe and playable"] = function()
	local p = Economy.newProfile()
	assert(#p.ore == 32 and #p.ingots == 32 and #p.journal == 32, "per-material arrays must be dense")
	assert(p.ingots[1] == Economy.STARTER_INGOTS and p.ingots[1] > 0, "starter ingots")
	assert(p.unlockedTier == 1 and p.selectedMaterial == 1)
	local ok = Economy.canForge(p, 1, 1)
	assert(ok, "first forge must be possible immediately")
	for _, track in Balance.machineTracks do
		assert(p.levels[track] == 0)
	end
	for _, track in Balance.gearTracks do
		assert(p.gear[track] == 0)
	end
end

tests["reconcile repairs damaged profiles without touching foreign fields"] = function()
	local p: any = {
		coins = -5,
		ore = { [3] = 4 },
		ingots = "bad",
		unlockedTier = 99,
		selectedMaterial = 50,
		levels = { ExtractorOutput = 999 },
		showcase = { "w1", "missing", "w1" },
		weapons = { w1 = { id = "w1", m = 1, c = 1, q = 1, r = 1, d = "x", v = 12, ts = 0 } },
		pets = { a = 1 },
	}
	Economy.reconcile(p)
	assert(p.coins == 0, "negative coins")
	assert(#p.ore == 32 and p.ore[3] == 4 and p.ore[1] == 0, "ore densified")
	assert(#p.ingots == 32, "ingots rebuilt")
	assert(p.unlockedTier == 32 and p.selectedMaterial == 32, "tier clamp")
	assert(p.levels.ExtractorOutput == Balance.tracks.ExtractorOutput.maxLevel, "level clamp")
	assert(p.levels.SmelterSpeed == 0, "missing level filled")
	assert(#p.showcase == 1 and p.showcase[1] == "w1", "showcase cleaned")
	assert(p.pets.a == 1, "foreign field kept")
	assert(p.gear.Hammer == 0, "gear filled")
end

tests["base rates follow the v0 numbers"] = function()
	local p = Economy.newProfile()
	local r = Economy.rates(p)
	near(r.orePerSec, 1 / 6, 1e-12, "ore")
	near(r.ingotPerSec, 1 / 6.5, 1e-12, "ingot")
	assert(r.capacity == 30 and r.oreCapacity == 30, "capacity")
	-- older material on an advanced extractor is faster, capped at 4x
	p.unlockedTier = 20
	p.selectedMaterial = 19
	near(Economy.rates(p).orePerSec, 1.15 / 6, 1e-12, "one tier behind")
	p.selectedMaterial = 1
	near(Economy.rates(p).orePerSec, 4 / 6, 1e-12, "older cap")
end

tests["bonus families are additive and capped at 3x"] = function()
	local b = Economy.combineBonuses({ { extract = 0.5 }, { extract = 0.4, smelt = 0.2 }, nil :: any, { prep = 0 / 0 } })
	near(b.extract, 0.9, 1e-12, "extract sum")
	near(b.smelt, 0.2, 1e-12, "smelt")
	assert(b.prep == 0, "NaN ignored")
	assert(Economy.familyMultiplier(10) == 3, "cap")
	assert(Economy.familyMultiplier(-1) == 1, "floor")
	local p = Economy.newProfile()
	near(Economy.rates(p, { extract = 5, smelt = 0, prep = 0, storage = 0 }).orePerSec, 3 / 6, 1e-12, "capped extract")
end

tests["settle produces at the right rate and never past caps"] = function()
	local p = Economy.newProfile()
	p.ingots[1] = 0
	local rates = Economy.rates(p)
	local ore, ingots = Economy.settle(p, 60, rates)
	assert(ore == 10, "60s at 6s/ore = 10 ore, got " .. ore)
	assert(ingots == 8, "smelter only runs once ore exists (from 6 s): 54 s / 6.5 s = 8, got " .. ingots)
	assert(p.ingots[1] == ingots and p.ore[1] == ore - ingots, "stock bookkeeping")
	-- an hour fills storage and stalls; nothing above caps
	Economy.settle(p, 3600, rates)
	assert(sum(p.ingots) == rates.capacity, "ingot cap")
	assert(sum(p.ore) == rates.oreCapacity, "ore cap")
	local before = sum(p.ore) + sum(p.ingots)
	Economy.settle(p, 3600, rates)
	assert(sum(p.ore) + sum(p.ingots) == before, "stalled pipeline must not grow")
	assert(p.progress.ore <= 1 and p.progress.smelt <= 1, "no banked progress")
end

tests["settle in one call or many ticks gives the same totals"] = function()
	local a, b = Economy.newProfile(), Economy.newProfile()
	local rates = Economy.rates(a)
	Economy.settle(a, 120, rates)
	for _ = 1, 120 do
		Economy.settle(b, 1, rates)
	end
	assert(sum(a.ingots) == sum(b.ingots) and sum(a.ore) == sum(b.ore), "tick-size dependence")
end

tests["offline settlement is capped"] = function()
	local p = Economy.newProfile()
	p.lastSeen = 1000
	local rates = Economy.rates(p)
	local settled = Economy.settleOffline(p, 1000 + 10 * 24 * 3600, rates)
	assert(settled == Balance.production.maxOfflineAccrualSec, "offline cap")
	assert(p.lastSeen == 1000 + 10 * 24 * 3600)
	assert(sum(p.ingots) <= rates.capacity)
	local fresh = Economy.newProfile()
	assert(Economy.settleOffline(fresh, 5000, rates) == 0, "first join settles nothing")
end

tests["smelter prefers the selected material and keeps old ore"] = function()
	local p = Economy.newProfile()
	p.unlockedTier = 3
	p.selectedMaterial = 3
	p.ore[1] = 2
	p.ingots[1] = 0
	p.progress.smelt = 0.999
	Economy.settle(p, 1, Economy.rates(p))
	assert(p.ingots[1] == 1, "falls back to old ore when selected has none")
	assert(Economy.selectMaterial(p, 2), "select unlocked")
	assert(p.ore[1] == 1, "switching keeps mined ore")
end

tests["locked materials cannot be selected"] = function()
	local p = Economy.newProfile()
	local ok, err = Economy.selectMaterial(p, 2)
	assert(not ok and err == "MaterialLocked")
	ok, err = Economy.selectMaterial(p, 33)
	assert(not ok and err == "InvalidMaterial")
	ok, err = Economy.selectMaterial(p, 1.5)
	assert(not ok and err == "InvalidMaterial")
	ok, err = Economy.canForge(p, 2, 1)
	assert(not ok and err == "NoMaterial", "no ingots of a locked material")
end

tests["unlocking the next material costs its unlockCost"] = function()
	local p = Economy.newProfile()
	p.coins = Materials[2].unlockCost - 1
	local ok, err = Economy.unlockNextMaterial(p)
	assert(not ok and err == "NotEnoughCoins")
	p.coins += 1
	ok = Economy.unlockNextMaterial(p)
	assert(ok and p.unlockedTier == 2 and p.selectedMaterial == 2 and p.coins == 0)
	p.unlockedTier = 32
	ok, err = Economy.unlockNextMaterial(p)
	assert(not ok and err == "MaxTier")
end

tests["upgrades charge the curve and stop at max level"] = function()
	local p = Economy.newProfile()
	assert(Balance.upgradeCost("ExtractorOutput", 0) == 40)
	p.coins = 1e12
	for level = 0, Balance.tracks.ExtractorOutput.maxLevel - 1 do
		local cost = Balance.upgradeCost("ExtractorOutput", level) :: number
		local before = p.coins
		local ok, newLevel = Economy.buyUpgrade(p, "ExtractorOutput")
		assert(ok and newLevel == level + 1 and before - p.coins == cost, "level " .. level)
	end
	local ok, err = Economy.buyUpgrade(p, "ExtractorOutput")
	assert(not ok and err == "MaxLevel")
	near(Economy.rates(p).orePerSec, 4 / 6, 1e-9, "max extractor output = 4x")
	ok, err = Economy.buyUpgrade(p, "Nope")
	assert(not ok and err == "InvalidTrack")
	assert(Economy.buyUpgrade(p, "Hammer") and p.gear.Hammer == 1, "gear goes to gear")
	local broke = Economy.newProfile()
	ok, err = Economy.buyUpgrade(broke, "SmelterSpeed")
	assert(not ok and err == "NotEnoughCoins" and broke.levels.SmelterSpeed == 0)
end

tests["costs grow and stay inside safe integers"] = function()
	for name, def in Balance.tracks do
		local last = 0
		for level = 0, def.maxLevel - 1 do
			local cost = Balance.upgradeCost(name, level) :: number
			assert(cost > last and cost <= Balance.maxSafeInteger, name .. " level " .. level)
			last = cost
		end
		assert(Balance.upgradeCost(name, def.maxLevel) == nil, name .. " max")
	end
end

tests["forge timing: upgrades cut downtime, never the strike window"] = function()
	local p = Economy.newProfile()
	local base = Economy.forgeTiming(p, "manual")
	assert(base.heatSec == 2 and base.windowSec == 6 and base.revealSec == 1.5, "base timing")
	p.levels.FurnaceHeat = 15
	p.levels.AnvilFinish = 15
	p.gear.Hammer = 10
	local fast = Economy.forgeTiming(p, "manual", { extract = 0, smelt = 0, prep = 1, storage = 0 })
	near(fast.heatSec, 2 * 0.25 / 2, 1e-12, "heat floor with prep bonus")
	near(fast.revealSec, 1.5 * 0.25, 1e-12, "reveal floor")
	assert(fast.windowSec == 6, "window fixed")
end

tests["completeForge spends one ingot and records the weapon"] = function()
	local p = Economy.newProfile()
	local rng = Random.new(5)
	local ok, w = Economy.completeForge(p, 1, 2, 2.5, rng, 123)
	assert(ok, w)
	assert(p.ingots[1] == Economy.STARTER_INGOTS - 1, "ingot spent")
	assert(p.pending == w and w.id == "w1" and w.ts == 123 and w.c == 2 and w.m == 1)
	assert(p.weaponsForged == 1 and p.highestWeaponValue == w.v)
	assert(Economy.hasDiscovered(p, 1, w.r), "journal bit")
	local ok2, w2 = Economy.completeForge(p, 1, 2, 2.5, rng, 124)
	assert(ok2 and w2.id == "w2", "unique ids")
	assert(p.weapons.w1 == w, "previous pending auto-kept")
	assert(p.pending == w2)
end

tests["forging without material or room fails cleanly"] = function()
	local p = Economy.newProfile()
	p.ingots[1] = 0
	local ok, err = Economy.completeForge(p, 1, 1, 1, Random.new(1), 0)
	assert(not ok and err == "NoMaterial" and p.weaponsForged == 0)
	p.ingots[1] = 5
	for i = 1, Balance.inventory.maxWeapons - 1 do
		p.weapons["x" .. i] = { id = "x" .. i, m = 1, c = 1, q = 1, r = 1, d = "x", v = 1, ts = 0 }
	end
	p.pending = { id = "p", m = 1, c = 1, q = 1, r = 1, d = "x", v = 1, ts = 0 }
	ok, err = Economy.canForge(p, 1, 1)
	assert(not ok and err == "InventoryFull", "pending counts toward the cap")
	ok, err = Economy.canForge(p, 1, 9)
	assert(not ok and err == "InvalidClass")
end

tests["gloves can save the ingot but never add or go negative"] = function()
	local p = Economy.newProfile()
	p.gear.Gloves = Balance.tracks.Gloves.maxLevel
	p.ingots[1] = 1
	local rng = Random.new(11)
	local forged = 0
	while p.ingots[1] > 0 and forged < 1000 do
		local before = p.ingots[1]
		assert(Economy.completeForge(p, 1, 1, 1, rng, 0))
		assert(p.ingots[1] == before or p.ingots[1] == before - 1, "gloves changed ingots wrongly")
		forged += 1
		p.pending = nil
		p.weapons = {}
	end
	assert(p.ingots[1] == 0, "ingot eventually spent")
	local ok = Economy.completeForge(p, 1, 1, 1, rng, 0)
	assert(not ok, "no free forge at zero ingots")
end

tests["selling the pending weapon pays exactly once"] = function()
	local p = Economy.newProfile()
	local _, w = Economy.completeForge(p, 1, 1, 2.5, Random.new(3), 0)
	local ok, result = Economy.resolvePending(p, "sell")
	assert(ok and result.coins == w.v and p.coins == w.v and p.lifetimeCoins == w.v)
	local again, err = Economy.resolvePending(p, "sell")
	assert(not again and err == "NothingPending" and p.coins == w.v, "double sell")
	assert(p.weaponsSold == 1)
	local _, w2 = Economy.completeForge(p, 1, 1, 2.5, Random.new(4), 0)
	assert(Economy.resolvePending(p, "keep") and p.weapons[w2.id] == w2 and p.pending == nil)
	local bad, code = Economy.resolvePending(p, "explode")
	assert(not bad and code == "NothingPending")
end

tests["batch sell skips duplicates, unknown and showcased ids"] = function()
	local p = Economy.newProfile()
	p.weapons.a = { id = "a", m = 1, c = 1, q = 1, r = 1, d = "x", v = 10, ts = 0 }
	p.weapons.b = { id = "b", m = 1, c = 1, q = 1, r = 1, d = "x", v = 20, ts = 0 }
	p.weapons.c = { id = "c", m = 1, c = 1, q = 1, r = 1, d = "x", v = 40, ts = 0 }
	assert(Economy.toggleShowcase(p, "c"))
	local ok, result = Economy.sellWeapons(p, { "a", "a", "b", "zzz", "c", 5 })
	assert(ok and result.coins == 30 and #result.sold == 2, "sold " .. tostring(result.coins))
	assert(p.coins == 30 and p.weapons.c ~= nil)
	local again, err = Economy.sellWeapons(p, { "a", "b" })
	assert(not again and err == "NothingSold" and p.coins == 30)
	assert(not Economy.sellWeapons(p, {}), "empty batch")
	assert(not Economy.sellWeapons(p, "a"), "non-table")
end

tests["showcase toggles and respects slot count"] = function()
	local p = Economy.newProfile()
	for i = 1, Balance.inventory.showcaseSlots + 1 do
		p.weapons["s" .. i] = { id = "s" .. i, m = 1, c = 1, q = 1, r = 1, d = "x", v = 1, ts = 0 }
	end
	for i = 1, Balance.inventory.showcaseSlots do
		assert(Economy.toggleShowcase(p, "s" .. i))
	end
	local ok, err = Economy.toggleShowcase(p, "s" .. (Balance.inventory.showcaseSlots + 1))
	assert(not ok and err == "ShowcaseFull")
	assert(Economy.toggleShowcase(p, "s1") and #p.showcase == Balance.inventory.showcaseSlots - 1, "toggle off")
	ok, err = Economy.toggleShowcase(p, "nope")
	assert(not ok and err == "UnknownWeapon")
end

tests["coins clamp at the largest safe integer"] = function()
	local p = Economy.newProfile()
	p.coins = Balance.maxSafeInteger - 5
	p.pending = { id = "big", m = 32, c = 1, q = 5, r = 6, d = "x", v = Materials[32].priceMax, ts = 0 }
	assert(Economy.resolvePending(p, "sell"))
	assert(p.coins == Balance.maxSafeInteger, "clamped")
end

tests["a free player can afford early unlocks from forging copper"] = function()
	-- Simulates ~10 minutes of active manual play at 2.5x with no purchases.
	local p = Economy.newProfile()
	local rng = Random.new(77)
	local clock = 0
	local unlocks = 0
	while clock < 600 do
		local timing = Economy.forgeTiming(p, "manual")
		local cycle = timing.heatSec + timing.windowSec + timing.revealSec
		Economy.settle(p, cycle, Economy.rates(p))
		clock += cycle
		local ok = Economy.completeForge(p, p.selectedMaterial, 1, 2.5, rng, clock)
		if ok then
			Economy.resolvePending(p, "sell")
		end
		-- save for the next material; only buy production upgrades that are cheap relative to it
		if Economy.unlockNextMaterial(p) then
			unlocks += 1
		else
			local nextCost = Materials[p.unlockedTier + 1].unlockCost
			for _, track in { "SmelterSpeed", "ExtractorOutput" } do
				local cost = Balance.upgradeCost(track, p.levels[track])
				if cost and cost <= 0.2 * nextCost then
					Economy.buyUpgrade(p, track)
				end
			end
		end
	end
	assert(unlocks >= 2, "expected at least two material unlocks in 10 free minutes, got " .. unlocks)
end

return tests
