--!strict
--[[
	Companion eggs. Status: v2 economy (docs/22).

	Eggs are bought with earned Coins only; there are no paid random eggs here (docs/07
	requires a policy review before any paid egg ships). Opening one egg per action is free
	for everyone; the MultiHatch pass lets a player open 3 or 5 at once, still paying the
	coin cost per egg, so it is convenience only and never changes odds.

	`unlockTier` is compared against the highest material tier the player has ever unlocked
	(kept through evolution), so an evolved player does not lose egg access.

	Odds are identical across eggs so the disclosure UI stays simple; `Eggs.odds(eggId)`
	returns exact percentages computed from the weights.
]]

local Companions = require(script.Parent.Companions)
local Materials = require(script.Parent.Materials)

export type Entry = { kind: string, weight: number }
export type Egg = {
	id: string,
	name: string,
	coinCost: number,
	unlockTier: number,
	color: Color3,
	kinds: { Entry },
	availableFrom: number?, -- unix seconds, for seasonal eggs
	availableUntil: number?,
}

local RARITY_WEIGHT = { Common = 60, Uncommon = 25, Rare = 11, Epic = 3.5, Legendary = 0.5 }

local function entries(kindIds: { string }): { Entry }
	local list = {}
	for _, id in kindIds do
		local kind = Companions.ById[id]
		assert(kind and not kind.premium, "egg references unknown or premium kind " .. id)
		table.insert(list, { kind = id, weight = RARITY_WEIGHT[kind.rarity] })
	end
	return list
end

local rgb = Color3.fromRGB

-- Egg prices follow the v2 curve: a fraction of the unlock price of the material after the
-- one that opens the egg, so every egg is a meaningful but affordable buy when it appears.
local EGG_PRICE_FACTOR = 0.2
local function priced(tier: number): number
	local cost = Materials[math.min(#Materials, tier + 1)].unlockCost * EGG_PRICE_FACTOR
	if cost < 1000 then
		return math.floor(cost + 0.5)
	end
	local magnitude = 10 ^ (math.floor(math.log10(cost)) - 2)
	return math.floor(cost / magnitude + 0.5) * magnitude
end

local list: { Egg } = {
	{
		id = "hearth",
		name = "Hearth Egg",
		coinCost = priced(2),
		unlockTier = 2,
		color = rgb(200, 120, 70),
		kinds = entries({ "soot_mole", "bellows_bat", "clockwork_helper", "crate_mimic", "ore_golem" }),
	},
	{
		id = "ember",
		name = "Ember Egg",
		coinCost = priced(6),
		unlockTier = 6,
		color = rgb(255, 110, 40),
		kinds = entries({ "cinder_mole", "ember_sprite", "gearwing_bat", "vault_mimic", "magma_salamander" }),
	},
	{
		id = "rune",
		name = "Rune Egg",
		coinCost = priced(11),
		unlockTier = 11,
		color = rgb(80, 200, 210),
		kinds = entries({ "rune_mole", "glyph_clockwork", "moonlit_sprite", "mithril_golem", "runic_salamander" }),
	},
	{
		id = "storm",
		name = "Storm Egg",
		coinCost = priced(17),
		unlockTier = 17,
		color = rgb(110, 130, 255),
		kinds = entries({ "frost_mimic", "storm_bat", "thunder_mole", "obsidian_clockwork", "tempest_golem" }),
	},
	{
		id = "astral",
		name = "Astral Egg",
		coinCost = priced(23),
		unlockTier = 23,
		color = rgb(150, 110, 255),
		kinds = entries({ "sunlit_sprite", "lunar_mimic", "astral_salamander", "void_mole", "starforged_golem" }),
	},
	{
		id = "primordial",
		name = "Primordial Egg",
		coinCost = priced(28),
		unlockTier = 28,
		color = rgb(255, 240, 200),
		kinds = entries({ "nebula_bat", "chrono_clockwork", "aether_mimic", "primordial_sprite", "primordial_wyrm" }),
	},
}

local Eggs = {}
Eggs.List = list
Eggs.ById = {} :: { [string]: Egg }
for _, egg in list do
	Eggs.ById[egg.id] = egg
end

-- Exact odds for disclosure: { { kind, name, rarity, percent } }, percent sums to 100.
function Eggs.odds(eggId: string): { { kind: string, name: string, rarity: string, percent: number } }?
	local egg = Eggs.ById[eggId]
	if not egg then
		return nil
	end
	local total = 0
	for _, entry in egg.kinds do
		total += entry.weight
	end
	local out = {}
	for _, entry in egg.kinds do
		local kind = Companions.ById[entry.kind]
		table.insert(out, { kind = entry.kind, name = kind.name, rarity = kind.rarity, percent = entry.weight / total * 100 })
	end
	return out
end

return Eggs
