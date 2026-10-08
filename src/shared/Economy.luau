--!strict
--[[
	Economy — pure, synchronous rules that read and mutate a player's profile table.

	Services (DataService, ProductionService, ForgeService, UpgradeService) own sessions, timers
	and Roblox APIs; every rule that touches coins, ore, ingots, levels or weapons lives here so it
	is testable without Studio. Nothing in this module yields, so each call is atomic on the server.

	Functions that can fail return (ok: boolean, resultOrError). Error codes are short strings
	the UI can map to messages.

	Bonuses: services pass a `Bonuses` table ({ extract, smelt, prep, storage } fractions, e.g.
	0.3 = +30%) summed from companions, evolution and premium entitlements. Each family is
	capped at Balance.production.maxConfiguredProductionFamilyMultiplier (3x) in total.
]]

local Config = script.Parent.Config
local Balance = require(Config.Balance)
local Materials = require(Config.Materials)
local ForgeMath = require(script.Parent.ForgeMath)

local Economy = {}

Economy.SCHEMA_VERSION = 1
Economy.MATERIAL_COUNT = #Materials
-- PROPOSED: Copper ingots granted on a fresh profile so the first forge needs no waiting.
Economy.STARTER_INGOTS = 3

export type Bonuses = { extract: number, smelt: number, prep: number, storage: number }
export type Weapon = ForgeMath.Weapon

export type Profile = {
	schemaVersion: number,
	coins: number,
	lifetimeCoins: number,
	weaponsForged: number,
	weaponsSold: number,
	highestWeaponValue: number,
	selectedMaterial: number,
	unlockedTier: number,
	ore: { number },
	ingots: { number },
	progress: { ore: number, smelt: number },
	levels: { [string]: number },
	gear: { [string]: number },
	weapons: { [string]: Weapon },
	pending: Weapon?,
	showcase: { string }, -- one entry per pedestal, "" when empty
	journal: { number },
	nextWeaponId: number,
	lastSeen: number,
	[string]: any, -- fields owned by other services (pets, evolution, entitlements, ...)
}

local function zeros(n: number): { number }
	return table.create(n, 0)
end

local function trackLevels(names: { string }): { [string]: number }
	local out = {}
	for _, name in names do
		out[name] = 0
	end
	return out
end

-- Fresh profile. DataService also uses it as the ProfileStore template.
function Economy.newProfile(): Profile
	local ingots = zeros(Economy.MATERIAL_COUNT)
	ingots[1] = Economy.STARTER_INGOTS
	return {
		schemaVersion = Economy.SCHEMA_VERSION,
		coins = 0,
		lifetimeCoins = 0,
		weaponsForged = 0,
		weaponsSold = 0,
		highestWeaponValue = 0,
		selectedMaterial = 1,
		unlockedTier = 1,
		ore = zeros(Economy.MATERIAL_COUNT),
		ingots = ingots,
		progress = { ore = 0, smelt = 0 },
		levels = trackLevels(Balance.machineTracks),
		gear = trackLevels(Balance.gearTracks),
		weapons = {},
		pending = nil,
		showcase = table.create(Balance.inventory.showcaseSlots, ""),
		journal = zeros(Economy.MATERIAL_COUNT),
		nextWeaponId = 1,
		lastSeen = 0,
	}
end

