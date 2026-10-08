--!strict
--[[
	Forge Companion kinds and equip rules.

	Status: PROPOSED FOR PROTOTYPE (docs/05, docs/13). Every number is a playtest starting
	value, not owner-approved balance.

	Bonus families map onto existing workshop stats only (no combat):
	  extract  ore produced per second
	  smelt    ingots refined per second
	  prep     heat/prep phase speed (time divisor); never forge luck
	  storage  ore/ingot storage capacity
	Values are additive fractions (0.10 = +10%). Equipped companions are summed per family,
	then each family is capped at +200% (3x total), per docs/13.

	Kinds reuse a handful of shared rigs (`modelKind`) recoloured per kind (`color`), so the
	whole catalog needs only seven companion meshes plus the two premium creatures.
]]

export type Bonus = { extract: number?, smelt: number?, prep: number?, storage: number? }

export type Kind = {
	id: string,
	name: string,
	rarity: string,
	bonus: Bonus,
	color: Color3,
	modelKind: string,
	premium: boolean?, -- sold directly with disclosed bonuses; never in an egg; cannot be released
}

local Companions = {}

Companions.Families = { "extract", "smelt", "prep", "storage" }
Companions.FamilyCap = 2.0 -- max additive bonus per family (+200% = 3x)

Companions.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Exclusive" }
Companions.RarityColors = {
	Common = Color3.fromRGB(190, 190, 190),
	Uncommon = Color3.fromRGB(95, 200, 95),
	Rare = Color3.fromRGB(70, 140, 235),
	Epic = Color3.fromRGB(170, 80, 230),
	Legendary = Color3.fromRGB(255, 170, 30),
	Exclusive = Color3.fromRGB(255, 80, 120),
}

Companions.BaseSlots = 2
Companions.EarnedSlotAtEvolutionRank = 1 -- third slot comes from the first evolution
Companions.MaxSlots = 3
Companions.InventoryCapacity = 100
Companions.HatchCooldownSec = 1.0

-- Pet merging (docs/21 §12): three identical pets of the same level become one pet one level
-- higher. Each level multiplies the pet's bonuses. Premium pets cannot be merged.
Companions.MergeCount = 3
Companions.MaxLevel = 5
Companions.LevelMultipliers = { 1, 1.6, 2.5, 4, 6.5 }

function Companions.levelMultiplier(level: number): number
	return Companions.LevelMultipliers[math.clamp(math.floor(level or 1), 1, Companions.MaxLevel)]
end

local rgb = Color3.fromRGB

