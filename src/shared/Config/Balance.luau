--!strict
--[[
	Balance — tunable numbers for the forging economy (everything except the material list,
	which lives in Config/Materials and is generated from its curve parameters).

	Status: v2, rebuilt after the October 7 owner playtest (docs/21, docs/22). The curve targets a
	fast first session and roughly 500 hours of free automated play to reach the final material;
	tools/lune/simulate-v2.luau reproduces the pacing evidence in docs/23.

	Pure data plus small pure functions: no Roblox services, so clients can read it for odds
	disclosure and shop UI.
]]

local Balance = {}

Balance.version = "2.0.0"
Balance.currency = "Cash"

-- Cash totals are doubles. Late-game values pass 2^53, where whole-dollar precision no longer
-- matters; everything is clamped to this ceiling so a value can never become inf/NaN.
Balance.maxCoins = 1e30
-- Older call sites/tests speak of a "safe integer" ceiling; it is the same clamp now.
Balance.maxSafeInteger = Balance.maxCoins

Balance.eras = {
	"Basic Metals",
	"Refined Metals",
	"Industrial Metals",
	"Arcane Metals",
	"Elemental",
	"Forbidden",
	"Celestial",
	"Ancient",
}

export type WeaponClass = {
	id: string,
	name: string,
	ingots: number, -- ingots one forge of this class consumes (bigger weapon, bigger recipe)
	valueMult: number, -- multiplies the per-ingot material band into the weapon's value
	designs: { string }, -- Common..Epic, reskinned per material
	legendaryDesigns: { string },
	mythicDesigns: { string },
}

--[[
	Class indices are stored in saved weapons and must never be reordered. Recipes follow
	physical size. Bigger recipes pay slightly less per ingot but more per forge, so a player
	who is short on ingots prefers small weapons and a player whose storage is full prefers big
	ones: there is no single dominant class (see docs/22).
]]
Balance.weaponClasses = {
	{
		id = "Sword",
		name = "Sword",
		ingots = 2,
		valueMult = 2.3,
		designs = { "sword_broad", "sword_arming", "sword_runed" },
		legendaryDesigns = { "sword_legendary_dawnbreaker" },
		mythicDesigns = { "sword_mythic_worldsplitter" },
	},
	{
		id = "Greatsword",
		name = "Greatsword",
		ingots = 5,
		valueMult = 5.0,
		designs = { "greatsword_claymore", "greatsword_zweihander", "greatsword_cleaver" },
		legendaryDesigns = { "greatsword_legendary_titanfall" },
		mythicDesigns = { "greatsword_mythic_starforge" },
	},
	{
		id = "Axe",
		name = "Axe",
		ingots = 3,
		valueMult = 3.25,
		designs = { "axe_bearded", "axe_double", "axe_crescent" },
		legendaryDesigns = { "axe_legendary_emberjaw" },
		mythicDesigns = { "axe_mythic_voidreaver" },
	},
	{
		id = "Dagger",
		name = "Dagger",
		ingots = 1,
		valueMult = 1.2,
		designs = { "dagger_stiletto", "dagger_kris", "dagger_fang" },
		legendaryDesigns = { "dagger_legendary_moonfang" },
		mythicDesigns = { "dagger_mythic_whisper" },
	},
	{
		id = "Hammer",
		name = "Hammer",
		ingots = 4,
		valueMult = 4.15,
		designs = { "hammer_maul", "hammer_warhammer", "hammer_forge" },
		legendaryDesigns = { "hammer_legendary_thunderhead" },
		mythicDesigns = { "hammer_mythic_primeval" },
	},
} :: { WeaponClass }

-- Smallest to largest, the order every picker shows.
Balance.classDisplayOrder = { 4, 1, 3, 5, 2 }

function Balance.recipeIngots(classIndex: number): number
	local class = Balance.weaponClasses[classIndex]
	return if class then class.ingots else 1
end

