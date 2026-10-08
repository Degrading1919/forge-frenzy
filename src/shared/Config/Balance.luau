--!strict
--[[
	Balance — tunable numbers for the core forging economy (everything except the material
	list, which lives in Config/Materials).

	Status: PROPOSED FOR PROTOTYPE. Forge, rarity, craftsmanship, trait, payout and production
	values mirror design/balance-v0.json; MaterialsBalanceSync.spec fails if they drift. Values the
	JSON does not cover yet (machine and gear curves, inventory limits, premium bonus sizes) are
	marked PROPOSED and are safe to retune after playtests.

	Pure data plus small pure functions: no Roblox services, so clients can read it for odds
	disclosure and shop UI.
]]

local Balance = {}

Balance.version = "0.1.0"
Balance.currency = "Coins"

-- Largest integer a double represents exactly; coin totals and values are clamped to it.
Balance.maxSafeInteger = 9007199254740991

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
	designs: { string }, -- Common..Epic, reskinned per material
	legendaryDesigns: { string },
	mythicDesigns: { string },
}

-- One price band per material for every class (balance v0), so class choice is identity only.
Balance.weaponClasses = {
	{
		id = "Sword",
		name = "Sword",
		designs = { "sword_broad", "sword_arming", "sword_runed" },
		legendaryDesigns = { "sword_legendary_dawnbreaker" },
		mythicDesigns = { "sword_mythic_worldsplitter" },
	},
	{
		id = "Greatsword",
		name = "Greatsword",
		designs = { "greatsword_claymore", "greatsword_zweihander", "greatsword_cleaver" },
		legendaryDesigns = { "greatsword_legendary_titanfall" },
		mythicDesigns = { "greatsword_mythic_starforge" },
	},
	{
		id = "Axe",
		name = "Axe",
		designs = { "axe_bearded", "axe_double", "axe_crescent" },
		legendaryDesigns = { "axe_legendary_emberjaw" },
		mythicDesigns = { "axe_mythic_voidreaver" },
	},
	{
		id = "Dagger",
		name = "Dagger",
		designs = { "dagger_stiletto", "dagger_kris", "dagger_fang" },
		legendaryDesigns = { "dagger_legendary_moonfang" },
		mythicDesigns = { "dagger_mythic_whisper" },
	},
	{
		id = "Hammer",
		name = "Hammer",
		designs = { "hammer_maul", "hammer_warhammer", "hammer_forge" },
		legendaryDesigns = { "hammer_legendary_thunderhead" },
		mythicDesigns = { "hammer_mythic_primeval" },
	},
} :: { WeaponClass }

Balance.forge = {
	manual = {
		strikeWindowSec = 6,
		baseLuck = 1,
		luckPerCps = 0.3,
		maxLuck = 5,
		-- Strikes beyond this many inside any one-second bucket are ignored.
		inputRateGuardCps = 20,
		-- PROPOSED: strikes arriving this long after the window closes still count (latency).
		latencyGraceSec = 0.35,
	},
	auto = {
		freeLuck = 1.5,
		premiumLuck = 4,
		-- PROPOSED: auto mode keeps the same strike-window length as the animation.
		windowSec = 6,
	},
	timing = {
		baseHeatSec = 2,
		baseQuenchAndRevealSec = 1.5,
		-- PROPOSED: furnace, anvil and hammer together cut at most this share of downtime.
		maxDowntimeReduction = 0.75,
	},
	materialUnitsPerRoll = 1,
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
}

Balance.production = {
	baseOreIntervalSec = 6,
	baseSmeltIntervalSec = 6.5,
	maxOlderMaterialRateMultiplier = 4,
	olderMaterialRateMultiplierPerTier = 1.15,
	baseIngotStorageCapacity = 30,
	-- PROPOSED: the raw ore buffer shares the ingot cap.
	baseOreStorageCapacity = 30,
	-- PROPOSED: longest offline stretch settled on join; storage caps still apply.
	maxOfflineAccrualSec = 4 * 60 * 60,
	-- Companion + evolution + premium bonuses of one family never exceed this multiplier.
	maxConfiguredProductionFamilyMultiplier = 3,
}

export type Track = {
	name: string,
	kind: "machine" | "gear",
	maxLevel: number,
	baseCost: number,
	growth: number,
	effectPerLevel: number,
	looks: { { fromLevel: number, look: string } }?,
}