local function nonNegativeInt(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value < 0 then
		return fallback
	end
	return math.floor(value)
end

local function denseCounts(value: any, length: number): { number }
	local out = zeros(length)
	if type(value) == "table" then
		for i = 1, length do
			out[i] = nonNegativeInt(value[i], 0)
		end
	end
	return out
end

--[[
	Repairs a loaded profile in place: fills missing fields, re-densifies per-material arrays to
	the current material count (DataStores cannot hold sparse arrays) and clamps bad numbers.
	Safe to run on every load; never removes fields owned by other services.
]]
function Economy.reconcile(p: Profile): Profile
	local template = Economy.newProfile()
	for key, value in template do
		if p[key] == nil then
			p[key] = value
		end
	end
	for _, key in { "coins", "lifetimeCoins", "weaponsForged", "weaponsSold", "highestWeaponValue", "nextWeaponId", "lastSeen" } do
		p[key] = nonNegativeInt(p[key], template[key])
	end
	p.nextWeaponId = math.max(1, p.nextWeaponId)
	p.ore = denseCounts(p.ore, Economy.MATERIAL_COUNT)
	p.ingots = denseCounts(p.ingots, Economy.MATERIAL_COUNT)
	p.journal = denseCounts(p.journal, Economy.MATERIAL_COUNT)
	p.unlockedTier = math.clamp(nonNegativeInt(p.unlockedTier, 1), 1, Economy.MATERIAL_COUNT)
	p.selectedMaterial = math.clamp(nonNegativeInt(p.selectedMaterial, 1), 1, p.unlockedTier)
	if type(p.progress) ~= "table" then
		p.progress = { ore = 0, smelt = 0 }
	end
	for _, group in { { p.levels, Balance.machineTracks }, { p.gear, Balance.gearTracks } } do
		local levels, names = group[1], group[2]
		for _, name in names do
			levels[name] = math.clamp(nonNegativeInt(levels[name], 0), 0, Balance.tracks[name].maxLevel)
		end
	end
	if type(p.weapons) ~= "table" then
		p.weapons = {}
	end
	if type(p.showcase) ~= "table" then
		p.showcase = {}
	end
	-- Fixed pedestal slots; an id stays on its slot, unknown or repeated ids become "".
	local showcase = table.create(Balance.inventory.showcaseSlots, "")
	for slot = 1, Balance.inventory.showcaseSlots do
		local id = p.showcase[slot]
		if type(id) == "string" and p.weapons[id] and not table.find(showcase, id) then
			showcase[slot] = id
		end
	end
	p.showcase = showcase
	p.schemaVersion = Economy.SCHEMA_VERSION
	return p
end

local function addCoins(p: Profile, amount: number)
	p.coins = math.min(Balance.maxSafeInteger, p.coins + amount)
end

local function addEarnings(p: Profile, amount: number)
	addCoins(p, amount)
	p.lifetimeCoins = math.min(Balance.maxSafeInteger, p.lifetimeCoins + amount)
end

local function spend(p: Profile, cost: number): boolean
	if p.coins < cost then
		return false
	end
	p.coins -= cost
	return true
end

local BONUS_FAMILIES = { "extract", "smelt", "prep", "storage" }

-- Sums bonus sources ({ extract = 0.1 }, ...) into one Bonuses table. Missing fields count 0.
function Economy.combineBonuses(sources: { { [string]: number }? }): Bonuses
	local total: { [string]: number } = { extract = 0, smelt = 0, prep = 0, storage = 0 }
	for _, source in sources do
		if type(source) == "table" then
			for _, family in BONUS_FAMILIES do
				local value = source[family]
				if type(value) == "number" and value == value then
					total[family] += value
				end
			end
		end
	end
	return (total :: any) :: Bonuses
end

-- 1 + bonus, capped at the family multiplier cap and never below 1.
function Economy.familyMultiplier(bonus: number?): number
	return math.clamp(1 + (bonus or 0), 1, Balance.production.maxConfiguredProductionFamilyMultiplier)
end

local NO_BONUSES: Bonuses = { extract = 0, smelt = 0, prep = 0, storage = 0 }

export type Rates = {
	orePerSec: number,
	ingotPerSec: number,
	capacity: number, -- ingot storage cap (sum over all materials)
	oreCapacity: number, -- raw ore storage cap (sum over all materials)
	olderMaterialMultiplier: number,
}

function Economy.rates(p: Profile, bonuses: Bonuses?): Rates
	local b = bonuses or NO_BONUSES
	local prod = Balance.production
	local tiersBehind = math.max(0, p.unlockedTier - p.selectedMaterial)
	local older = math.min(prod.maxOlderMaterialRateMultiplier, prod.olderMaterialRateMultiplierPerTier ^ tiersBehind)
	local extract = (1 + Balance.upgradeEffect("ExtractorOutput", p.levels.ExtractorOutput)) * Economy.familyMultiplier(b.extract)
	local smelt = (1 + Balance.upgradeEffect("SmelterSpeed", p.levels.SmelterSpeed)) * Economy.familyMultiplier(b.smelt)
	local storageFlat = Balance.upgradeEffect("StorageCapacity", p.levels.StorageCapacity) + Balance.upgradeEffect("Apron", p.gear.Apron)
	local storageMult = Economy.familyMultiplier(b.storage)
	return {
		orePerSec = older * extract / prod.baseOreIntervalSec,
		ingotPerSec = smelt / prod.baseSmeltIntervalSec,
		capacity = math.floor((prod.baseIngotStorageCapacity + storageFlat) * storageMult),
		oreCapacity = math.floor((prod.baseOreStorageCapacity + storageFlat) * storageMult),
		olderMaterialMultiplier = older,
	}
end

local function total(list: { number }): number
	local sum = 0
	for _, n in list do
		sum += n
	end
	return sum
end

-- Which material's ore the smelter takes next: the selected one first, else the highest tier.
local function nextOreToSmelt(p: Profile): number?
	if p.ore[p.selectedMaterial] > 0 then
		return p.selectedMaterial
	end
	for index = Economy.MATERIAL_COUNT, 1, -1 do
		if p.ore[index] > 0 then
			return index
		end
	end
	return nil
end

-- Most simulation steps per settle call; long offline gaps use proportionally bigger steps.
local MAX_STEPS = 20000
-- Absorbs floating point drift so 60 s at 6 s/ore yields exactly 10 ore.
local EPSILON = 1e-9

--[[
	Advances extraction and smelting by `dt` seconds. The extractor produces the selected
	material's ore; the smelter turns ore into ingots of the same material. Each stage stalls
	when its output buffer is full, so nothing is ever created past the caps.
	Returns ore and ingots produced.
]]
function Economy.settle(p: Profile, dt: number, rates: Rates): (number, number)
	if dt ~= dt or dt <= 0 then
		return 0, 0
	end
	local step = math.max(1, dt / MAX_STEPS)
	local remaining = dt
	local oreMade, ingotsMade = 0, 0
	local progress = p.progress
	local oreStock = total(p.ore)
	local ingotStock = total(p.ingots)
	while remaining > 0 do
		local slice = math.min(step, remaining)
		remaining -= slice

		if oreStock < rates.oreCapacity then
			progress.ore += rates.orePerSec * slice
			local whole = math.min(math.floor(progress.ore + EPSILON), rates.oreCapacity - oreStock)
			if whole > 0 then
				p.ore[p.selectedMaterial] += whole
				oreStock += whole
				oreMade += whole
				progress.ore = math.max(0, progress.ore - whole)
			end
		end
		if oreStock >= rates.oreCapacity then
			progress.ore = math.min(progress.ore, 1)
		end

		if ingotStock < rates.capacity and oreStock > 0 then
			progress.smelt += rates.ingotPerSec * slice
			while progress.smelt >= 1 - EPSILON and ingotStock < rates.capacity do
				local source = nextOreToSmelt(p)
				if not source then
					break
				end
				p.ore[source] -= 1
				p.ingots[source] += 1
				oreStock -= 1
				ingotStock += 1
				ingotsMade += 1
				progress.smelt = math.max(0, progress.smelt - 1)
			end
		end
		if ingotStock >= rates.capacity or oreStock <= 0 then
			-- Idle smelter keeps at most one unit of progress, so it cannot bank a burst.
			progress.smelt = math.min(progress.smelt, 1)
		end
	end
	return oreMade, ingotsMade
end

-- Settles the time since `lastSeen` (capped by maxOfflineAccrualSec). Returns seconds settled.
function Economy.settleOffline(p: Profile, now: number, rates: Rates): number
	if p.lastSeen <= 0 or now <= p.lastSeen then
		p.lastSeen = now
		return 0
	end
	local elapsed = math.min(now - p.lastSeen, Balance.production.maxOfflineAccrualSec)
	Economy.settle(p, elapsed, rates)
	p.lastSeen = now
	return elapsed
end

function Economy.selectMaterial(p: Profile, index: any): (boolean, any)
	if not ForgeMath.isValidMaterial(index) then
		return false, "InvalidMaterial"
	end
	if index > p.unlockedTier then
		return false, "MaterialLocked"
	end
	p.selectedMaterial = index
	-- Ore already mined stays as that material; only future extraction changes.
	return true, index
end

-- Buys the next extractor tier, unlocking (and selecting) the next material.
function Economy.unlockNextMaterial(p: Profile): (boolean, any)
	local nextIndex = p.unlockedTier + 1
	local mat = Materials[nextIndex]
	if not mat then
		return false, "MaxTier"
	end
	if not spend(p, mat.unlockCost) then
		return false, "NotEnoughCoins"
	end
	p.unlockedTier = nextIndex
	p.selectedMaterial = nextIndex
	return true, nextIndex
end

function Economy.trackLevel(p: Profile, track: string): number?
	local def = Balance.tracks[track]
	if not def then
		return nil
	end
	local levels = if def.kind == "gear" then p.gear else p.levels
	return levels[track] or 0
end

function Economy.buyUpgrade(p: Profile, track: any): (boolean, any)
	if type(track) ~= "string" or not Balance.tracks[track] then
		return false, "InvalidTrack"
	end
	local def = Balance.tracks[track]
	local levels = if def.kind == "gear" then p.gear else p.levels
	local level = levels[track] or 0
	local cost = Balance.upgradeCost(track, level)
	if not cost then
		return false, "MaxLevel"
	end
	if not spend(p, cost) then
		return false, "NotEnoughCoins"
	end
	levels[track] = level + 1
	return true, level + 1
end

export type Timing = { heatSec: number, windowSec: number, revealSec: number }

-- Phase lengths for the next forge. Upgrades shorten downtime only, never the strike window.
function Economy.forgeTiming(p: Profile, mode: string, bonuses: Bonuses?): Timing
	local b = bonuses or NO_BONUSES
	local timing = Balance.forge.timing
	local hammer = Balance.upgradeEffect("Hammer", p.gear.Hammer)
	local heatCut = math.min(timing.maxDowntimeReduction, Balance.upgradeEffect("FurnaceHeat", p.levels.FurnaceHeat) + hammer)
	local revealCut = math.min(timing.maxDowntimeReduction, Balance.upgradeEffect("AnvilFinish", p.levels.AnvilFinish) + hammer)
	return {
		heatSec = timing.baseHeatSec * (1 - heatCut) / Economy.familyMultiplier(b.prep),
		windowSec = if mode == "manual" then Balance.forge.manual.strikeWindowSec else Balance.forge.auto.windowSec,
		revealSec = timing.baseQuenchAndRevealSec * (1 - revealCut),
	}
end

function Economy.weaponCount(p: Profile): number
	local count = 0
	for _ in p.weapons do
		count += 1
	end
	return count
end

-- Room for one more weapon once the current pending result is auto-kept.
function Economy.hasRoom(p: Profile): boolean
	local after = Economy.weaponCount(p) + (if p.pending then 1 else 0)
	return after < Balance.inventory.maxWeapons
end

-- Checks a forge can start. Does not spend anything: material is consumed at completion.
function Economy.canForge(p: Profile, materialIndex: any, classIndex: any): (boolean, string?)
	if not ForgeMath.isValidMaterial(materialIndex) then
		return false, "InvalidMaterial"
	end
	if not ForgeMath.isValidClass(classIndex) then
		return false, "InvalidClass"
	end
	if p.ingots[materialIndex] < Balance.forge.materialUnitsPerRoll then
		return false, "NoMaterial"
	end
	if not Economy.hasRoom(p) then
		return false, "InventoryFull"
	end
	return true, nil
end

--[[
	Completes a forge atomically: spends the ingot (Gloves may refund it), rolls the weapon,
	auto-keeps any previous pending result, sets `pending`, and updates counters and journal.
	`luck` must already be server-derived (strike state or auto mode), never client-claimed.
]]
function Economy.completeForge(p: Profile, materialIndex: number, classIndex: number, luck: number, rng: ForgeMath.Rng, now: number): (boolean, any)
	local ok, err = Economy.canForge(p, materialIndex, classIndex)
	if not ok then
		return false, err
	end
	local id = "w" .. p.nextWeaponId
	local weapon = ForgeMath.rollWeapon(rng, materialIndex, classIndex, luck, { id = id, ts = now })
	local keepIngot = rng:NextNumber() < Balance.upgradeEffect("Gloves", p.gear.Gloves)
	if not keepIngot then
		p.ingots[materialIndex] -= Balance.forge.materialUnitsPerRoll
	end
	p.nextWeaponId += 1
	if p.pending then
		p.weapons[p.pending.id] = p.pending
	end
	p.pending = weapon
	p.weaponsForged += 1
	p.highestWeaponValue = math.max(p.highestWeaponValue, weapon.v)
	p.journal[materialIndex] = bit32.bor(p.journal[materialIndex], bit32.lshift(1, weapon.r - 1))
	return true, weapon
end

-- Sells or keeps the pending forge result. A second call finds nothing pending.
function Economy.resolvePending(p: Profile, action: any): (boolean, any)
	local weapon = p.pending
	if not weapon then
		return false, "NothingPending"
	end
	if action == "sell" then
		p.pending = nil
		addEarnings(p, weapon.v)
		p.weaponsSold += 1
		return true, { action = "sell", weapon = weapon, coins = weapon.v }
	elseif action == "keep" then
		if Economy.weaponCount(p) >= Balance.inventory.maxWeapons then
			return false, "InventoryFull"
		end
		p.pending = nil
		p.weapons[weapon.id] = weapon
		return true, { action = "keep", weapon = weapon }
	end
	return false, "InvalidAction"
end

-- Sells kept weapons by id. Unknown, duplicate and showcased ids are skipped, never paid twice.
function Economy.sellWeapons(p: Profile, ids: any): (boolean, any)
	if type(ids) ~= "table" or #ids == 0 or #ids > Balance.inventory.maxSellBatch then
		return false, "InvalidRequest"
	end
	local sold, coins = {}, 0
	for _, id in ids do
		local weapon = if type(id) == "string" then p.weapons[id] else nil
		if weapon and not table.find(p.showcase, id) then
			p.weapons[id] = nil
			coins += weapon.v
			p.weaponsSold += 1
			table.insert(sold, id)
		end
	end
	if #sold == 0 then
		return false, "NothingSold"
	end
	addEarnings(p, coins)
	return true, { sold = sold, coins = coins }
end

-- Places a kept weapon on pedestal `slot` (1..showcaseSlots), or clears it when id is nil/"".
-- A weapon stands on at most one pedestal; placing it elsewhere moves it.
function Economy.setShowcase(p: Profile, slot: any, id: any): (boolean, any)
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > Balance.inventory.showcaseSlots then
		return false, "InvalidSlot"
	end
	if id == nil or id == "" then
		p.showcase[slot] = ""
		return true, p.showcase
	end
	if type(id) ~= "string" or not p.weapons[id] then
		return false, "UnknownWeapon"
	end
	local at = table.find(p.showcase, id)
	if at then
		p.showcase[at] = ""
	end
	p.showcase[slot] = id
	return true, p.showcase
end

-- Puts a kept weapon on the first free pedestal, or takes it down if already shown.
function Economy.toggleShowcase(p: Profile, id: any): (boolean, any)
	if type(id) ~= "string" or not p.weapons[id] then
		return false, "UnknownWeapon"
	end
	local at = table.find(p.showcase, id)
	if at then
		p.showcase[at] = ""
		return true, p.showcase
	end
	local free = table.find(p.showcase, "")
	if not free then
		return false, "ShowcaseFull"
	end
	p.showcase[free] = id
	return true, p.showcase
end

-- True when weapon of `rarity` has been forged from `materialIndex` (collection journal).
function Economy.hasDiscovered(p: Profile, materialIndex: number, rarity: number): boolean
	return bit32.btest(p.journal[materialIndex] or 0, bit32.lshift(1, rarity - 1))
end

return Economy
