--!strict
--[[
	ForgeMath — pure forging math: click luck, odds, weapon rolls and valuation.

	Deterministic given a Random-like `rng` (anything with :NextNumber() returning [0, 1)).
	Only the server rolls; clients may call the odds/expectation helpers for disclosure UI.

	Rules implemented (docs/02, docs/13, PROPOSED v0 numbers in Config/Balance):
	  * Luck only reshapes the rarity distribution. It never multiplies the sale price.
	  * Rare..Mythic chances scale linearly with luck, Uncommon is fixed, Common takes the rest.
	  * Craftsmanship odds ignore luck. Trait chance depends on rarity.
	  * Value = material band min + position * (max - min), position clamped to [0.01, 0.99],
	    so every weapon's value stays inside its material's [priceMin, priceMax].
]]

local Config = script.Parent.Config
local Balance = require(Config.Balance)
local Materials = require(Config.Materials)

local ForgeMath = {}

export type Weapon = {
	id: string,
	m: number, -- material index 1..32
	c: number, -- class index 1..5
	q: number, -- craftsmanship 1..5
	r: number, -- rarity 1..6
	d: string, -- design id
	t: string?, -- trait name, nil when none
	v: number, -- sale value, integer inside the material band
	ts: number, -- creation time (os.time)
}

-- Roblox `Random`, or any object with :NextNumber() -> [0, 1).
export type Rng = any

local forge = Balance.forge
local RARITY_COUNT = #forge.rarity.names
local QUALITY_COUNT = #forge.craftsmanship.names

ForgeMath.RARITY = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }
ForgeMath.MIN_LUCK = 1
ForgeMath.MAX_LUCK = forge.manual.maxLuck

local function clampLuck(luck: number): number
	if luck ~= luck then -- NaN
		return ForgeMath.MIN_LUCK
	end
	return math.clamp(luck, ForgeMath.MIN_LUCK, ForgeMath.MAX_LUCK)
end
ForgeMath.clampLuck = clampLuck

-- Manual luck: clamp(1 + 0.30 * validStrikes / windowSec, 1, 5).
function ForgeMath.luckFromStrikes(validStrikes: number, windowSec: number?): number
	local window = windowSec or forge.manual.strikeWindowSec
	if window <= 0 or validStrikes ~= validStrikes then
		return ForgeMath.MIN_LUCK
	end
	local cps = math.max(0, validStrikes) / window
	return clampLuck(forge.manual.baseLuck + forge.manual.luckPerCps * cps)
end

-- Fixed luck for automatic modes: "free" -> 1.5, "premium" -> 4.
function ForgeMath.autoLuck(mode: string): number?
	if mode == "free" then
		return forge.auto.freeLuck
	elseif mode == "premium" then
		return forge.auto.premiumLuck
	end
	return nil
end

--[[
	Server-side strike validation for one manual session. Strikes count only inside
	[windowStart, windowEnd + grace], and at most `inputRateGuardCps` per one-second bucket, so
	replayed or spammed events cannot push luck past what a real 6-second window allows.
]]
export type StrikeState = {
	windowStart: number,
	windowEnd: number,
	valid: number,
	buckets: { [number]: number },
}

function ForgeMath.newStrikeState(windowStart: number, windowSec: number?): StrikeState
	return {
		windowStart = windowStart,
		windowEnd = windowStart + (windowSec or forge.manual.strikeWindowSec),
		valid = 0,
		buckets = {},
	}
end

function ForgeMath.registerStrike(state: StrikeState, now: number): boolean
	if now < state.windowStart or now > state.windowEnd + forge.manual.latencyGraceSec then
		return false
	end
	local bucket = math.floor(now - state.windowStart)
	local used = state.buckets[bucket] or 0
	if used >= forge.manual.inputRateGuardCps then
		return false
	end
	state.buckets[bucket] = used + 1
	state.valid += 1
	return true
end

function ForgeMath.strikeLuck(state: StrikeState): number
	return ForgeMath.luckFromStrikes(state.valid, state.windowEnd - state.windowStart)
end

-- Rarity chances at `luck` as fractions summing to 1 (index = rarity).
function ForgeMath.rarityChances(luck: number): { number }
	luck = clampLuck(luck)
	local base = forge.rarity.baseChancePercent
	local chances = table.create(RARITY_COUNT, 0)
	local scaled = {}
	for _, index in forge.rarity.scaledWithLuck do
		scaled[index] = true
	end
	local taken = 0
	for index = 1, RARITY_COUNT do
		if index ~= forge.rarity.remainder then
			local pct = if scaled[index] then base[index] * luck else base[index]
			chances[index] = pct / 100
			taken += pct
		end
	end
	chances[forge.rarity.remainder] = math.max(0, 100 - taken) / 100
	return chances
