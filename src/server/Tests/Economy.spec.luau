-- Economy (schema v2): profile rules for ore lines, per-material bins, upgrades, recipes,
-- backpack, selling and showcases. Pad, display and station rules live in Workshop.spec.
-- Pure; runs in Studio and under Lune.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
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

local function weapon(id: string, v: number, r: number?, m: number?, c: number?): any
	return { id = id, m = m or 1, c = c or 1, q = 1, r = r or 1, d = "x", v = v, ts = 0 }
end

local tests = {}

tests["fresh profile is DataStore-safe, v2-shaped and playable"] = function()
	local p = Economy.newProfile()
	assert(p.schemaVersion == 2 and Economy.SCHEMA_VERSION == 2)
	assert(#p.ingots == 32 and #p.journal == 32, "per-material arrays must be dense")
	assert(p.ore == nil and p.progress == nil and p.pending == nil, "v1 fields are gone")
	assert(p.ingots[1] == Economy.STARTER_INGOTS and p.ingots[1] > 0, "starter ingots")
	assert(p.unlockedTier == 1 and p.selectedMaterial == 1)
	assert(#p.lines == 1 and p.lines[1].m == 1 and p.lines[1].ore == 0, "one starter ore line")
	assert(#p.stations == 1 and p.stations[1].c == Economy.STARTER_CLASS and p.stations[1].keep == 4, "one starter forge on a dagger")
	assert(#p.showcase == Balance.inventory.showcaseSlots and p.showcase[1] == "", "eight podium entries")
	assert(next(p.pads) == nil and p.bank == 0)
	assert(Economy.lineCount(p) == 1 and Economy.forgeCount(p) == 1 and Economy.showcaseSlots(p) == 2)
	-- the starter dagger needs one ingot, so the very first forge is possible at once
	assert(Economy.canForge(p, 1, p.stations[1].c), "first forge must be possible immediately")
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
		ingots = "bad",
		unlockedTier = 99,
		selectedMaterial = 50,
		levels = { ExtractorOutput = 999 },
		showcase = { "w1", "missing", "w1" },
		weapons = { w1 = weapon("w1", 12) },
		pets = { a = 1 },
	}
	Economy.reconcile(p)
	assert(p.coins == 0, "negative coins")
	assert(#p.ingots == 32, "ingots rebuilt")
	assert(p.unlockedTier == 32, "tier clamp")
	assert(#p.lines == 1 and p.lines[1].m == 1 and p.selectedMaterial == 1, "missing line is rebuilt on Copper; selectedMaterial mirrors line 1")
	assert(p.levels.ExtractorOutput == Balance.tracks.ExtractorOutput.maxLevel, "level clamp")
	assert(p.levels.SmelterSpeed == 0, "missing level filled")
	assert(#p.showcase == Balance.inventory.showcaseSlots, "showcase has one entry per podium")
	assert(p.showcase[1] == "w1" and p.showcase[2] == "" and p.showcase[3] == "", "duplicates and unknown ids removed in place")
	assert(p.pets.a == 1, "foreign field kept")
	assert(p.gear.Hammer == 0, "gear filled")
	assert(p.schemaVersion == 2)
end

tests["reconcile repairs partial progress, malformed tracks, lines and unsafe numbers"] = function()
	local p = Economy.newProfile()
	p.coins = math.huge
	p.lifetimeCoins = Balance.maxCoins * 2
	p.weaponsForged = 0 / 0
	p.ingots[2] = -3
	p.ingots[1] = math.huge
	p.levels = "broken" :: any
	p.gear = 10 :: any
	p.bank = -1
	p.lines = { { m = 0 / 0, ore = 99, po = 7, ps = -2 } }
	p.stations = { { m = "x", c = 99, keep = 50 } }
	Economy.reconcile(p)
	assert(p.coins == 0 and p.lifetimeCoins == Balance.maxCoins and p.weaponsForged == 0 and p.bank == 0)
	assert(p.ingots[2] == 0 and p.ingots[1] == 0)
	assert(p.levels.ExtractorOutput == 0 and p.gear.Hammer == 0)
	local line = p.lines[1]
	assert(line.m == 1 and line.ore == Balance.production.lineOreBuffer and line.po == 1 and line.ps == 0, "line clamped")
	local station = p.stations[1]
	assert(station.m == 1 and station.c == Economy.STARTER_CLASS and station.keep == 7, "station clamped")
	Economy.settle(p, 12, Economy.rates(p)) -- the restored pipeline must be executable
end

tests["reconcile folds a v1 pending weapon into the backpack and drops it"] = function()
	local p = Economy.newProfile()
	p.pending = weapon("w12", 201, 6)
	p.nextWeaponId = nil :: any
	Economy.reconcile(p)
	assert(p.pending == nil, "v2 has no pending weapon")
	assert(p.weapons.w12 ~= nil and p.weapons.w12.v == 201, "pending weapon kept, never lost")
	assert(p.nextWeaponId == 13, "serial recovered from ids")
end

tests["weapon serials never overwrite owned items"] = function()
	local p = Economy.newProfile()
	local retained = weapon("w8", 200, 6)
	p.weapons.w8, p.nextWeaponId = retained, nil :: any
	Economy.reconcile(p)
	assert(p.nextWeaponId == 9 and p.weapons.w8 == retained)
	local rng = Random.new(5)
	local ok, result = Economy.completeForge(p, 1, 4, 1.5, rng, 0, { keepFrom = 1 })
	assert(ok and result.weapon.id == "w9" and p.weapons.w8 == retained)
	p.nextWeaponId = 8 -- runtime defense also catches a damaged counter after load
	local ok2, result2 = Economy.completeForge(p, 1, 4, 1.5, rng, 0, { keepFrom = 1 })
	assert(ok2 and result2.weapon.id ~= "w8" and result2.weapon.id ~= "w9" and p.weapons.w8 == retained)
end

tests["base rates are per line with a per-material bin capacity"] = function()
	local p = Economy.newProfile()
	local r = Economy.rates(p)
	near(r.orePerSec, 1 / 3, 1e-12, "ore")
	near(r.ingotPerSec, 1 / 3, 1e-12, "ingot")
	assert(r.capacity == 25 and r.oreBuffer == 8 and r.lines == 1, "capacity / buffer / lines")
	p.levels.StorageCapacity = 3
	p.gear.Apron = 2
	assert(Economy.rates(p).capacity == 25 + 30 + 50, "vault levels and apron add flat capacity")
	assert(Economy.rates(p, { extract = 0, smelt = 0, prep = 0, storage = 1 }).capacity == (25 + 30 + 50) * 2, "storage bonus multiplies")
	p.pads.line_2 = true
	p.unlockedTier = 4
	Economy.reconcile(p)
	assert(Economy.rates(p).lines == 2, "ore lines count from pads")
end

tests["bonus families are additive and capped at 3x"] = function()
	local b = Economy.combineBonuses({ { extract = 0.5 }, { extract = 0.4, smelt = 0.2 }, nil :: any, { prep = 0 / 0 } })
	near(b.extract, 0.9, 1e-12, "extract sum")
	near(b.smelt, 0.2, 1e-12, "smelt")
	assert(b.prep == 0, "NaN ignored")
	assert(Economy.familyMultiplier(10) == 3, "cap")
	assert(Economy.familyMultiplier(-1) == 1, "floor")
	local p = Economy.newProfile()
	near(Economy.rates(p, { extract = 5, smelt = 0, prep = 0, storage = 0 }).orePerSec, 3 / 3, 1e-12, "capped extract")
end

tests["settle produces at the right rate and never past caps"] = function()
	local p = Economy.newProfile()
	p.ingots[1] = 0
	local rates = Economy.rates(p)
	local ore, ingots = Economy.settle(p, 60, rates)
	assert(ore == 20, "60s at 3s/ore = 20 ore, got " .. ore)
	assert(ingots >= 18 and ingots <= 20, "smelter keeps pace with the drill, got " .. ingots)
	assert(p.ingots[1] == ingots and p.lines[1].ore == ore - ingots, "stock bookkeeping")
	-- an hour fills the bin and the conveyor and stalls; nothing above caps
	Economy.settle(p, 3600, rates)
	assert(p.ingots[1] == rates.capacity, "bin cap " .. p.ingots[1])
	assert(p.lines[1].ore == rates.oreBuffer, "ore buffer cap " .. p.lines[1].ore)
	local before = p.ingots[1] + p.lines[1].ore
	Economy.settle(p, 3600, rates)
	assert(p.ingots[1] + p.lines[1].ore == before, "stalled pipeline must not grow")
	assert(p.lines[1].po <= 1 and p.lines[1].ps <= 1, "no banked progress")
end

tests["each material has its own bin: an old full bin never blocks a new line"] = function()
	local p = Economy.newProfile()
	p.unlockedTier = 2
	p.ingots[1] = 25 -- Copper bin completely full
	local rates = Economy.rates(p)
	-- Line mining Copper stalls at once...
	Economy.settle(p, 120, rates)
	assert(p.ingots[1] == 25, "full Copper bin must not overflow")
	-- ...but pointing the line at Tin produces Tin without touching Copper
	assert(Economy.setLineMaterial(p, 1, 2))
	Economy.settle(p, 120, rates)
	assert(p.ingots[2] > 0, "Tin line was blocked by a full Copper bin")
	assert(p.ingots[1] == 25)
	-- Capacity applies per material
	Economy.settle(p, 7200, rates)
	assert(p.ingots[2] == rates.capacity and p.ingots[1] == 25, "each bin fills to its own capacity")
	assert(sum(p.ingots) == 25 + rates.capacity)
end

tests["each ore line mines its own material"] = function()
	local p = Economy.newProfile()
	p.unlockedTier = 6
	p.pads.line_2 = true
	p.pads.line_3 = true
	Economy.reconcile(p)
	assert(#p.lines == 3)
	assert(Economy.setLineMaterial(p, 1, 1) and Economy.setLineMaterial(p, 2, 3) and Economy.setLineMaterial(p, 3, 6))
	for i = 1, #p.ingots do
		p.ingots[i] = 0
	end
	Economy.settle(p, 60, Economy.rates(p))
	assert(p.ingots[1] > 0 and p.ingots[3] > 0 and p.ingots[6] > 0, "every line produced its own material")
	assert(p.ingots[2] == 0 and p.ingots[4] == 0 and p.ingots[5] == 0, "nothing for unmined materials")
	assert(p.ingots[1] == p.ingots[3] and p.ingots[3] == p.ingots[6], "identical lines produce identically")
	-- two lines on one material share its single bin
	assert(Economy.setLineMaterial(p, 2, 6))
	for i = 1, #p.ingots do
		p.ingots[i] = 0
	end
	local before6 = p.ingots[6]
	Economy.settle(p, 60, Economy.rates(p))
	assert(p.ingots[6] > before6 and p.ingots[6] <= Economy.rates(p).capacity)
	assert(p.ingots[3] == 0, "line 2 no longer mines Bronze")
end

tests["settle in one call or many ticks gives the same totals"] = function()
	local a, b = Economy.newProfile(), Economy.newProfile()
	local rates = Economy.rates(a)
	Economy.settle(a, 120, rates)
	for _ = 1, 120 do
		Economy.settle(b, 1, rates)
	end
	assert(sum(a.ingots) == sum(b.ingots) and a.lines[1].ore == b.lines[1].ore, "tick-size dependence")
end

tests["offline settlement is capped"] = function()
	local p = Economy.newProfile()
	p.lastSeen = 1000
	local rates = Economy.rates(p)
	local settled = Economy.settleOffline(p, 1000 + 10 * 24 * 3600, rates)
	assert(settled == Balance.production.maxOfflineAccrualSec, "offline cap")
	assert(p.lastSeen == 1000 + 10 * 24 * 3600)
	assert(p.ingots[1] <= rates.capacity)
	local fresh = Economy.newProfile()
	assert(Economy.settleOffline(fresh, 5000, rates) == 0, "first join settles nothing")
end

tests["line material selection validates and mirrors line 1"] = function()
	local p = Economy.newProfile()
	local ok, err = Economy.setLineMaterial(p, 1, 2)
	assert(not ok and err == "MaterialLocked")
	ok, err = Economy.setLineMaterial(p, 1, 33)
	assert(not ok and err == "InvalidMaterial")
	ok, err = Economy.setLineMaterial(p, 1, 1.5)
	assert(not ok and err == "InvalidMaterial")
	ok, err = Economy.setLineMaterial(p, 2, 1)
	assert(not ok and err == "InvalidLine", "line 2 is not built")
	ok, err = Economy.setLineMaterial(p, "1" :: any, 1)
	assert(not ok and err == "InvalidLine")
	ok, err = Economy.canForge(p, 2, 1)
	assert(not ok and err == "MaterialLocked", "locked material rejected even if stored ingots exist")
	p.unlockedTier = 3
	assert(Economy.setLineMaterial(p, 1, 3) and p.selectedMaterial == 3)
	assert(Economy.selectMaterial(p, 2) and p.lines[1].m == 2 and p.selectedMaterial == 2, "legacy selectMaterial drives line 1")
end

tests["unlockMaterial is sequential, charged and switches the buying line"] = function()
	local p = Economy.newProfile()
	assert(Materials[1].unlockCost == 0)
	p.coins = Materials[2].unlockCost - 1
	local ok, err = Economy.unlockMaterial(p, 2)
	assert(not ok and err == "NotEnoughCoins" and p.unlockedTier == 1)
	p.coins += 1
	ok = Economy.unlockMaterial(p, 2)
	assert(ok and p.unlockedTier == 2 and p.selectedMaterial == 2 and p.lines[1].m == 2 and p.coins == 0)
	p.coins = 1e30
	ok, err = Economy.unlockMaterial(p, 2)
	assert(not ok and err == "AlreadyUnlocked")
	ok, err = Economy.unlockMaterial(p, 5)
	assert(not ok and err == "UnlockPrevious", "no skipping tiers")
	ok, err = Economy.unlockMaterial(p, 0)
	assert(not ok and err == "InvalidMaterial")
	ok, err = Economy.unlockMaterial(p, 3.5)
	assert(not ok and err == "InvalidMaterial")
	-- the purchase can switch a chosen line
	p.pads.line_2 = true
	p.unlockedTier = 4
	Economy.reconcile(p)
	p.coins = Materials[5].unlockCost
	assert(Economy.unlockMaterial(p, 5, 2))
	assert(p.lines[2].m == 5 and p.lines[1].m ~= 5, "second line switched")
	assert(p.coins == 0, "exactly the unlock cost was charged")
	-- unlockNextMaterial at the top tier
	p.unlockedTier = 32
	ok, err = Economy.unlockNextMaterial(p)
	assert(not ok and err == "InvalidMaterial", "past the last material")
end

tests["upgrades charge the curve and stop at max level"] = function()
	local p = Economy.newProfile()
	assert(Balance.upgradeCost("ExtractorOutput", 0) == 150)
	assert(Balance.upgradeCost("ExtractorOutput", Balance.tracks.ExtractorOutput.maxLevel) == nil)
	for level = 0, Balance.tracks.ExtractorOutput.maxLevel - 1 do
		local cost = Balance.upgradeCost("ExtractorOutput", level) :: number
		if cost < 2 ^ 50 then -- below this a double can tell cost - 1 from cost
			p.coins = cost - 1
			local short, shortErr = Economy.buyUpgrade(p, "ExtractorOutput")
			assert(not short and shortErr == "NotEnoughCoins" and p.levels.ExtractorOutput == level, "one short at level " .. level)
		end
		p.coins = cost
		local ok, newLevel = Economy.buyUpgrade(p, "ExtractorOutput")
		assert(ok and newLevel == level + 1 and p.coins == 0, "level " .. level)
	end
	p.coins = 1e30
	local ok, err = Economy.buyUpgrade(p, "ExtractorOutput")
	assert(not ok and err == "MaxLevel")
	near(Economy.rates(p).orePerSec, (1 + 0.15 * 100) / 3, 1e-9, "max ore drill = 16x")
	ok, err = Economy.buyUpgrade(p, "Nope")
	assert(not ok and err == "InvalidTrack")
	assert(Economy.buyUpgrade(p, "Hammer") and p.gear.Hammer == 1, "gear goes to gear")
	local broke = Economy.newProfile()
	ok, err = Economy.buyUpgrade(broke, "SmelterSpeed")
	assert(not ok and err == "NotEnoughCoins" and broke.levels.SmelterSpeed == 0)
end

tests["every track states what and where it upgrades"] = function()
	for name, def in Balance.tracks do
		assert(type(def.label) == "string" and #def.label > 0, name .. " label")
		assert(table.find({ "pct", "flat", "sec", "chance" }, def.unit), name .. " unit")
		assert(table.find({ "Ore", "Storage", "Forge", "Tools" }, def.station), name .. " station")
		assert(def.kind == "machine" or def.kind == "gear")
	end
	for _, name in Balance.gearTracks do
		assert(Balance.tracks[name].kind == "gear" and Balance.tracks[name].station == "Tools")
	end
end

tests["costs grow and stay under the cash ceiling"] = function()
	for name, def in Balance.tracks do
		local last = 0
		for level = 0, def.maxLevel - 1 do
			local cost = Balance.upgradeCost(name, level) :: number
			assert(cost > last and cost <= Balance.maxCoins and cost == cost and cost < math.huge, name .. " level " .. level)
			last = cost
		end
		assert(Balance.upgradeCost(name, def.maxLevel) == nil, name .. " max")
	end
end

tests["forge timing: upgrades cut downtime, never the strike window"] = function()
	local p = Economy.newProfile()
	local base = Economy.forgeTiming(p, "manual")
	assert(base.heatSec == 2 and base.windowSec == 6 and base.revealSec == 1.5, "base timing")
	assert(Economy.forgeTiming(p, "free").windowSec == Balance.forge.auto.windowSec, "auto window")
	p.levels.FurnaceHeat = 15
	p.levels.AnvilFinish = 15
	p.gear.Hammer = 10
	local fast = Economy.forgeTiming(p, "manual", { extract = 0, smelt = 0, prep = 1, storage = 0 })
	near(fast.heatSec, Balance.forge.timing.minPhaseSec / 2, 1e-12, "heat floor with prep bonus")
	near(fast.revealSec, Balance.forge.timing.minPhaseSec, 1e-12, "reveal floor")
	assert(fast.windowSec == 6, "window fixed")
end

tests["recipes consume ingots by weapon size"] = function()
	local expected = { Sword = 2, Greatsword = 5, Axe = 3, Dagger = 1, Hammer = 4 }
	for c, class in Balance.weaponClasses do
		assert(class.ingots == expected[class.id], class.id .. " recipe")
		assert(Balance.recipeIngots(c) == class.ingots)
		local p = Economy.newProfile()
		p.ingots[1] = class.ingots
		local ok, result = Economy.completeForge(p, 1, c, 1.5, Random.new(c), 100, { keepFrom = 1 })
		assert(ok, result)
		assert(p.ingots[1] == 0 or result.refund, class.id .. " spent exactly its recipe")
		-- one ingot short fails and spends nothing
		local short = Economy.newProfile()
		short.ingots[1] = class.ingots - 1
		local ok2, err = Economy.completeForge(short, 1, c, 1.5, Random.new(c), 100)
		assert(not ok2 and err == "NoMaterial" and short.ingots[1] == class.ingots - 1 and short.weaponsForged == 0, class.id .. " short")
	end
	assert(Balance.recipeIngots(99) == 1, "unknown class defaults to one ingot")
end

tests["completeForge keeps the weapon in the backpack, spends the recipe, records it"] = function()
	local p = Economy.newProfile()
	local rng = Random.new(5)
	local ok, result = Economy.completeForge(p, 1, 2, 2.5, rng, 123) -- Greatsword: 5 ingots
	assert(ok, result)
	local w = result.weapon
	assert(result.sold == false and result.coins == 0)
	assert(p.pending == nil, "no pending weapon in v2")
	assert(p.weapons[w.id] == w and w.id == "w1" and w.ts == 123 and w.c == 2 and w.m == 1)
	assert(p.ingots[1] == Economy.STARTER_INGOTS - 5 or result.refund, "recipe ingots spent")
	assert(p.weaponsForged == 1 and p.highestWeaponValue == w.v)
	assert(Economy.hasDiscovered(p, 1, w.r), "journal bit")
	p.ingots[1] = 10
	local ok2, result2 = Economy.completeForge(p, 1, 4, 2.5, rng, 124)
	assert(ok2 and result2.weapon.id == "w2", "unique ids")
	assert(p.weapons.w1 == w, "earlier weapons stay")
	assert(Economy.weaponCount(p) == 2)
end

tests["forged values stay in the per-ingot band times class and cash multipliers"] = function()
	local rng = Random.new(77)
	for m = 1, 32 do
		for c = 1, 5 do
			local p = Economy.newProfile()
			p.unlockedTier = m
			p.ingots[m] = 50
			local mult = if m % 2 == 0 then 1 else 2.5
			local ok, result = Economy.completeForge(p, m, c, 1 + rng:NextNumber() * 4, rng, 0, { mult = mult, keepFrom = 1 })
			assert(ok)
			local v = result.weapon.v
			local classMult = Balance.weaponClasses[c].valueMult
			assert(v >= math.floor(Materials[m].priceMin * classMult * mult + 0.5), `material {m} class {c} below band`)
			assert(v <= math.floor(Materials[m].priceMax * classMult * mult + 0.5), `material {m} class {c} above band`)
		end
	end
end

tests["forging without material or room fails cleanly"] = function()
	local p = Economy.newProfile()
	p.ingots[1] = 0
	local ok, err = Economy.completeForge(p, 1, 4, 1, Random.new(1), 0)
	assert(not ok and err == "NoMaterial" and p.weaponsForged == 0)
	p.ingots[1] = 50
	for i = 1, Balance.inventory.maxWeapons do
		p.weapons["x" .. i] = weapon("x" .. i, 1)
	end
	ok, err = Economy.canForge(p, 1, 4)
	assert(not ok and err == "InventoryFull")
	assert(Economy.canForge(p, 1, 4, true), "automatic forges may continue with a full backpack")
	ok, err = Economy.canForge(p, 1, 9)
	assert(not ok and err == "InvalidClass")
	ok, err = Economy.canForge(p, 40, 1)
	assert(not ok and err == "InvalidMaterial")
	ok, err = Economy.completeForge(p, 1, 4, 1, Random.new(1), 0)
	assert(not ok and err == "InventoryFull" and p.ingots[1] == 50 and p.weaponsForged == 0, "manual forge refuses on a full backpack and spends nothing")
end

tests["a full backpack sells automatic results instead of losing or stopping them"] = function()
	local p = Economy.newProfile()
	p.ingots[1] = 50
	for i = 1, Balance.inventory.maxWeapons do
		p.weapons["x" .. i] = weapon("x" .. i, 1)
	end
	local ok, result = Economy.completeForge(p, 1, 4, 1.5, Random.new(1), 0, { allowFullBackpack = true, keepFrom = 1 })
	assert(ok and result.sold and result.coins == result.weapon.v)
	assert(p.coins == result.weapon.v and p.lifetimeCoins == result.weapon.v and p.weaponsSold == 1)
	assert(Economy.weaponCount(p) == Balance.inventory.maxWeapons, "backpack never exceeds its cap")
	assert(p.weapons[result.weapon.id] == nil)
end

tests["keepFrom sells low rarities at once and keeps the rest"] = function()
	local p = Economy.newProfile()
	p.ingots[1] = 500
	local rng = Random.new(2024)
	local kept, sold = 0, 0
	for _ = 1, 200 do
		local ok, result = Economy.completeForge(p, 1, 4, 2.5, rng, 0, { keepFrom = 3, allowFullBackpack = true })
		assert(ok)
		if result.sold then
			sold += 1
			assert(result.weapon.r < 3, "sold a weapon at or above the keep rarity")
		else
			kept += 1
			assert(result.weapon.r >= 3 and p.weapons[result.weapon.id])
		end
	end
	assert(kept > 0 and sold > 0, "both outcomes expected over 200 forges")
	assert(p.weaponsSold == sold and Economy.weaponCount(p) == kept)
	local everything = Economy.newProfile()
	for _ = 1, 20 do
		local ok, result = Economy.completeForge(everything, 1, 4, 1, rng, 0, { keepFrom = 7, allowFullBackpack = true })
		if not ok then break end
		assert(result.sold, "keep rule 7 sells everything")
	end
end

tests["completeForgeBatch returns results and an extra roll needs its own ingots"] = function()
	local p = Economy.newProfile()
	p.ingots[1] = 10
	local ok, batch = Economy.completeForgeBatch(p, 1, 4, 1.5, Random.new(8), 0, 2, { keepFrom = 1 })
	assert(ok and #batch.results == 2 and batch.results[1].weapon.id ~= batch.results[2].weapon.id)
	assert(p.weaponsForged == 2 and p.ingots[1] >= 8 and p.ingots[1] <= 10)
	-- two-ingot recipe with a single ingot left: only the first roll happens
	local q = Economy.newProfile()
	q.ingots[1] = 3
	local ok2, batch2 = Economy.completeForgeBatch(q, 1, 1, 1.5, Random.new(9), 0, 2, { keepFrom = 1 }) -- Sword, 2 ingots each
	assert(ok2 and #batch2.results == 1 and q.weaponsForged == 1)
	-- invalid roll counts
	for _, rolls in { 0, 3, 1.5, -1 } do
		local bad, err = Economy.completeForgeBatch(q, 1, 1, 1.5, Random.new(1), 0, rolls)
		assert(not bad and err == "InvalidRequest")
	end
	-- no ingots at all
	local empty = Economy.newProfile()
	empty.ingots[1] = 0
	local bad, err = Economy.completeForgeBatch(empty, 1, 1, 1.5, Random.new(1), 0, 1)
	assert(not bad and err == "NoMaterial")
end

tests["gloves can save the ingots but never add or go negative"] = function()
	local p = Economy.newProfile()
	p.gear.Gloves = Balance.tracks.Gloves.maxLevel
	p.ingots[1] = 200
	local rng = Random.new(11)
	local forged, refunds = 0, 0
	while p.ingots[1] >= 1 and forged < 2000 do
		local before = p.ingots[1]
		local ok, result = Economy.completeForge(p, 1, 4, 1, rng, 0, { keepFrom = 7, allowFullBackpack = true })
		assert(ok)
		assert(p.ingots[1] == before or p.ingots[1] == before - 1, "gloves changed ingots wrongly")
		assert((p.ingots[1] == before) == result.refund)
		if result.refund then refunds += 1 end
		forged += 1
	end
	assert(p.ingots[1] == 0, "ingots eventually spent")
	assert(refunds > 0, "gloves never refunded in a long run")
	local ok = Economy.completeForge(p, 1, 4, 1, rng, 0)
	assert(not ok, "no free forge at zero ingots")
end

tests["batch sell skips duplicates, unknown, displayed and protected ids"] = function()
	local p = Economy.newProfile()
	p.weapons.a = weapon("a", 10)
	p.weapons.b = weapon("b", 20)
	p.weapons.c = weapon("c", 40)
	p.weapons.d = weapon("d", 80)
	assert(Economy.toggleShowcase(p, "c"))
	local ok, result = Economy.sellWeapons(p, { "a", "a", "b", "zzz", "c", 5, "d" }, { d = true })
	assert(ok and result.coins == 30 and #result.sold == 2, "sold " .. tostring(result.coins))
	assert(p.coins == 30 and p.lifetimeCoins == 30 and p.weapons.c ~= nil and p.weapons.d ~= nil and p.weaponsSold == 2)
	local again, err = Economy.sellWeapons(p, { "a", "b" })
	assert(not again and err == "NothingSold" and p.coins == 30)
	assert(not Economy.sellWeapons(p, {}), "empty batch")
	assert(not Economy.sellWeapons(p, "a"), "non-table")
	local huge = {}
	for i = 1, Balance.inventory.maxSellBatch + 1 do huge[i] = "w" .. i end
	local tooMany, why = Economy.sellWeapons(p, huge)
	assert(not tooMany and why == "InvalidRequest", "oversized batch")
end

tests["sellAll keeps displayed and protected ids and honours the rarity threshold"] = function()
	local p = Economy.newProfile()
	p.weapons.a = weapon("a", 10, 1)
	p.weapons.b = weapon("b", 20, 2)
	p.weapons.c = weapon("c", 40, 3)
	p.weapons.d = weapon("d", 80, 4)
	p.weapons.e = weapon("e", 160, 6)
	assert(Economy.setShowcase(p, 1, "a"), "displayed")
	-- sellableIds is sorted and excludes displayed weapons
	local ids = Economy.sellableIds(p)
	assert(table.concat(ids, ",") == "b,c,d,e", table.concat(ids, ","))
	assert(table.concat(Economy.sellableIds(p, 3), ",") == "b", "below rarity 3 only")
	-- sell everything below Rare, but protect a weapon that is being carried off
	local ok, result = Economy.sellAll(p, 3, { b = true })
	assert(not ok and result == "NothingSold", "the only candidate was protected")
	ok, result = Economy.sellAll(p, 4, { c = true })
	assert(ok and result.coins == 20 and #result.sold == 1 and p.weapons.b == nil and p.weapons.c ~= nil)
	ok, result = Economy.sellAll(p, nil, { e = true })
	assert(ok and result.coins == 40 + 80, "nil threshold sells every unprotected, undisplayed weapon")
	assert(p.weapons.a ~= nil and p.weapons.e ~= nil, "displayed and protected stay")
	assert(p.coins == 20 + 120)
	local none = Economy.sellAll(p, nil, { e = true })
	assert(not none)
	-- out-of-range threshold means "sell all"
	p.weapons.z = weapon("z", 5, 6)
	assert(Economy.sellAll(p, 99, { e = true }) and p.weapons.z == nil)
end

tests["showcase respects built podiums and moves weapons between slots"] = function()
	local p = Economy.newProfile()
	for i = 1, 10 do
		p.weapons["s" .. i] = weapon("s" .. i, 1)
	end
	assert(Economy.showcaseSlots(p) == 2)
	assert(Economy.toggleShowcase(p, "s1") and p.showcase[1] == "s1")
	assert(Economy.toggleShowcase(p, "s2") and p.showcase[2] == "s2")
	local ok, err = Economy.toggleShowcase(p, "s3")
	assert(not ok and err == "ShowcaseFull", "only two podiums are built")
	ok, err = Economy.setShowcase(p, 3, "s3")
	assert(not ok and err == "SlotLocked", "podium 3 is not built yet")
	ok, err = Economy.setShowcase(p, 9, "s3")
	assert(not ok and err == "InvalidSlot")
	ok, err = Economy.setShowcase(p, 0, "s3")
	assert(not ok and err == "InvalidSlot")
	ok, err = Economy.setShowcase(p, 1.5, "s3")
	assert(not ok and err == "InvalidSlot")
	assert(Economy.toggleShowcase(p, "s1") and p.showcase[1] == "", "toggle off frees the slot")
	p.pads.podiums_1 = true
	assert(Economy.showcaseSlots(p) == 4)
	assert(Economy.setShowcase(p, 4, "s3") and p.showcase[4] == "s3")
	assert(Economy.setShowcase(p, 3, "s3") and p.showcase[3] == "s3" and p.showcase[4] == "", "moving keeps one podium per weapon")
	assert(Economy.setShowcase(p, 3, nil) and p.showcase[3] == "", "clear slot")
	ok, err = Economy.setShowcase(p, 1, "nope")
	assert(not ok and err == "UnknownWeapon")
	ok, err = Economy.toggleShowcase(p, "nope")
	assert(not ok and err == "UnknownWeapon")
	-- locked podiums lose their weapon when a profile is repaired
	local q = Economy.newProfile()
	q.weapons.k = weapon("k", 1)
	q.showcase[5] = "k"
	Economy.reconcile(q)
	assert(q.showcase[5] == "" and q.weapons.k ~= nil, "weapon stays in the backpack, podium cleared")
end

tests["cash is clamped at the ceiling, never inf or NaN"] = function()
	local p = Economy.newProfile()
	p.coins = Balance.maxCoins - 5
	p.weapons.big = weapon("big", Materials[32].priceMax * 5, 6, 32)
	assert(Balance.maxCoins == 1e30)
	local ok = Economy.sellWeapons(p, { "big" })
	assert(ok and p.coins == Balance.maxCoins and p.lifetimeCoins <= Balance.maxCoins)
	p.coins = 0 / 0
	Economy.reconcile(p)
	assert(p.coins == 0)
	p.coins = 1e40
	Economy.reconcile(p)
	assert(p.coins == Balance.maxCoins, "oversized saves are clamped to the ceiling")
	-- Primordium values (1e15+) are ordinary doubles far below the ceiling
	assert(ForgeMath.maxValue(32) > 1e15 and ForgeMath.maxValue(32) < Balance.maxCoins)
end

tests["a free player can afford early unlocks from automatic daggers"] = function()
	-- Ten minutes of unattended Auto Forge: sell everything, buy the next material, point the
	-- line and the forge at it. No upgrades are bought.
	local p = Economy.newProfile()
	local rng = Random.new(77)
	local clock, unlocks = 0, 0
	while clock < 600 do
		local timing = Economy.forgeTiming(p, "free")
		local cycle = timing.heatSec + timing.windowSec + timing.revealSec
		Economy.settle(p, cycle, Economy.rates(p))
		clock += cycle
		local station = p.stations[1]
		local ok = Economy.completeForge(p, station.m, station.c, ForgeMath.autoLuck("free") :: number, rng, clock, { keepFrom = 7, allowFullBackpack = true })
		if not ok then
			continue
		end
		if Economy.unlockNextMaterial(p) then
			unlocks += 1
			Economy.configureStation(p, 1, p.unlockedTier, station.c, station.keep)
		end
	end
	assert(unlocks >= 2, "expected at least two material unlocks in 10 free minutes, got " .. unlocks)
end

return tests
