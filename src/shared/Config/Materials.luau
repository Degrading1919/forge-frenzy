--!strict
--[[
	Materials — the 32 metal tiers, in progression order (index 1..32).

	Status: v2 economy (docs/22, docs/23). Appearance fields (color, material, accent, glow) drive
	the shared weapon/ore skins: every standard weapon mesh is recoloured from these, never
	remodelled. `material` is an Enum.Material name.

	Economic fields are generated from the curve parameters below instead of being typed by hand:
	  priceMin / priceMax  per-ingot value band; a weapon is worth band position * class valueMult
	  unlockCost           cash to buy this material at the ore station (Copper is free)
	The value ratio between tiers grows from early to late game and unlock prices grow faster
	still, so the first materials arrive in minutes while the last ones take hundreds of hours.
	tools/lune/simulate-v2.luau measures the result against the owner's ~500 hour target.
]]

export type Material = {
	id: string,
	name: string,
	index: number,
	era: number,
	priceMin: number,
	priceMax: number,
	unlockCost: number,
	color: Color3,
	material: string,
	accent: Color3?,
	glow: boolean,
}

local Curve = {
	-- Copper's per-ingot band minimum, in cash.
	basePriceMin = 20,
	-- priceMax = priceMin * bandRatio (Mythic weapons sit near the top of the band).
	bandRatio = 18,
	-- Value ratio between consecutive tiers: valueGrowthStart at Tin, rising linearly to
	-- valueGrowthEnd at the final material.
	valueGrowthStart = 2.1,
	valueGrowthEnd = 3.0,
	-- Unlock price of tier k = priceMin(k - 1) * weapons(k): how many minimum-value ingots of
	-- the previous material the unlock costs. weapons(k) = unlockScale * (k - 1)^unlockPower,
	-- so early unlocks take seconds to minutes and late unlocks take tens of hours.
	unlockScale = 12,
	unlockPower = 3.66,
	-- The first few unlocks are discounted (rampFloor at Bronze rising to full price at
	-- rampUntilTier) so a new player's first session moves quickly.
	rampFloor = 0.55,
	rampUntilTier = 8,
}