Balance.forge = {
	manual = {
		strikeWindowSec = 6,
		baseLuck = 1,
		luckPerCps = 0.3,
		maxLuck = 5,
		-- Strikes beyond this many inside any one-second bucket are ignored.
		inputRateGuardCps = 20,
		-- Strikes arriving this long after the window closes still count (latency).
		latencyGraceSec = 0.35,
	},
	auto = {
		freeLuck = 1.5,
		premiumLuck = 4,
		-- Automatic hammering is shorter than the manual window: auto is about throughput.
		windowSec = 4,
	},
	timing = {
		baseHeatSec = 2,
		baseQuenchAndRevealSec = 1.5,
		-- Upgrades never shorten a phase below this many seconds.
		minPhaseSec = 0.3,
	},
	rarity = {
		names = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" },
		baseChancePercent = { 65.045, 23, 9, 2.5, 0.45, 0.005 },
		-- Indices of rarities whose chance is multiplied by luck; Common takes the remainder.
		scaledWithLuck = { 3, 4, 5, 6 },
		remainder = 1,
		valueBandPositions = { 0.05, 0.12, 0.25, 0.45, 0.75, 0.95 },
	},
	craftsmanship = {
		names = { "Crude", "Standard", "Fine", "Masterwork", "Perfect" },
		baseChancePercent = { 24, 42, 24, 9, 1 },
		valueBandOffsets = { -0.02, -0.01, 0, 0.025, 0.05 },
	},
	trait = {
		names = { "Infernal", "Frozen", "Stormforged", "Radiant" },
		baseChanceByRarityPercent = { 2, 4, 8, 15, 30, 50 },
		bonusToValuePosition = 0.025,
	},
	payout = {
		jitterMin = -0.01,
		jitterMax = 0.01,
		positionMin = 0.01,
		positionMax = 0.99,
	},
	-- A free player unlocks Auto Forge after this many forges (the tutorial teaches it).
	autoUnlockAfterForges = 3,
}

Balance.production = {
	-- One ore line = drill + smelter. Each line mines its own chosen material.
	baseOreIntervalSec = 3,
	baseSmeltIntervalSec = 3,
	-- Raw ore that can wait on the conveyor in front of one smelter.
	lineOreBuffer = 8,
	-- Ingot storage per material bin in the vault.
	baseIngotStorageCapacity = 25,
	-- Longest offline stretch settled on join; storage caps still apply.
	maxOfflineAccrualSec = 8 * 60 * 60,
	-- Companion + evolution + premium bonuses of one family never exceed this multiplier.
	maxConfiguredProductionFamilyMultiplier = 3,
}

-- Displayed weapons earn passive cash into the workshop's cash collector.
Balance.display = {
	-- Fraction of a weapon's value earned per second while it is on a podium (6% / minute), so a
	-- weapon pays back its sale value in under 20 minutes on display: the steal-or-sell tension.
	incomePerSecond = 0.001,
	-- A displayed weapon never earns as if it were worth more than the best weapon the owner
	-- could forge right now (current tier, biggest recipe, best roll), so a pile of old high-tier
	-- trophies cannot trivialise the climb after an evolution.
	capToCurrentTier = true,
	-- The collector holds at most this many seconds of current display income.
	bankCapSec = 60 * 60,
	-- Offline display income accrues at this efficiency.
	offlineEfficiency = 0.5,
	starterSlots = 2,
}

export type Track = {
	name: string,
	kind: "machine" | "gear",
	station: string, -- where the upgrade is bought in the world
	maxLevel: number,
	baseCost: number,
	growth: number,
	effectPerLevel: number,
	unit: string, -- how the effect reads on the button: "pct" (+%), "flat" (+n), "sec" (-sec), "chance"
	label: string, -- what the effect changes, e.g. "Ore Speed"
	looks: { { fromLevel: number, look: string } }?,
}