local kinds: { Kind } = {
	-- Hearth Egg (scale .04)
	{ id = "soot_mole", name = "Soot Mole", rarity = "Common", modelKind = "Mole", color = rgb(70, 64, 60), bonus = { extract = 0.04 } },
	{ id = "bellows_bat", name = "Bellows Bat", rarity = "Uncommon", modelKind = "Bat", color = rgb(150, 75, 45), bonus = { prep = 0.06 } },
	{ id = "clockwork_helper", name = "Clockwork Helper", rarity = "Rare", modelKind = "Clockwork", color = rgb(196, 160, 70), bonus = { smelt = 0.09 } },
	{ id = "crate_mimic", name = "Crate Mimic", rarity = "Epic", modelKind = "Mimic", color = rgb(150, 105, 60), bonus = { storage = 0.14 } },
	{ id = "ore_golem", name = "Ore Golem", rarity = "Legendary", modelKind = "Golem", color = rgb(190, 110, 70), bonus = { extract = 0.20 } },

	-- Ember Egg (scale .07)
	{ id = "cinder_mole", name = "Cinder Mole", rarity = "Common", modelKind = "Mole", color = rgb(120, 50, 35), bonus = { extract = 0.07 } },
	{ id = "ember_sprite", name = "Ember Sprite", rarity = "Uncommon", modelKind = "Sprite", color = rgb(255, 120, 40), bonus = { prep = 0.105 } },
	{ id = "gearwing_bat", name = "Gearwing Bat", rarity = "Rare", modelKind = "Bat", color = rgb(180, 150, 90), bonus = { smelt = 0.16 } },
	{ id = "vault_mimic", name = "Vault Mimic", rarity = "Epic", modelKind = "Mimic", color = rgb(110, 115, 125), bonus = { storage = 0.245 } },
	{ id = "magma_salamander", name = "Magma Salamander", rarity = "Legendary", modelKind = "Salamander", color = rgb(230, 70, 30), bonus = { prep = 0.35 } },

	-- Rune Egg (scale .11)
	{ id = "rune_mole", name = "Rune Mole", rarity = "Common", modelKind = "Mole", color = rgb(70, 90, 140), bonus = { extract = 0.11 } },
	{ id = "glyph_clockwork", name = "Glyph Clockwork", rarity = "Uncommon", modelKind = "Clockwork", color = rgb(80, 170, 200), bonus = { smelt = 0.165 } },
	{ id = "moonlit_sprite", name = "Moonlit Sprite", rarity = "Rare", modelKind = "Sprite", color = rgb(190, 210, 255), bonus = { prep = 0.2475 } },
	{ id = "mithril_golem", name = "Mithril Golem", rarity = "Epic", modelKind = "Golem", color = rgb(170, 220, 230), bonus = { extract = 0.385 } },
	{ id = "runic_salamander", name = "Runic Salamander", rarity = "Legendary", modelKind = "Salamander", color = rgb(60, 220, 180), bonus = { smelt = 0.55 } },

	-- Storm Egg (scale .16)
	{ id = "frost_mimic", name = "Frost Mimic", rarity = "Common", modelKind = "Mimic", color = rgb(170, 220, 245), bonus = { storage = 0.16 } },
	{ id = "storm_bat", name = "Storm Bat", rarity = "Uncommon", modelKind = "Bat", color = rgb(90, 100, 170), bonus = { prep = 0.24 } },
	{ id = "thunder_mole", name = "Thunder Mole", rarity = "Rare", modelKind = "Mole", color = rgb(240, 220, 70), bonus = { extract = 0.36 } },
	{ id = "obsidian_clockwork", name = "Obsidian Clockwork", rarity = "Epic", modelKind = "Clockwork", color = rgb(40, 30, 50), bonus = { smelt = 0.56 } },
	{ id = "tempest_golem", name = "Tempest Golem", rarity = "Legendary", modelKind = "Golem", color = rgb(110, 140, 255), bonus = { extract = 0.80 } },

	-- Astral Egg (scale .22)
	{ id = "sunlit_sprite", name = "Sunlit Sprite", rarity = "Common", modelKind = "Sprite", color = rgb(255, 210, 90), bonus = { prep = 0.22 } },
	{ id = "lunar_mimic", name = "Lunar Mimic", rarity = "Uncommon", modelKind = "Mimic", color = rgb(200, 205, 230), bonus = { storage = 0.33 } },
	{ id = "astral_salamander", name = "Astral Salamander", rarity = "Rare", modelKind = "Salamander", color = rgb(140, 110, 255), bonus = { smelt = 0.495 } },
	{ id = "void_mole", name = "Void Mole", rarity = "Epic", modelKind = "Mole", color = rgb(45, 20, 70), bonus = { extract = 0.77 } },
	{ id = "starforged_golem", name = "Starforged Golem", rarity = "Legendary", modelKind = "Golem", color = rgb(120, 170, 255), bonus = { extract = 0.60, smelt = 0.50 } },

	-- Primordial Egg (scale .30)
	{ id = "nebula_bat", name = "Nebula Bat", rarity = "Common", modelKind = "Bat", color = rgb(170, 70, 200), bonus = { prep = 0.30 } },
	{ id = "chrono_clockwork", name = "Chrono Clockwork", rarity = "Uncommon", modelKind = "Clockwork", color = rgb(230, 190, 120), bonus = { smelt = 0.45 } },
	{ id = "aether_mimic", name = "Aether Mimic", rarity = "Rare", modelKind = "Mimic", color = rgb(150, 240, 255), bonus = { storage = 0.675 } },
	{ id = "primordial_sprite", name = "Primordial Sprite", rarity = "Epic", modelKind = "Sprite", color = rgb(255, 120, 220), bonus = { prep = 1.05 } },
	{ id = "primordial_wyrm", name = "Primordial Wyrm", rarity = "Legendary", modelKind = "Salamander", color = rgb(255, 245, 200), bonus = { extract = 0.90, smelt = 0.60 } },

	-- Premium, sold directly with fully disclosed guaranteed bonuses (docs/05, docs/07).
	{ id = "golden_forge_dragon", name = "Golden Forge Dragon", rarity = "Exclusive", modelKind = "Dragon", color = rgb(255, 200, 50), bonus = { extract = 1.00, smelt = 0.20 }, premium = true },
	{ id = "apprentice_anvil_pup", name = "Apprentice Anvil Pup", rarity = "Exclusive", modelKind = "Pup", color = rgb(150, 155, 165), bonus = { prep = 0.10, storage = 0.10 }, premium = true },
}

Companions.Kinds = kinds
Companions.ById = {} :: { [string]: Kind }
for _, kind in kinds do
	assert(Companions.ById[kind.id] == nil, "duplicate companion kind " .. kind.id)
	Companions.ById[kind.id] = kind
end

return Companions
