--!strict
--[[
	Game passes and developer products. Status: PROPOSED; prices are the illustrative
	idea-stage numbers from docs/07 and are NOT approved. Every `id` is 0 until the owner
	creates the real pass/product and approves prices.

	`LIVE = false` means MonetizationService never prompts a real purchase. Owned passes can
	still be simulated in Studio through MonetizationService.grantDev.

	Fields:
	  kind          "pass" (permanent) or "product" (repeatable dev product)
	  effects       additive bonus fractions in the same families as companions
	                { extract, smelt, prep, storage } plus `forgeSlots` (extra concurrent forges)
	  paidRandom    true when the purchase modifies or is tied to a randomized outcome; such
	                items are never offered where PolicyService restricts paid random items
	  grants        what a product/pass hands out on purchase (companion kind, coins, charges)
]]

export type Product = {
	key: string,
	kind: "pass" | "product",
	id: number,
	name: string,
	description: string,
	illustrativeRobux: number?,
	effects: { [string]: number }?,
	paidRandom: boolean?,
	grants: { companion: string?, coins: number?, evolveCharges: number? }?,
}

local Products = {}

Products.LIVE = false

local list: { Product } = {
	{
		key = "PremiumAutoForge",
		kind = "pass",
		id = 0,
		name = "Premium Auto Forge",
		description = "Auto forging at 4x luck. Free auto forging is 1.5x and skilled manual hammering reaches 5x.",
		illustrativeRobux = 399,
		paidRandom = true, -- changes rarity odds, so it needs disclosure and the policy gate
	},
	{
		key = "MultiForge",
		kind = "pass",
		id = 0,
		name = "Multi-Forge",
		description = "One extra forge slot. Each extra weapon still costs its own ingot and rolls independently.",
		effects = { forgeSlots = 1 },
	},
	{
		key = "MultiHatch",
		kind = "pass",
		id = 0,
		name = "Multi-Hatch",
		description = "Open 3 or 5 eggs at once. Each egg still costs coins; odds are unchanged.",
		paidRandom = true, -- convenience on a randomized item; gated conservatively
	},
	{
		key = "GoldenForgeDragon",
		kind = "pass",
		id = 0,
		name = "Golden Forge Dragon",
		description = "Guaranteed companion: +100% extraction and +20% smelting.",
		illustrativeRobux = 249,
		grants = { companion = "golden_forge_dragon" },
	},
	{
		key = "TitanExcavator",
		kind = "pass",
		id = 0,
		name = "Titan Excavator",
		description = "Premium extractor: +100% ore output.",
		illustrativeRobux = 299,
		effects = { extract = 1.0 },
	},
	{
		key = "DragonFurnace",
		kind = "pass",
		id = 0,
		name = "Dragon Furnace",
		description = "Premium furnace: +50% heat preparation speed.",
		illustrativeRobux = 499,
		effects = { prep = 0.5 },
	},
	{
		key = "CollectionMagnet",
		kind = "pass",
		id = 0,
		name = "Collection Magnet",
		description = "Auto-collects finished output and unlocks auto-sell filters. Manual pickup and selling stay free.",
	},
	{
		key = "VIPWorkshop",
		kind = "pass",
		id = 0,
		name = "VIP Workshop",
		description = "VIP workshop styling and +25% smelting speed.",
		effects = { smelt = 0.25 },
	},
	{
		key = "ProtectedEvolution",
		kind = "product",
		id = 0,
		name = "Protected Evolution",
		description = "Your next evolution keeps coins, materials and machine levels. You still need fresh progress to qualify.",
		grants = { evolveCharges = 1 },
	},
	{
		key = "StarterPack",
		kind = "product",
		id = 0,
		name = "Blacksmith Starter Pack",
		description = "2,500 coins and the Apprentice Anvil Pup companion.",
		illustrativeRobux = 79,
		grants = { coins = 2_500, companion = "apprentice_anvil_pup" },
	},
}

-- Cap on combined pass effects per family, so passes cannot stack into runaway multipliers.
Products.EffectCap = { extract = 1.0, smelt = 0.5, prep = 0.5, storage = 0.5, forgeSlots = 1 }

Products.List = list
Products.ByKey = {} :: { [string]: Product }
-- Pass ids and dev product ids are separate Roblox namespaces, so they get separate maps.
Products.PassById = {} :: { [number]: Product }
Products.ProductById = {} :: { [number]: Product }
for _, product in list do
	assert(Products.ByKey[product.key] == nil, "duplicate product key " .. product.key)
	Products.ByKey[product.key] = product
	if product.id ~= 0 then
		local map = if product.kind == "pass" then Products.PassById else Products.ProductById
		map[product.id] = product
	end
end

return Products