local list = {
	{ id = "copper", name = "Copper", index = 1, era = 1, color = Color3.fromRGB(184, 115, 51), material = "Metal", accent = nil, glow = false },
	{ id = "tin", name = "Tin", index = 2, era = 1, color = Color3.fromRGB(170, 176, 180), material = "Metal", accent = nil, glow = false },
	{ id = "bronze", name = "Bronze", index = 3, era = 1, color = Color3.fromRGB(176, 128, 62), material = "Metal", accent = nil, glow = false },
	{ id = "iron", name = "Iron", index = 4, era = 1, color = Color3.fromRGB(112, 112, 118), material = "Metal", accent = nil, glow = false },
	{ id = "steel", name = "Steel", index = 5, era = 2, color = Color3.fromRGB(160, 170, 182), material = "DiamondPlate", accent = nil, glow = false },
	{ id = "silver", name = "Silver", index = 6, era = 2, color = Color3.fromRGB(208, 212, 220), material = "Foil", accent = nil, glow = false },
	{ id = "gold", name = "Gold", index = 7, era = 2, color = Color3.fromRGB(240, 190, 50), material = "Foil", accent = Color3.fromRGB(255, 236, 150), glow = false },
	{ id = "platinum", name = "Platinum", index = 8, era = 2, color = Color3.fromRGB(228, 230, 236), material = "Foil", accent = Color3.fromRGB(200, 220, 255), glow = false },
	{ id = "cobalt", name = "Cobalt", index = 9, era = 3, color = Color3.fromRGB(40, 72, 160), material = "Metal", accent = Color3.fromRGB(90, 140, 255), glow = false },
	{ id = "titanium", name = "Titanium", index = 10, era = 3, color = Color3.fromRGB(132, 138, 150), material = "DiamondPlate", accent = nil, glow = false },
	{ id = "tungsten", name = "Tungsten", index = 11, era = 3, color = Color3.fromRGB(70, 72, 80), material = "Metal", accent = Color3.fromRGB(150, 150, 160), glow = false },
	{ id = "osmium", name = "Osmium", index = 12, era = 3, color = Color3.fromRGB(60, 80, 105), material = "Metal", accent = Color3.fromRGB(120, 170, 220), glow = false },
	{ id = "moonsteel", name = "Moonsteel", index = 13, era = 4, color = Color3.fromRGB(150, 190, 230), material = "Glass", accent = Color3.fromRGB(220, 240, 255), glow = true },
	{ id = "mithril", name = "Mithril", index = 14, era = 4, color = Color3.fromRGB(170, 230, 220), material = "Foil", accent = Color3.fromRGB(230, 255, 250), glow = true },
	{ id = "runite", name = "Runite", index = 15, era = 4, color = Color3.fromRGB(60, 180, 170), material = "Metal", accent = Color3.fromRGB(120, 255, 230), glow = true },
	{ id = "adamantite", name = "Adamantite", index = 16, era = 4, color = Color3.fromRGB(40, 140, 80), material = "Metal", accent = Color3.fromRGB(120, 255, 160), glow = true },
	{ id = "emberite", name = "Emberite", index = 17, era = 5, color = Color3.fromRGB(240, 90, 30), material = "Neon", accent = Color3.fromRGB(255, 200, 80), glow = true },
	{ id = "frostsilver", name = "Frostsilver", index = 18, era = 5, color = Color3.fromRGB(170, 220, 255), material = "Ice", accent = Color3.fromRGB(240, 250, 255), glow = true },
	{ id = "stormium", name = "Stormium", index = 19, era = 5, color = Color3.fromRGB(120, 110, 230), material = "Metal", accent = Color3.fromRGB(200, 220, 255), glow = true },
	{ id = "obsidian", name = "Obsidian", index = 20, era = 5, color = Color3.fromRGB(30, 22, 40), material = "Glass", accent = Color3.fromRGB(140, 60, 200), glow = true },
	{ id = "bloodiron", name = "Bloodiron", index = 21, era = 6, color = Color3.fromRGB(150, 20, 30), material = "Metal", accent = Color3.fromRGB(255, 70, 60), glow = true },
	{ id = "soulsteel", name = "Soulsteel", index = 22, era = 6, color = Color3.fromRGB(140, 240, 220), material = "Glass", accent = Color3.fromRGB(220, 255, 250), glow = true },
	{ id = "starsteel", name = "Starsteel", index = 23, era = 6, color = Color3.fromRGB(50, 40, 110), material = "Foil", accent = Color3.fromRGB(255, 240, 200), glow = true },
	{ id = "voidmetal", name = "Voidmetal", index = 24, era = 6, color = Color3.fromRGB(20, 10, 40), material = "Glass", accent = Color3.fromRGB(170, 80, 255), glow = true },
	{ id = "sunmetal", name = "Sunmetal", index = 25, era = 7, color = Color3.fromRGB(255, 200, 60), material = "Neon", accent = Color3.fromRGB(255, 250, 210), glow = true },
	{ id = "lunarite", name = "Lunarite", index = 26, era = 7, color = Color3.fromRGB(235, 232, 245), material = "Glass", accent = Color3.fromRGB(180, 200, 255), glow = true },
	{ id = "astralite", name = "Astralite", index = 27, era = 7, color = Color3.fromRGB(90, 150, 255), material = "Neon", accent = Color3.fromRGB(240, 220, 255), glow = true },
	{ id = "etherium", name = "Etherium", index = 28, era = 7, color = Color3.fromRGB(200, 170, 255), material = "Glass", accent = Color3.fromRGB(255, 255, 255), glow = true },
	{ id = "chronosteel", name = "Chronosteel", index = 29, era = 8, color = Color3.fromRGB(200, 160, 90), material = "Foil", accent = Color3.fromRGB(120, 240, 255), glow = true },
	{ id = "nebulium", name = "Nebulium", index = 30, era = 8, color = Color3.fromRGB(180, 80, 200), material = "Neon", accent = Color3.fromRGB(90, 200, 255), glow = true },
	{ id = "aetherglass", name = "Aetherglass", index = 31, era = 8, color = Color3.fromRGB(190, 240, 255), material = "Glass", accent = Color3.fromRGB(255, 180, 240), glow = true },
	{ id = "primordium", name = "Primordium", index = 32, era = 8, color = Color3.fromRGB(255, 120, 200), material = "Neon", accent = Color3.fromRGB(255, 240, 120), glow = true },
}

local function roundPrice(cost: number): number
	if cost < 1000 then
		return math.floor(cost + 0.5)
	end
	local magnitude = 10 ^ (math.floor(math.log10(cost)) - 2)
	return math.floor(cost / magnitude + 0.5) * magnitude
end

local Materials: { Material } = {}
local priceMin = Curve.basePriceMin
for index, row in list do
	local previousMin = priceMin
	if index > 1 then
		local t = (index - 2) / (#list - 2)
		priceMin *= Curve.valueGrowthStart + (Curve.valueGrowthEnd - Curve.valueGrowthStart) * t
		local ramp = math.clamp(Curve.rampFloor + (1 - Curve.rampFloor) * (index - 3) / (Curve.rampUntilTier - 3), Curve.rampFloor, 1)
		row.unlockCost = roundPrice(previousMin * Curve.unlockScale * (index - 1) ^ Curve.unlockPower * ramp)
	else
		row.unlockCost = 0
	end
	row.priceMin = roundPrice(priceMin)
	row.priceMax = roundPrice(priceMin * Curve.bandRatio)
	Materials[index] = row :: any
end

return Materials
