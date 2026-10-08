--!strict
--[[
	Materials — the 32 metal tiers, in progression order (index 1..32).

	Status: PROPOSED FOR PROTOTYPE. Economic fields mirror design/balance-v0.json
	(MaterialsBalanceSync.spec fails if they drift); `unlockCost` is the JSON's
	extractorUnlockCoinCost. Appearance fields (color, material, accent, glow) drive the shared
	weapon/ore skins: every standard weapon mesh is recoloured from these, never remodelled.
	`material` is an Enum.Material name.
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

local Materials: { Material } = {
	{ id = "copper", name = "Copper", index = 1, era = 1, priceMin = 12, priceMax = 216, unlockCost = 0, color = Color3.fromRGB(184, 115, 51), material = "Metal", accent = nil, glow = false },
	{ id = "tin", name = "Tin", index = 2, era = 1, priceMin = 21, priceMax = 378, unlockCost = 414, color = Color3.fromRGB(170, 176, 180), material = "Metal", accent = nil, glow = false },
	{ id = "bronze", name = "Bronze", index = 3, era = 1, priceMin = 38, priceMax = 684, unlockCost = 870, color = Color3.fromRGB(176, 128, 62), material = "Metal", accent = nil, glow = false },
	{ id = "iron", name = "Iron", index = 4, era = 1, priceMin = 68, priceMax = 1224, unlockCost = 1836, color = Color3.fromRGB(112, 112, 118), material = "Metal", accent = nil, glow = false },
	{ id = "steel", name = "Steel", index = 5, era = 2, priceMin = 120, priceMax = 2160, unlockCost = 3754, color = Color3.fromRGB(160, 170, 182), material = "DiamondPlate", accent = nil, glow = false },
	{ id = "silver", name = "Silver", index = 6, era = 2, priceMin = 214, priceMax = 3852, unlockCost = 7451, color = Color3.fromRGB(208, 212, 220), material = "Foil", accent = nil, glow = false },
	{ id = "gold", name = "Gold", index = 7, era = 2, priceMin = 382, priceMax = 6876, unlockCost = 14764, color = Color3.fromRGB(240, 190, 50), material = "Foil", accent = Color3.fromRGB(255, 236, 150), glow = false },
	{ id = "platinum", name = "Platinum", index = 8, era = 2, priceMin = 679, priceMax = 12222, unlockCost = 28990, color = Color3.fromRGB(228, 230, 236), material = "Foil", accent = Color3.fromRGB(200, 220, 255), glow = false },
	{ id = "cobalt", name = "Cobalt", index = 9, era = 3, priceMin = 1209, priceMax = 21762, unlockCost = 56213, color = Color3.fromRGB(40, 72, 160), material = "Metal", accent = Color3.fromRGB(90, 140, 255), glow = false },
	{ id = "titanium", name = "Titanium", index = 10, era = 3, priceMin = 2153, priceMax = 38754, unlockCost = 108432, color = Color3.fromRGB(132, 138, 150), material = "DiamondPlate", accent = nil, glow = false },
	{ id = "tungsten", name = "Tungsten", index = 11, era = 3, priceMin = 3832, priceMax = 68976, unlockCost = 207949, color = Color3.fromRGB(70, 72, 80), material = "Metal", accent = Color3.fromRGB(150, 150, 160), glow = false },
	{ id = "osmium", name = "Osmium", index = 12, era = 3, priceMin = 6820, priceMax = 122760, unlockCost = 396554, color = Color3.fromRGB(60, 80, 105), material = "Metal", accent = Color3.fromRGB(120, 170, 220), glow = false },
	{ id = "moonsteel", name = "Moonsteel", index = 13, era = 4, priceMin = 12140, priceMax = 218520, unlockCost = 752817, color = Color3.fromRGB(150, 190, 230), material = "Glass", accent = Color3.fromRGB(220, 240, 255), glow = true },
	{ id = "mithril", name = "Mithril", index = 14, era = 4, priceMin = 21609, priceMax = 388962, unlockCost = 1423811, color = Color3.fromRGB(170, 230, 220), material = "Foil", accent = Color3.fromRGB(230, 255, 250), glow = true },
	{ id = "runite", name = "Runite", index = 15, era = 4, priceMin = 38465, priceMax = 692370, unlockCost = 2683440, color = Color3.fromRGB(60, 180, 170), material = "Metal", accent = Color3.fromRGB(120, 255, 230), glow = true },
	{ id = "adamantite", name = "Adamantite", index = 16, era = 4, priceMin = 68467, priceMax = 1232406, unlockCost = 5042013, color = Color3.fromRGB(40, 140, 80), material = "Metal", accent = Color3.fromRGB(120, 255, 160), glow = true },
	{ id = "emberite", name = "Emberite", index = 17, era = 5, priceMin = 121871, priceMax = 2193678, unlockCost = 9447043, color = Color3.fromRGB(240, 90, 30), material = "Neon", accent = Color3.fromRGB(255, 200, 80), glow = true },
	{ id = "frostsilver", name = "Frostsilver", index = 18, era = 5, priceMin = 216931, priceMax = 3904758, unlockCost = 17656485, color = Color3.fromRGB(170, 220, 255), material = "Ice", accent = Color3.fromRGB(240, 250, 255), glow = true },
	{ id = "stormium", name = "Stormium", index = 19, era = 5, priceMin = 386137, priceMax = 6950466, unlockCost = 32925235, color = Color3.fromRGB(120, 110, 230), material = "Metal", accent = Color3.fromRGB(200, 220, 255), glow = true },
	{ id = "obsidian", name = "Obsidian", index = 20, era = 5, priceMin = 687324, priceMax = 12371832, unlockCost = 61270839, color = Color3.fromRGB(30, 22, 40), material = "Glass", accent = Color3.fromRGB(140, 60, 200), glow = true },
	{ id = "bloodiron", name = "Bloodiron", index = 21, era = 6, priceMin = 1223436, priceMax = 22021848, unlockCost = 113803947, color = Color3.fromRGB(150, 20, 30), material = "Metal", accent = Color3.fromRGB(255, 70, 60), glow = true },
	{ id = "soulsteel", name = "Soulsteel", index = 22, era = 6, priceMin = 2177716, priceMax = 39198888, unlockCost = 211011360, color = Color3.fromRGB(140, 240, 220), material = "Glass", accent = Color3.fromRGB(220, 255, 250), glow = true },
	{ id = "starsteel", name = "Starsteel", index = 23, era = 6, priceMin = 3876335, priceMax = 69774030, unlockCost = 390624215, color = Color3.fromRGB(50, 40, 110), material = "Foil", accent = Color3.fromRGB(255, 240, 200), glow = true },
	{ id = "voidmetal", name = "Voidmetal", index = 24, era = 6, priceMin = 6899876, priceMax = 124197768, unlockCost = 722053933, color = Color3.fromRGB(20, 10, 40), material = "Glass", accent = Color3.fromRGB(170, 80, 255), glow = true },
	{ id = "sunmetal", name = "Sunmetal", index = 25, era = 7, priceMin = 12281780, priceMax = 221072040, unlockCost = 1332858017, color = Color3.fromRGB(255, 200, 60), material = "Neon", accent = Color3.fromRGB(255, 250, 210), glow = true },
	{ id = "lunarite", name = "Lunarite", index = 26, era = 7, priceMin = 21861568, priceMax = 393508224, unlockCost = 2457219103, color = Color3.fromRGB(235, 232, 245), material = "Glass", accent = Color3.fromRGB(180, 200, 255), glow = true },
	{ id = "astralite", name = "Astralite", index = 27, era = 7, priceMin = 38913591, priceMax = 700444638, unlockCost = 4524672333, color = Color3.fromRGB(90, 150, 255), material = "Neon", accent = Color3.fromRGB(240, 220, 255), glow = true },
	{ id = "etherium", name = "Etherium", index = 28, era = 7, priceMin = 69266191, priceMax = 1246791438, unlockCost = 8322380636, color = Color3.fromRGB(200, 170, 255), material = "Glass", accent = Color3.fromRGB(255, 255, 255), glow = true },
	{ id = "chronosteel", name = "Chronosteel", index = 29, era = 8, priceMin = 123293821, priceMax = 2219288778, unlockCost = 15291703042, color = Color3.fromRGB(200, 160, 90), material = "Foil", accent = Color3.fromRGB(120, 240, 255), glow = true },
	{ id = "nebulium", name = "Nebulium", index = 30, era = 8, priceMin = 219463001, priceMax = 3950334018, unlockCost = 28069832629, color = Color3.fromRGB(180, 80, 200), material = "Neon", accent = Color3.fromRGB(90, 200, 255), glow = true },
	{ id = "aetherglass", name = "Aetherglass", index = 31, era = 8, priceMin = 390644141, priceMax = 7031594538, unlockCost = 51478371750, color = Color3.fromRGB(190, 240, 255), material = "Glass", accent = Color3.fromRGB(255, 180, 240), glow = true },
	{ id = "primordium", name = "Primordium", index = 32, era = 8, priceMin = 695346571, priceMax = 12516238278, unlockCost = 94326545693, color = Color3.fromRGB(255, 120, 200), material = "Neon", accent = Color3.fromRGB(255, 240, 120), glow = true },
}

return Materials