--[[
	Upgrade tracks. Buying takes a track from `level` to `level + 1` for
	baseCost * growth^level cash. Machine levels reset on evolution; gear is permanent.

	Effects:
	  ExtractorOutput  ore speed x (1 + effect * level)               (Ore Drill)
	  SmelterSpeed     smelt speed x (1 + effect * level)             (Smelter)
	  StorageCapacity  + effect * level ingot storage                 (Storage Vault)
	  FurnaceHeat      - effect * level seconds of heat               (Forge)
	  AnvilFinish      - effect * level seconds of cooling/reveal     (Forge)
	  Hammer           - effect * level seconds of heat and cooling   (Tool Rack, never luck)
	  Gloves           chance (effect * level) a forge refunds its ingots (Tool Rack)
	  Apron            + effect * level ingot storage                 (Tool Rack)
]]
Balance.tracks = {
	ExtractorOutput = { name = "Ore Drill", label = "Ore Speed", unit = "pct", kind = "machine", station = "Ore", maxLevel = 100, baseCost = 150, growth = 1.42, effectPerLevel = 0.15 },
	SmelterSpeed = { name = "Smelter", label = "Smelt Speed", unit = "pct", kind = "machine", station = "Ore", maxLevel = 100, baseCost = 150, growth = 1.42, effectPerLevel = 0.15 },
	StorageCapacity = { name = "Storage Vault", label = "Storage", unit = "flat", kind = "machine", station = "Storage", maxLevel = 100, baseCost = 100, growth = 1.38, effectPerLevel = 10 },
	FurnaceHeat = { name = "Forge Heat", label = "Heat", unit = "sec", kind = "machine", station = "Forge", maxLevel = 12, baseCost = 300, growth = 3.2, effectPerLevel = 0.1 },
	AnvilFinish = { name = "Quench Tank", label = "Cooling", unit = "sec", kind = "machine", station = "Forge", maxLevel = 8, baseCost = 400, growth = 3.4, effectPerLevel = 0.1 },
	Hammer = {
		name = "Hammer",
		label = "Heat & Cooling",
		unit = "sec",
		kind = "gear",
		station = "Tools",
		maxLevel = 10,
		baseCost = 2500,
		growth = 9,
		effectPerLevel = 0.05,
		looks = { { fromLevel = 0, look = "Wooden" }, { fromLevel = 3, look = "Steel" }, { fromLevel = 6, look = "Enchanted" }, { fromLevel = 9, look = "Legendary" } },
	},
	Gloves = {
		name = "Gloves",
		label = "Free Ingot Chance",
		unit = "chance",
		kind = "gear",
		station = "Tools",
		maxLevel = 10,
		baseCost = 4000,
		growth = 9,
		effectPerLevel = 0.02,
		looks = { { fromLevel = 0, look = "Leather" }, { fromLevel = 4, look = "Reinforced" }, { fromLevel = 8, look = "Runic" } },
	},
	Apron = {
		name = "Apron",
		label = "Storage",
		unit = "flat",
		kind = "gear",
		station = "Tools",
		maxLevel = 10,
		baseCost = 3000,
		growth = 9,
		effectPerLevel = 25,
		looks = { { fromLevel = 0, look = "Basic" }, { fromLevel = 4, look = "Armored" }, { fromLevel = 8, look = "Master" } },
	},
} :: { [string]: Track }

Balance.machineTracks = { "ExtractorOutput", "SmelterSpeed", "StorageCapacity", "FurnaceHeat", "AnvilFinish" }
Balance.gearTracks = { "Hammer", "Gloves", "Apron" }

-- Rounds a big price to three significant digits so buttons read cleanly.
function Balance.roundPrice(cost: number): number
	if cost < 1000 then
		return math.floor(cost + 0.5)
	end
	local magnitude = 10 ^ (math.floor(math.log10(cost)) - 2)
	return math.floor(cost / magnitude + 0.5) * magnitude
end

-- Cash to raise `track` from `level` to `level + 1`, or nil when maxed / unknown.
function Balance.upgradeCost(track: string, level: number): number?
	local def = Balance.tracks[track]
	if not def or level < 0 or level >= def.maxLevel then
		return nil
	end
	return Balance.roundPrice(def.baseCost * def.growth ^ level)
end

-- Raw effect of `track` at `level` (see the table above for units).
function Balance.upgradeEffect(track: string, level: number): number
	local def = Balance.tracks[track]
	if not def then
		return 0
	end
	return def.effectPerLevel * math.clamp(level, 0, def.maxLevel)
end

function Balance.gearLook(track: string, level: number): string?
	local def = Balance.tracks[track]
	if not def or not def.looks then
		return nil
	end
	local look = nil
	for _, entry in def.looks do
		if level >= entry.fromLevel then
			look = entry.look
		end
	end
	return look
end

--[[
	Bonuses granted by owned premium entitlements, keyed by MonetizationService key. Fractions,
	added into the same capped families as companion and evolution bonuses.
]]
Balance.premiumBonuses = {
	TitanExcavator = { extract = 1.0 },
	DragonFurnace = { prep = 0.5 },
	VIPWorkshop = { extract = 0.25, smelt = 0.25 },
} :: { [string]: { [string]: number } }

Balance.inventory = {
	-- Weapons a player can carry in their backpack (displayed weapons included).
	maxWeapons = 250,
	-- Physical podiums in the workshop; build pads unlock them in pairs.
	showcaseSlots = 8,
	-- Most weapon ids accepted by one sell call.
	maxSellBatch = 250,
}

-- Lifetime metrics behind the four leaderboard concepts.
Balance.metrics = { "lifetimeCoins", "weaponsForged", "evolutionRank", "highestWeaponValue" }

return Balance