end

function ForgeMath.craftsmanshipChances(): { number }
	local out = table.create(QUALITY_COUNT, 0)
	for index, pct in forge.craftsmanship.baseChancePercent do
		out[index] = pct / 100
	end
	return out
end

function ForgeMath.traitChance(rarity: number): number
	return (forge.trait.baseChanceByRarityPercent[rarity] or 0) / 100
end

-- Picks an index from fractional weights with one rng draw.
local function pick(rng: Rng, weights: { number }): number
	local roll = rng:NextNumber()
	local total = 0
	for _, w in weights do
		total += w
	end
	local target = roll * total
	local acc = 0
	for index, w in weights do
		acc += w
		if target < acc then
			return index
		end
	end
	-- Floating point remainder: return the last index with a nonzero weight.
	for index = #weights, 1, -1 do
		if weights[index] > 0 then
			return index
		end
	end
	return 1
end

local function pickFrom<T>(rng: Rng, list: { T }): T
	local index = math.min(#list, math.floor(rng:NextNumber() * #list) + 1)
	return list[index]
end

-- Position inside the material band before clamping.
function ForgeMath.rawPosition(rarity: number, quality: number, hasTrait: boolean, jitter: number): number
	return forge.rarity.valueBandPositions[rarity]
		+ forge.craftsmanship.valueBandOffsets[quality]
		+ (if hasTrait then forge.trait.bonusToValuePosition else 0)
		+ jitter
end

-- Sale value for a roll; always an integer inside [priceMin, priceMax] of the material.
function ForgeMath.valueFor(materialIndex: number, rarity: number, quality: number, hasTrait: boolean, jitter: number): number
	local mat = Materials[materialIndex]
	local payout = forge.payout
	local position = math.clamp(ForgeMath.rawPosition(rarity, quality, hasTrait, jitter), payout.positionMin, payout.positionMax)
	local value = math.floor(mat.priceMin + position * (mat.priceMax - mat.priceMin) + 0.5)
	return math.clamp(value, mat.priceMin, mat.priceMax)
end

function ForgeMath.designsFor(classIndex: number, rarity: number): { string }
	local class = Balance.weaponClasses[classIndex]
	if rarity == ForgeMath.RARITY.Mythic then
		return class.mythicDesigns
	elseif rarity == ForgeMath.RARITY.Legendary then
		return class.legendaryDesigns
	end
	return class.designs
end

function ForgeMath.isValidMaterial(index: any): boolean
	return type(index) == "number" and index == math.floor(index) and Materials[index] ~= nil
end

function ForgeMath.isValidClass(index: any): boolean
	return type(index) == "number" and index == math.floor(index) and Balance.weaponClasses[index] ~= nil
end

export type RollOptions = { id: string?, ts: number? }

--[[
	Rolls one weapon. Draw order is fixed (rarity, quality, trait chance, trait name, design,
	jitter) so a seeded rng reproduces the same weapon.
]]
function ForgeMath.rollWeapon(rng: Rng, materialIndex: number, classIndex: number, luck: number, options: RollOptions?): Weapon
	assert(ForgeMath.isValidMaterial(materialIndex), "invalid material index")
	assert(ForgeMath.isValidClass(classIndex), "invalid class index")
	local rarity = pick(rng, ForgeMath.rarityChances(luck))
	local quality = pick(rng, ForgeMath.craftsmanshipChances())
	local trait: string? = nil
	if rng:NextNumber() < ForgeMath.traitChance(rarity) then
		trait = pickFrom(rng, forge.trait.names) :: string
	end
	local design: string = pickFrom(rng, ForgeMath.designsFor(classIndex, rarity))
	local payout = forge.payout
	local jitter = payout.jitterMin + rng:NextNumber() * (payout.jitterMax - payout.jitterMin)
	return {
		id = if options and options.id then options.id else "",
		m = materialIndex,
		c = classIndex,
		q = quality,
		r = rarity,
		d = design,
		t = trait,
		v = ForgeMath.valueFor(materialIndex, rarity, quality, trait ~= nil, jitter),
		ts = if options and options.ts then options.ts else 0,
	}
end

-- E[clamp(p + U, lo, hi)] for U uniform on [a, b]; exact, so expectations match the roll.
local function expectedClamped(p: number, a: number, b: number, lo: number, hi: number): number
	local x0, x1 = p + a, p + b
	local width = x1 - x0
	if width <= 0 then
		return math.clamp(x0, lo, hi)
	end
	local function integral(from: number, to: number): number
		-- integral of clamp(x) dx over [from, to]
		local total = 0
		local belowEnd = math.min(to, lo)
		if belowEnd > from then
			total += lo * (belowEnd - from)
		end
		local midStart, midEnd = math.max(from, lo), math.min(to, hi)
		if midEnd > midStart then
			total += (midEnd * midEnd - midStart * midStart) / 2
		end
		local aboveStart = math.max(from, hi)
		if to > aboveStart then
			total += hi * (to - aboveStart)
		end
		return total
	end
	return integral(x0, x1) / width
end

-- Expected sale value of one forge of `materialIndex` at `luck` (ignores integer rounding).
function ForgeMath.expectedValue(materialIndex: number, luck: number): number
	local mat = Materials[materialIndex]
	local payout = forge.payout
	local rarityChances = ForgeMath.rarityChances(luck)
	local qualityChances = ForgeMath.craftsmanshipChances()
	local expectedPosition = 0
	for rarity, pr in rarityChances do
		local traitP = ForgeMath.traitChance(rarity)
		for quality, pq in qualityChances do
			for _, hasTrait in { false, true } do
				local pt = if hasTrait then traitP else 1 - traitP
				local base = ForgeMath.rawPosition(rarity, quality, hasTrait, 0)
				local pos = expectedClamped(base, payout.jitterMin, payout.jitterMax, payout.positionMin, payout.positionMax)
				expectedPosition += pr * pq * pt * pos
			end
		end
	end
	return mat.priceMin + expectedPosition * (mat.priceMax - mat.priceMin)
end

export type OddsTable = {
	luck: number,
	rarity: { { name: string, chance: number } },
	craftsmanship: { { name: string, chance: number } },
	traitByRarity: { { name: string, chance: number } },
	traitNames: { string },
}

-- Exact (unrounded) odds for a disclosure screen at a given luck.
function ForgeMath.oddsTable(luck: number): OddsTable
	luck = clampLuck(luck)
	local rarity = {}
	for index, chance in ForgeMath.rarityChances(luck) do
		rarity[index] = { name = forge.rarity.names[index], chance = chance }
	end
	local craftsmanship = {}
	for index, chance in ForgeMath.craftsmanshipChances() do
		craftsmanship[index] = { name = forge.craftsmanship.names[index], chance = chance }
	end
	local traitByRarity = {}
	for index, name in forge.rarity.names do
		traitByRarity[index] = { name = name, chance = ForgeMath.traitChance(index) }
	end
	return {
		luck = luck,
		rarity = rarity,
		craftsmanship = craftsmanship,
		traitByRarity = traitByRarity,
		traitNames = table.clone(forge.trait.names),
	}
end

-- Joint chance of one exact outcome (rarity, quality, trait name or nil, design) at `luck`.
function ForgeMath.outcomeChance(luck: number, classIndex: number, rarity: number, quality: number, trait: string?, design: string?): number
	local p = ForgeMath.rarityChances(luck)[rarity] * ForgeMath.craftsmanshipChances()[quality]
	local traitP = ForgeMath.traitChance(rarity)
	if trait then
		p *= traitP / #forge.trait.names
	else
		p *= 1 - traitP
	end
	if design then
		local designs = ForgeMath.designsFor(classIndex, rarity)
		p *= if table.find(designs, design) then 1 / #designs else 0
	end
	return p
end

-- "Perfect Infernal Mithril Sword"
function ForgeMath.weaponName(weapon: Weapon): string
	local parts = {}
	if weapon.q ~= 2 then -- "Standard" reads as noise in a name
		table.insert(parts, forge.craftsmanship.names[weapon.q])
	end
	if weapon.t then
		table.insert(parts, weapon.t)
	end
	table.insert(parts, Materials[weapon.m].name)
	table.insert(parts, Balance.weaponClasses[weapon.c].name)
	return table.concat(parts, " ")
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 1234 -> "1.23K", 12516238278 -> "12.5B"
function ForgeMath.formatCoins(n: number): string
	local negative = n < 0
	n = math.abs(n)
	local tier = 1
	while n >= 1000 and tier < #SUFFIXES do
		n /= 1000
		tier += 1
	end
	local text
	if tier == 1 then
		text = tostring(math.floor(n))
	elseif n >= 100 then
		text = string.format("%d", math.floor(n)) .. SUFFIXES[tier]
	elseif n >= 10 then
		text = string.format("%.1f", math.floor(n * 10) / 10) .. SUFFIXES[tier]
	else
		text = string.format("%.2f", math.floor(n * 100) / 100) .. SUFFIXES[tier]
	end
	return if negative then "-" .. text else text
end

return ForgeMath