--[[
	PROPOSED upgrade tracks. Buying takes a track from `level` to `level + 1` for
	round(baseCost * growth^level) coins. Machine levels are temporary progress (evolution may
	reset `levels`); gear lives in `gear`. ExtractorTier is not a track: unlocking the next
	material costs that material's `unlockCost`.

	Effects:
	  ExtractorOutput  ore rate x (1 + effect * level)
	  SmelterSpeed     ingot rate x (1 + effect * level)
	  StorageCapacity  + effect * level ore and ingot capacity
	  FurnaceHeat      heat time - effect * level (shared downtime cap)
	  AnvilFinish      quench/reveal time - effect * level (shared downtime cap)
	  Hammer           heat and quench time - effect * level each; never touches luck
	  Gloves           chance (effect * level) that a forge keeps its ingot; never extra ingots
	  Apron            + effect * level ore and ingot capacity
]]
Balance.tracks = {
	ExtractorOutput = { name = "Extractor Output", kind = "machine", maxLevel = 30, baseCost = 40, growth = 1.65, effectPerLevel = 0.10 },
	SmelterSpeed = { name = "Smelter Speed", kind = "machine", maxLevel = 30, baseCost = 45, growth = 1.65, effectPerLevel = 0.10 },
	StorageCapacity = { name = "Material Storage", kind = "machine", maxLevel = 30, baseCost = 35, growth = 1.6, effectPerLevel = 10 },
	FurnaceHeat = { name = "Furnace", kind = "machine", maxLevel = 15, baseCost = 60, growth = 2.1, effectPerLevel = 0.04 },
	AnvilFinish = { name = "Anvil", kind = "machine", maxLevel = 15, baseCost = 60, growth = 2.1, effectPerLevel = 0.04 },
	Hammer = {
		name = "Hammer",
		kind = "gear",
		maxLevel = 10,
		baseCost = 250,
		growth = 3.2,
		effectPerLevel = 0.025,
		looks = { { fromLevel = 0, look = "Wooden" }, { fromLevel = 3, look = "Steel" }, { fromLevel = 6, look = "Enchanted" }, { fromLevel = 9, look = "Legendary" } },
	},
	Gloves = {
		name = "Gloves",
		kind = "gear",
		maxLevel = 10,
		baseCost = 400,
		growth = 3.2,
		effectPerLevel = 0.02,
		looks = { { fromLevel = 0, look = "Leather" }, { fromLevel = 4, look = "Reinforced" }, { fromLevel = 8, look = "Runic" } },
	},
	Apron = {
		name = "Apron",
		kind = "gear",
		maxLevel = 10,
		baseCost = 300,
		growth = 3.2,
		effectPerLevel = 8,
		looks = { { fromLevel = 0, look = "Basic" }, { fromLevel = 4, look = "Armored" }, { fromLevel = 8, look = "Master" } },
	},
} :: { [string]: Track }

Balance.machineTracks = { "ExtractorOutput", "SmelterSpeed", "StorageCapacity", "FurnaceHeat", "AnvilFinish" }
Balance.gearTracks = { "Hammer", "Gloves", "Apron" }

-- Coins to raise `track` from `level` to `level + 1`, or nil when maxed / unknown.
function Balance.upgradeCost(track: string, level: number): number?
	local def = Balance.tracks[track]
	if not def or level < 0 or level >= def.maxLevel then
		return nil
	end
	return math.floor(def.baseCost * def.growth ^ level + 0.5)
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
	PROPOSED bonuses granted by owned premium entitlements, keyed by MonetizationService key.
	Fractions, added into the same capped families as companion and evolution bonuses.
	Keys must match Config/Products once the monetization thread lands it.
]]
Balance.premiumBonuses = {
	TitanExcavator = { extract = 1.0 },
	DragonFurnace = { prep = 0.5 },
	VIPWorkshop = { extract = 0.25, smelt = 0.25 },
} :: { [string]: { [string]: number } }

Balance.inventory = {
	-- PROPOSED: bounds profile size; a full inventory blocks new forges until the player sells.
	maxWeapons = 250,
	-- PROPOSED: physical pedestals in the personal workshop.
	showcaseSlots = 6,
	-- PROPOSED: most weapon ids accepted by one sell call.
	maxSellBatch = 250,
}

-- Lifetime metrics behind the four leaderboard concepts.
Balance.metrics = { "lifetimeCoins", "weaponsForged", "evolutionRank", "highestWeaponValue" }

return Balance
