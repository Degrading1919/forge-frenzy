-- ForgeMath: luck, odds, rolls and valuation. Pure; runs in Studio and under Lune.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local Balance = require(Shared.Config.Balance)
local Materials = require(Shared.Config.Materials)

local function near(a: number, b: number, eps: number, label: string)
	assert(math.abs(a - b) <= eps, `{label}: expected {b}, got {a}`)
end

local tests = {}

tests["32 materials with valid, increasing bands"] = function()
	assert(#Materials == 32, "expected 32 materials")
	local ids = {}
	for i, m in Materials do
		assert(m.index == i, "index mismatch at " .. i)
		assert(not ids[m.id], "duplicate id " .. m.id)
		ids[m.id] = true
		assert(m.priceMin > 0 and m.priceMax > m.priceMin, "bad band " .. m.id)
		assert(m.era == math.ceil(i / 4), "era " .. m.id)
		if i > 1 then
			assert(m.priceMin > Materials[i - 1].priceMin, "min not increasing at " .. m.id)
			assert(m.unlockCost > Materials[i - 1].unlockCost, "unlock not increasing at " .. m.id)
		end
		assert(m.priceMax <= Balance.maxCoins, "value above the cash ceiling " .. m.id)
	end
	assert(Materials[1].unlockCost == 0, "copper must be free")
end

tests["manual luck follows 1 + 0.3 * cps, clamped 1..5"] = function()
	near(ForgeMath.luckFromStrikes(0, 6), 1, 1e-9, "0 cps")
	near(ForgeMath.luckFromStrikes(30, 6), 2.5, 1e-9, "5 cps")
	near(ForgeMath.luckFromStrikes(60, 6), 4, 1e-9, "10 cps")
	near(ForgeMath.luckFromStrikes(80, 6), 5, 1e-9, "13.3 cps")
	near(ForgeMath.luckFromStrikes(10000, 6), 5, 1e-9, "spam caps at 5")
	near(ForgeMath.luckFromStrikes(-5, 6), 1, 1e-9, "negative")
	near(ForgeMath.luckFromStrikes(0 / 0, 6), 1, 1e-9, "NaN")
	assert(ForgeMath.autoLuck("free") == 1.5)
	assert(ForgeMath.autoLuck("premium") == 4)
	assert(ForgeMath.autoLuck("manual") == nil)
end

tests["strike guard: only window strikes count, max 20 per second"] = function()
	local state = ForgeMath.newStrikeState(100, 6)
	assert(not ForgeMath.registerStrike(state, 99.9), "before window counted")
	assert(not ForgeMath.registerStrike(state, 106.5), "after window+grace counted")
	assert(ForgeMath.registerStrike(state, 106.2), "inside latency grace rejected")
	-- 1000 strikes inside the first second: only 20 count
	local fresh = ForgeMath.newStrikeState(0, 6)
	for _ = 1, 1000 do
		ForgeMath.registerStrike(fresh, 0.5)
	end
	assert(fresh.valid == 20, "rate guard let through " .. fresh.valid)
	-- flooding every bucket can never beat the 5x ceiling
	local flood = ForgeMath.newStrikeState(0, 6)
	for i = 0, 6400 do
		ForgeMath.registerStrike(flood, i / 1000)
	end
	assert(ForgeMath.strikeLuck(flood) <= 5, "luck above 5")
	near(ForgeMath.strikeLuck(flood), 5, 1e-9, "flood luck")
end

tests["rarity chances match the v0 table and sum to 1"] = function()
	local expected = {
		[1] = { 65.045, 23, 9, 2.5, 0.45, 0.005 },
		[1.5] = { 59.0675, 23, 13.5, 3.75, 0.675, 0.0075 },
		[2.5] = { 47.1125, 23, 22.5, 6.25, 1.125, 0.0125 },
		[4] = { 29.18, 23, 36, 10, 1.8, 0.02 },
		[5] = { 17.225, 23, 45, 12.5, 2.25, 0.025 },
	}
	for luck, row in expected do
		local chances = ForgeMath.rarityChances(luck)
		local sum = 0
		for i, pct in row do
			near(chances[i] * 100, pct, 1e-9, `luck {luck} rarity {i}`)
			assert(chances[i] >= 0, "negative chance")
			sum += chances[i]
		end
		near(sum, 1, 1e-12, "sum at " .. luck)
	end
	-- out-of-range luck is clamped, never negative
	local over = ForgeMath.rarityChances(50)
	near(over[1], ForgeMath.rarityChances(5)[1], 1e-12, "clamped above")
end

tests["every roll stays inside its material band"] = function()
	local rng = Random.new(1234)
	for m = 1, #Materials do
		local mat = Materials[m]
		for _ = 1, 400 do
			local luck = 1 + rng:NextNumber() * 4
			local class = rng:NextInteger(1, 5)
			local mult = ({ 1, 1.5, 3 })[rng:NextInteger(1, 3)]
			local classMult = Balance.weaponClasses[class].valueMult
			local w = ForgeMath.rollWeapon(rng, m, class, luck, { mult = mult })
			-- per-ingot band, scaled by the class recipe multiplier and the cash multiplier
			local lo = math.floor(mat.priceMin * classMult * mult + 0.5)
			local hi = math.floor(mat.priceMax * classMult * mult + 0.5)
			assert(w.v >= lo and w.v <= hi, `{mat.id} class {class} x{mult}: value {w.v} outside [{lo}, {hi}]`)
			assert(w.v == math.floor(w.v), "non-integer value")
			assert(w.v <= ForgeMath.maxValue(m, mult) + 1, "above maxValue")
		end
		-- extreme positions, per ingot and with a class multiplier
		assert(ForgeMath.valueFor(m, 6, 5, true, 0.01) <= mat.priceMax)
		assert(ForgeMath.valueFor(m, 1, 1, false, -0.01) >= mat.priceMin)
		assert(ForgeMath.valueFor(m, 6, 5, true, 0.01, 2) <= math.floor(mat.priceMax * 5 + 0.5))
	end
end

tests["same seed reproduces the same weapon"] = function()
	local a = ForgeMath.rollWeapon(Random.new(42), 14, 2, 3.3)
	local b = ForgeMath.rollWeapon(Random.new(42), 14, 2, 3.3)
	for _, key in { "m", "c", "q", "r", "d", "t", "v" } do
		assert(a[key] == b[key], "field " .. key .. " differs")
	end
end

tests["legendary and mythic use dedicated designs, others standard"] = function()
	for c, class in Balance.weaponClasses do
		assert(#class.designs == 3, class.id .. " needs 3 standard designs")
		for r = 1, 4 do
			assert(ForgeMath.designsFor(c, r) == class.designs)
		end
		assert(ForgeMath.designsFor(c, 5) == class.legendaryDesigns)
		assert(ForgeMath.designsFor(c, 6) == class.mythicDesigns)
	end
	local rng = Random.new(7)
	for _ = 1, 3000 do
		local w = ForgeMath.rollWeapon(rng, 1, 1, 5)
		local designs = ForgeMath.designsFor(1, w.r)
		assert(table.find(designs, w.d), "design not eligible for rarity")
	end
end

tests["seeded distribution matches odds at 2.5x luck"] = function()
	local rng = Random.new(2026)
	local n = 200000
	local counts = { 0, 0, 0, 0, 0, 0 }
	local qualities = { 0, 0, 0, 0, 0 }
	local traits = 0
	for _ = 1, n do
		local w = ForgeMath.rollWeapon(rng, 4, 1, 2.5)
		counts[w.r] += 1
		qualities[w.q] += 1
		if w.t then
			traits += 1
		end
	end
	local chances = ForgeMath.rarityChances(2.5)
	for r, p in chances do
		local sd = math.sqrt(n * p * (1 - p))
		assert(math.abs(counts[r] - n * p) <= 5 * sd + 1, `rarity {r}: {counts[r]} vs {n * p}`)
	end
	for q, p in ForgeMath.craftsmanshipChances() do
		local sd = math.sqrt(n * p * (1 - p))
		assert(math.abs(qualities[q] - n * p) <= 5 * sd, "quality " .. q)
	end
	local traitP = 0
	for r, p in chances do
		traitP += p * ForgeMath.traitChance(r)
	end
	local sd = math.sqrt(n * traitP * (1 - traitP))
	assert(math.abs(traits - n * traitP) <= 5 * sd, "trait rate")
	assert(counts[6] > 0, "mythic unreachable in 200k rolls at 2.5x (expected ~25)")
end

tests["expectedValue matches simulated mean"] = function()
	local rng = Random.new(99)
	for _, case in { { 1, 1 }, { 4, 2.5 }, { 20, 5 } } do
		local m, luck = case[1], case[2]
		local n, sum = 60000, 0
		for _ = 1, n do
			sum += ForgeMath.rollWeapon(rng, m, 3, luck, { mult = 1.5 }).v
		end
		local expected = ForgeMath.expectedValue(m, luck, 3, 1.5)
		near(sum / n / expected, 1, 0.02, `material {m} at {luck}x`)
	end
	assert(ForgeMath.expectedValue(5, 5) > ForgeMath.expectedValue(5, 2.5), "luck must raise expectation")
	assert(ForgeMath.expectedValue(5, 2.5) > ForgeMath.expectedValue(5, 1.5))
end

tests["luck never multiplies the price ceiling"] = function()
	for m = 1, #Materials do
		assert(ForgeMath.expectedValue(m, 5) < Materials[m].priceMax, "expectation above max")
	end
	-- a top Copper weapon is still worth less than a typical Iron weapon's ceiling
	assert(ForgeMath.valueFor(1, 6, 5, true, 0.01) < Materials[4].priceMax)
end

tests["odds table and joint outcome chances are consistent"] = function()
	local odds = ForgeMath.oddsTable(4)
	assert(odds.luck == 4)
	near(odds.rarity[3].chance, 0.36, 1e-12, "rare at 4x")
	-- joint chances over every outcome of a class sum to 1
	local sum = 0
	for r = 1, 6 do
		for q = 1, 5 do
			for _, design in ForgeMath.designsFor(2, r) do
				sum += ForgeMath.outcomeChance(4, 2, r, q, nil, design)
				for _, trait in Balance.forge.trait.names do
					sum += ForgeMath.outcomeChance(4, 2, r, q, trait, design)
				end
			end
		end
	end
	near(sum, 1, 1e-9, "joint total")
end

tests["names and coin formatting"] = function()
	local name = ForgeMath.weaponName({ id = "w1", m = 14, c = 1, q = 5, r = 5, d = "x", t = "Infernal", v = 1, ts = 0 })
	assert(name == "Perfect Infernal Mithril Sword", name)
	assert(ForgeMath.weaponName({ id = "w2", m = 1, c = 4, q = 2, r = 1, d = "x", v = 1, ts = 0 }) == "Copper Dagger")
	assert(ForgeMath.formatCoins(999) == "999")
	assert(ForgeMath.formatCoins(1234) == "1.23K", ForgeMath.formatCoins(1234))
	assert(ForgeMath.formatCoins(12516238278) == "12.5B", ForgeMath.formatCoins(12516238278))
	assert(ForgeMath.formatCoins(694999999) == "694M", ForgeMath.formatCoins(694999999))
end

tests["class value multiplier and cash multiplier scale the per-ingot band"] = function()
	for m = 1, #Materials do
		local base = ForgeMath.expectedValue(m, 1.5)
		for c, class in Balance.weaponClasses do
			near(ForgeMath.expectedValue(m, 1.5, c) / base, class.valueMult, 1e-9, "class mult " .. class.id)
			near(ForgeMath.expectedValue(m, 1.5, c, 2) / base, class.valueMult * 2, 1e-9, "cash mult")
			assert(ForgeMath.valueAt(m, 0.5, c) >= ForgeMath.valueAt(m, 0.5), "bigger class never worth less")
		end
		assert(ForgeMath.expectedValue(m, 1.5, nil, 0.1) == base, "a multiplier below 1 never cuts value")
	end
	-- Primordium's best weapon is far beyond double precision of old safe-integer clamps.
	assert(ForgeMath.maxValue(32) > 1e15 and ForgeMath.maxValue(32) <= Balance.maxCoins)
	assert(ForgeMath.maxValue(1, 2) == 2 * ForgeMath.maxValue(1))
	local biggest = 0
	for _, class in Balance.weaponClasses do biggest = math.max(biggest, class.valueMult) end
	near(ForgeMath.maxValue(5), Materials[5].priceMax * biggest, 1e-6, "maxValue is top of band x biggest class")
end

tests["bigger recipes pay more per forge but a little less per ingot"] = function()
	local order = Balance.classDisplayOrder
	assert(#order == #Balance.weaponClasses)
	local lastIngots, lastMult, lastPerIngot = 0, 0, math.huge
	for _, c in order do
		local class = Balance.weaponClasses[c]
		assert(class.ingots > lastIngots and class.valueMult > lastMult, "display order is smallest to largest")
		assert(class.valueMult / class.ingots <= lastPerIngot + 1e-9, "per-ingot value must not rise with size")
		lastIngots, lastMult, lastPerIngot = class.ingots, class.valueMult, class.valueMult / class.ingots
	end
end

return tests
