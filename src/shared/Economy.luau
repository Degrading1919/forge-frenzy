--!strict
--[[
	Economy — pure, synchronous rules that read and mutate a player's profile table.

	Services own sessions, timers and Roblox APIs; every rule that touches cash, ingots, levels,
	weapons, pads or displays lives here so it is testable without Studio. Nothing in this module
	yields, so each call is atomic on the server.

	Functions that can fail return (ok: boolean, resultOrError). Error codes are short strings
	the network adapter maps to friendly messages.

	v2 workshop model (docs/22):
	  * Ore lines. Each owned line (drill + smelter) mines its own chosen material. Its drill
	    fills a small ore buffer on the conveyor; its smelter turns that ore into ingots in the
	    storage vault, which has one bin per material. A line stalls when its buffer or its
	    material's bin is full, so leftover old ingots never block a new material.
	  * Forge stations. Each owned forge has its own recipe (material + weapon type) and its own
	    automatic keep rule. Recipes consume ingots by weapon size (Config/Balance).
	  * Every forged weapon goes straight into the backpack (auto modes may sell low rarities
	    instead). Ordinary selling happens at the hub sell booth.
	  * Display podiums earn passive cash into the workshop collector.

	Bonuses: services pass a `Bonuses` table ({ extract, smelt, prep, storage } fractions) summed
	from companions, evolution and premium entitlements. Each family is capped at
	Balance.production.maxConfiguredProductionFamilyMultiplier (3x) in total.
]]

local Config = script.Parent.Config
local Balance = require(Config.Balance)
local Materials = require(Config.Materials)
local BuildPads = require(Config.BuildPads)
local ForgeMath = require(script.Parent.ForgeMath)

local Economy = {}

Economy.SCHEMA_VERSION = 2
Economy.MATERIAL_COUNT = #Materials
-- Copper ingots granted on a fresh profile so the first forges need no waiting.
Economy.STARTER_INGOTS = 6
-- The starter recipe: Copper Dagger (one ingot), so a brand-new player forges at once.
Economy.STARTER_CLASS = 4

export type Bonuses = { extract: number, smelt: number, prep: number, storage: number }
export type Weapon = ForgeMath.Weapon
export type Line = { m: number, ore: number, po: number, ps: number }
export type Station = { m: number, c: number, keep: number, auto: string? }

export type Profile = {
	schemaVersion: number,
	coins: number,
	lifetimeCoins: number,
	weaponsForged: number,
	weaponsSold: number,
	highestWeaponValue: number,
	selectedMaterial: number,
	unlockedTier: number,
	ingots: { number },
	lines: { Line },
	stations: { Station },
	pads: { [string]: boolean },
	levels: { [string]: number },
	gear: { [string]: number },
	weapons: { [string]: Weapon },
	showcase: { string }, -- one entry per podium, "" when empty
	bank: number, -- display income waiting in the collector
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

local function newLine(materialIndex: number): Line
	return { m = materialIndex, ore = 0, po = 0, ps = 0 }
end

local function newStation(materialIndex: number): Station
	-- keep = lowest rarity an automatic forge keeps; 4 (Epic) by default, 7 sells everything.
	return { m = materialIndex, c = Economy.STARTER_CLASS, keep = 4 }
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
		ingots = ingots,
		lines = { newLine(1) },
		stations = { newStation(1) },
		pads = {},
		levels = trackLevels(Balance.machineTracks),
		gear = trackLevels(Balance.gearTracks),
		weapons = {},
		showcase = table.create(Balance.inventory.showcaseSlots, ""),
		bank = 0,
		journal = zeros(Economy.MATERIAL_COUNT),
		nextWeaponId = 1,
		lastSeen = 0,
	}
end

local function finiteNonNegative(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value < 0 then
		return fallback
	end
	return math.min(Balance.maxCoins, value)
end

local function nonNegativeInt(value: any, fallback: number): number
	return math.floor(finiteNonNegative(value, fallback))
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

local function clampMaterial(value: any, unlocked: number): number
	return math.clamp(nonNegativeInt(value, 1), 1, unlocked)
end

function Economy.lineCount(p: Profile): number
	return BuildPads.lineCount(p.pads)
end

function Economy.forgeCount(p: Profile): number
	return BuildPads.forgeCount(p.pads)
end

function Economy.showcaseSlots(p: Profile): number
	return BuildPads.showcaseSlots(p.pads, Balance.display.starterSlots, Balance.inventory.showcaseSlots)
end

-- Grows/shrinks lines and stations to what the owned pads allow, keeping existing entries.
local function fitWorkshop(p: Profile)
	local lines = {}
	for i = 1, Economy.lineCount(p) do
		local line = if type(p.lines) == "table" then p.lines[i] else nil
		if type(line) == "table" then
			lines[i] = {
				m = clampMaterial(line.m, p.unlockedTier),
				ore = math.min(nonNegativeInt(line.ore, 0), Balance.production.lineOreBuffer),
				po = math.clamp(finiteNonNegative(line.po, 0), 0, 1),
				ps = math.clamp(finiteNonNegative(line.ps, 0), 0, 1),
			}
		else
			lines[i] = newLine(p.unlockedTier)
		end
	end
	p.lines = lines
	local stations = {}
	for i = 1, Economy.forgeCount(p) do
		local station = if type(p.stations) == "table" then p.stations[i] else nil
		if type(station) == "table" then
			stations[i] = {
				m = clampMaterial(station.m, p.unlockedTier),
				c = if ForgeMath.isValidClass(station.c) then station.c else Economy.STARTER_CLASS,
				keep = math.clamp(nonNegativeInt(station.keep, 4), 1, 7),
				-- Auto mode to resume after a rejoin ("free" / "premium"), nil when off.
				auto = if station.auto == "free" or station.auto == "premium" then station.auto else nil,
			}
		else
			stations[i] = newStation(p.unlockedTier)
		end
	end
	p.stations = stations
	p.selectedMaterial = p.lines[1].m
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
	for _, key in { "coins", "lifetimeCoins", "highestWeaponValue", "bank" } do
		p[key] = finiteNonNegative(p[key], template[key])
	end
	for _, key in { "weaponsForged", "weaponsSold", "nextWeaponId", "lastSeen" } do
		p[key] = nonNegativeInt(p[key], template[key])
	end
	p.nextWeaponId = math.max(1, p.nextWeaponId)
	p.ingots = denseCounts(p.ingots, Economy.MATERIAL_COUNT)
	p.journal = denseCounts(p.journal, Economy.MATERIAL_COUNT)
	p.unlockedTier = math.clamp(nonNegativeInt(p.unlockedTier, 1), 1, Economy.MATERIAL_COUNT)
	if type(p.pads) ~= "table" then
		p.pads = {}
	end
	for id, value in p.pads do
		if BuildPads.ById[id] == nil or value ~= true then
			p.pads[id] = nil
		end
	end
	fitWorkshop(p)
	if type(p.levels) ~= "table" then p.levels = {} end
	if type(p.gear) ~= "table" then p.gear = {} end
	for _, group in { { p.levels, Balance.machineTracks }, { p.gear, Balance.gearTracks } } do
		local levels, names = group[1], group[2]
		for _, name in names do
			levels[name] = math.clamp(nonNegativeInt(levels[name], 0), 0, Balance.tracks[name].maxLevel)
		end
	end
	if type(p.weapons) ~= "table" then
		p.weapons = {}
	end
	-- v1 kept one result pending a sell/keep choice; v2 keeps every result in the backpack.
	if type(p.pending) == "table" and type(p.pending.id) == "string" and p.weapons[p.pending.id] == nil then
		p.weapons[p.pending.id] = p.pending
	end
	p.pending = nil
	-- Recover the weapon serial from IDs so a fresh forge can never overwrite a kept weapon.
	local largest = 0
	for id, weapon in p.weapons do
		for _, candidate in { id, if type(weapon) == "table" then weapon.id else nil } do
			local serial = if type(candidate) == "string" then tonumber(candidate:match("^w(%d+)$")) else nil
			if serial and serial < 2 ^ 53 then largest = math.max(largest, serial) end
		end
	end
	p.nextWeaponId = math.max(p.nextWeaponId, largest + 1)
	if p.settings ~= nil and type(p.settings) ~= "table" then
		p.settings = {}
	end
	if type(p.showcase) ~= "table" then
		p.showcase = {}
	end
	-- Fixed podium slots; an id stays on its slot while that podium is built.
	local slots = Economy.showcaseSlots(p)
	local showcase = table.create(Balance.inventory.showcaseSlots, "")
	for slot = 1, slots do
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
	p.coins = math.min(Balance.maxCoins, p.coins + amount)
end

local function addEarnings(p: Profile, amount: number)
	addCoins(p, amount)
	p.lifetimeCoins = math.min(Balance.maxCoins, p.lifetimeCoins + amount)
end
Economy.addEarnings = addEarnings

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
	orePerSec: number, -- per line
	ingotPerSec: number, -- per line
	lines: number,
	capacity: number, -- ingot storage cap per material (each material has its own bin)
	oreBuffer: number, -- raw ore one line's conveyor holds
}

function Economy.rates(p: Profile, bonuses: Bonuses?): Rates
	local b = bonuses or NO_BONUSES
	local prod = Balance.production
	local extract = (1 + Balance.upgradeEffect("ExtractorOutput", p.levels.ExtractorOutput)) * Economy.familyMultiplier(b.extract)
	local smelt = (1 + Balance.upgradeEffect("SmelterSpeed", p.levels.SmelterSpeed)) * Economy.familyMultiplier(b.smelt)
	local storageFlat = Balance.upgradeEffect("StorageCapacity", p.levels.StorageCapacity) + Balance.upgradeEffect("Apron", p.gear.Apron)
	return {
		orePerSec = extract / prod.baseOreIntervalSec,
		ingotPerSec = smelt / prod.baseSmeltIntervalSec,
		lines = #p.lines,
		capacity = math.floor((prod.baseIngotStorageCapacity + storageFlat) * Economy.familyMultiplier(b.storage)),
		oreBuffer = prod.lineOreBuffer,
	}
end

function Economy.ingotTotal(p: Profile): number
	local sum = 0
	for _, n in p.ingots do
		sum += n
	end
	return sum
end

-- Most simulation steps per settle call; long offline gaps use proportionally bigger steps.
local MAX_STEPS = 4000
-- Absorbs floating point drift so 60 s at 3 s/ore yields exactly 20 ore.
local EPSILON = 1e-9

--[[
	Advances every ore line by `dt` seconds. A drill adds ore to its line's buffer; the smelter
	turns buffered ore into ingots of the line's material in the shared vault. Each stage stalls
	when its output is full, so nothing is ever created past the caps.
	Returns ore mined and ingots smelted.
]]
function Economy.settle(p: Profile, dt: number, rates: Rates): (number, number)
	if dt ~= dt or dt <= 0 then
		return 0, 0
	end
	local steps = math.clamp(math.ceil(dt), 1, MAX_STEPS)
	local slice = dt / steps
	local oreMade, ingotsMade = 0, 0
	for _ = 1, steps do
		for _, line in p.lines do
			local stock = p.ingots[line.m]
			if line.ore < rates.oreBuffer then
				line.po += rates.orePerSec * slice
				local whole = math.min(math.floor(line.po + EPSILON), rates.oreBuffer - line.ore)
				if whole > 0 then
					line.ore += whole
					oreMade += whole
					line.po = math.max(0, line.po - whole)
				end
			end
			if line.ore >= rates.oreBuffer then
				line.po = math.min(line.po, 1)
			end
			if stock < rates.capacity and line.ore > 0 then
				line.ps += rates.ingotPerSec * slice
				local whole = math.min(math.floor(line.ps + EPSILON), line.ore, rates.capacity - stock)
				if whole > 0 then
					line.ore -= whole
					p.ingots[line.m] += whole
					ingotsMade += whole
					line.ps = math.max(0, line.ps - whole)
				end
			end
			if p.ingots[line.m] >= rates.capacity or line.ore <= 0 then
				-- An idle smelter keeps at most one unit of progress, so it cannot bank a burst.
				line.ps = math.min(line.ps, 1)
			end
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

-- Chooses which material ore line `line` mines. Ore already on its conveyor is smelted as
-- the new material (the conveyor is short; this keeps switching instant and simple).
function Economy.setLineMaterial(p: Profile, lineIndex: any, materialIndex: any): (boolean, any)
	if type(lineIndex) ~= "number" or p.lines[lineIndex] == nil then
		return false, "InvalidLine"
	end
	if not ForgeMath.isValidMaterial(materialIndex) then
		return false, "InvalidMaterial"
	end
	if materialIndex > p.unlockedTier then
		return false, "MaterialLocked"
	end
	p.lines[lineIndex].m = materialIndex
	p.selectedMaterial = p.lines[1].m
	return true, materialIndex
end

-- Legacy single-extractor API: selects line 1's material.
function Economy.selectMaterial(p: Profile, index: any): (boolean, any)
	return Economy.setLineMaterial(p, 1, index)
end

--[[
	Buys material `index`, which must be the next locked one. The ore line it was bought from
	(default 1) switches to it, so the purchase is felt immediately.
]]
function Economy.unlockMaterial(p: Profile, index: any, lineIndex: number?): (boolean, any)
	local nextIndex = p.unlockedTier + 1
	if index == nil then
		index = nextIndex
	end
	if not ForgeMath.isValidMaterial(index) then
		return false, "InvalidMaterial"
	end
	if index <= p.unlockedTier then
		return false, "AlreadyUnlocked"
	end
	if index > nextIndex then
		return false, "UnlockPrevious"
	end
	local mat = Materials[index]
	if not spend(p, mat.unlockCost) then
		return false, "NotEnoughCoins"
	end
	p.unlockedTier = index
	local line = p.lines[lineIndex or 1] or p.lines[1]
	line.m = index
	p.selectedMaterial = p.lines[1].m
	return true, index
end

function Economy.unlockNextMaterial(p: Profile): (boolean, any)
	return Economy.unlockMaterial(p, p.unlockedTier + 1)
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

-- Builds pad `padId` for its price. Returns the pad definition.
function Economy.buyPad(p: Profile, padId: any): (boolean, any)
	local pad = if type(padId) == "string" then BuildPads.ById[padId] else nil
	if not pad then
		return false, "InvalidPad"
	end
	if p.pads[pad.id] then
		return false, "AlreadyBuilt"
	end
	local highest = math.max(p.unlockedTier, p.highestTierEver or 1)
	if not BuildPads.available(pad, p.pads, highest) then
		return false, "PadLocked"
	end
	if not spend(p, pad.cost) then
		return false, "NotEnoughCoins"
	end
	p.pads[pad.id] = true
	fitWorkshop(p)
	return true, pad
end

export type Timing = { heatSec: number, windowSec: number, revealSec: number }

-- Phase lengths for the next forge. Upgrades shorten downtime only, never the strike window.
function Economy.forgeTiming(p: Profile, mode: string, bonuses: Bonuses?): Timing
	local b = bonuses or NO_BONUSES
	local timing = Balance.forge.timing
	local hammer = Balance.upgradeEffect("Hammer", p.gear.Hammer)
	local heat = timing.baseHeatSec - Balance.upgradeEffect("FurnaceHeat", p.levels.FurnaceHeat) - hammer
	local reveal = timing.baseQuenchAndRevealSec - Balance.upgradeEffect("AnvilFinish", p.levels.AnvilFinish) - hammer
	return {
		heatSec = math.max(timing.minPhaseSec, heat) / Economy.familyMultiplier(b.prep),
		windowSec = if mode == "manual" then Balance.forge.manual.strikeWindowSec else Balance.forge.auto.windowSec,
		revealSec = math.max(timing.minPhaseSec, reveal),
	}
end

function Economy.weaponCount(p: Profile): number
	local count = 0
	for _ in p.weapons do
		count += 1
	end
	return count
end

function Economy.hasRoom(p: Profile): boolean
	return Economy.weaponCount(p) < Balance.inventory.maxWeapons
end

-- Checks a forge can start. Does not spend anything: ingots are consumed at completion.
-- `allowFullBackpack` lets automatic forges continue (they sell what does not fit).
function Economy.canForge(p: Profile, materialIndex: any, classIndex: any, allowFullBackpack: boolean?): (boolean, string?)
	if not ForgeMath.isValidMaterial(materialIndex) then
		return false, "InvalidMaterial"
	end
	if not ForgeMath.isValidClass(classIndex) then
		return false, "InvalidClass"
	end
	if materialIndex > p.unlockedTier then
		return false, "MaterialLocked"
	end
	if p.ingots[materialIndex] < Balance.recipeIngots(classIndex) then
		return false, "NoMaterial"
	end
	if not allowFullBackpack and not Economy.hasRoom(p) then
		return false, "InventoryFull"
	end
	return true, nil
end

export type ForgeOptions = {
	mult: number?, -- permanent cash multiplier (evolution)
	keepFrom: number?, -- results below this rarity are sold at once (auto modes); nil keeps all
	allowFullBackpack: boolean?, -- sell instead of failing when the backpack is full
}

local function nextWeaponId(p: Profile): string
	local serial = math.max(1, nonNegativeInt(p.nextWeaponId, 1))
	local id = "w" .. serial
	while p.weapons[id] ~= nil do
		serial += 1
		id = "w" .. serial
	end
	p.nextWeaponId = serial + 1
	return id
end
Economy.nextWeaponId = nextWeaponId

--[[
	Completes one forge atomically: spends the recipe's ingots (Gloves may refund them), rolls the
	weapon, then keeps it in the backpack or sells it. `luck` must already be server-derived
	(strike state or auto mode), never client-claimed.
	Returns { weapon, sold: boolean, coins: number }.
]]
function Economy.completeForge(p: Profile, materialIndex: number, classIndex: number, luck: number, rng: ForgeMath.Rng, now: number, options: ForgeOptions?): (boolean, any)
	local opts = options or {}
	local ok, err = Economy.canForge(p, materialIndex, classIndex, opts.allowFullBackpack)
	if not ok then
		return false, err
	end
	local id = nextWeaponId(p)
	local weapon = ForgeMath.rollWeapon(rng, materialIndex, classIndex, luck, { id = id, ts = now, mult = opts.mult })
	local refund = rng:NextNumber() < Balance.upgradeEffect("Gloves", p.gear.Gloves)
	if not refund then
		p.ingots[materialIndex] -= Balance.recipeIngots(classIndex)
	end
	p.weaponsForged += 1
	p.highestWeaponValue = math.max(p.highestWeaponValue, weapon.v)
	p.journal[materialIndex] = bit32.bor(p.journal[materialIndex], bit32.lshift(1, weapon.r - 1))
	local sell = (opts.keepFrom ~= nil and weapon.r < opts.keepFrom) or not Economy.hasRoom(p)
	if sell then
		addEarnings(p, weapon.v)
		p.weaponsSold += 1
		return true, { weapon = weapon, sold = true, coins = weapon.v, refund = refund }
	end
	p.weapons[id] = weapon
	return true, { weapon = weapon, sold = false, coins = 0, refund = refund }
end

--[[
	One minigame can produce a primary result and one extra independent roll (Multi-Forge).
	Each roll validates its own ingots before charging anything; a missing extra simply reduces
	throughput. Returns { results = { forge result... } }.
]]
function Economy.completeForgeBatch(p: Profile, materialIndex: number, classIndex: number, luck: number, rng: ForgeMath.Rng, now: number, rolls: number, options: ForgeOptions?): (boolean, any)
	if rolls ~= math.floor(rolls) or rolls < 1 or rolls > 2 then
		return false, "InvalidRequest"
	end
	local ok, first = Economy.completeForge(p, materialIndex, classIndex, luck, rng, now, options)
	if not ok then
		return false, first
	end
	local results = { first }
	for _ = 2, rolls do
		local extraOk, extra = Economy.completeForge(p, materialIndex, classIndex, luck, rng, now, options)
		if not extraOk then
			break
		end
		table.insert(results, extra)
	end
	return true, { results = results }
end

-- Sells kept weapons by id. Unknown, duplicate, displayed and `protected` ids are skipped.
function Economy.sellWeapons(p: Profile, ids: any, protected: { [string]: boolean }?): (boolean, any)
	if type(ids) ~= "table" or #ids == 0 or #ids > Balance.inventory.maxSellBatch then
		return false, "InvalidRequest"
	end
	local sold, coins = {}, 0
	for _, id in ids do
		local weapon = if type(id) == "string" then p.weapons[id] else nil
		if weapon and not table.find(p.showcase, id) and not (protected and protected[id]) then
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

-- Every backpack weapon below rarity `keepFrom` (nil sells all), excluding displayed weapons.
function Economy.sellableIds(p: Profile, keepFrom: number?): { string }
	local ids = {}
	for id, weapon in p.weapons do
		if not table.find(p.showcase, id) and (keepFrom == nil or weapon.r < keepFrom) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	while #ids > Balance.inventory.maxSellBatch do
		table.remove(ids)
	end
	return ids
end

function Economy.sellAll(p: Profile, keepFrom: any, protected: { [string]: boolean }?): (boolean, any)
	local threshold = if type(keepFrom) == "number" and keepFrom >= 1 and keepFrom <= 7 then math.floor(keepFrom) else nil
	local ids = Economy.sellableIds(p, threshold)
	if #ids == 0 then
		return false, "NothingSold"
	end
	return Economy.sellWeapons(p, ids, protected)
end

-- Places a kept weapon on podium `slot`, or clears it when id is nil/"". A weapon stands on at
-- most one podium; placing it elsewhere moves it. The podium must be built.
function Economy.setShowcase(p: Profile, slot: any, id: any): (boolean, any)
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > Balance.inventory.showcaseSlots then
		return false, "InvalidSlot"
	end
	if slot > Economy.showcaseSlots(p) then
		return false, "SlotLocked"
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

-- Puts a kept weapon on the first free podium, or takes it down if already shown.
function Economy.toggleShowcase(p: Profile, id: any): (boolean, any)
	if type(id) ~= "string" or not p.weapons[id] then
		return false, "UnknownWeapon"
	end
	local at = table.find(p.showcase, id)
	if at then
		p.showcase[at] = ""
		return true, p.showcase
	end
	for slot = 1, Economy.showcaseSlots(p) do
		if p.showcase[slot] == "" then
			p.showcase[slot] = id
			return true, p.showcase
		end
	end
	return false, "ShowcaseFull"
end

-- What one displayed weapon earns per second (see Balance.display).
function Economy.displayIncome(p: Profile, weapon: Weapon, mult: number?): number
	local value = weapon.v
	if Balance.display.capToCurrentTier then
		value = math.min(value, ForgeMath.maxValue(p.unlockedTier, mult))
	end
	return value * Balance.display.incomePerSecond
end

function Economy.displayIncomeTotal(p: Profile, mult: number?, skip: { [string]: boolean }?): number
	local total = 0
	for slot = 1, Economy.showcaseSlots(p) do
		local id = p.showcase[slot]
		local weapon = if id ~= "" then p.weapons[id] else nil
		if weapon and not (skip and skip[id]) then
			total += Economy.displayIncome(p, weapon, mult)
		end
	end
	return total
end

-- Adds `dt` seconds of display income to the collector bank, capped. Returns cash added.
function Economy.accrueDisplay(p: Profile, dt: number, mult: number?, efficiency: number?, skip: { [string]: boolean }?): number
	if dt ~= dt or dt <= 0 then
		return 0
	end
	local perSec = Economy.displayIncomeTotal(p, mult, skip)
	if perSec <= 0 then
		return 0
	end
	local cap = perSec * Balance.display.bankCapSec
	local before = p.bank
	p.bank = math.min(math.max(before, cap), before + perSec * dt * (efficiency or 1))
	if before >= cap then
		p.bank = before -- already full: nothing more accrues, nothing is lost
	end
	return p.bank - before
end

-- Moves the collector bank into the player's cash. Returns cash collected.
function Economy.collectBank(p: Profile): (boolean, any)
	local amount = math.floor(p.bank)
	if amount <= 0 then
		return false, "NothingToCollect"
	end
	p.bank = 0
	addEarnings(p, amount)
	return true, amount
end

--[[
	Forge station configuration. `keep` is the lowest rarity an automatic forge keeps
	(1 keeps everything, 7 sells everything).
]]
function Economy.configureStation(p: Profile, stationIndex: any, materialIndex: any, classIndex: any, keep: any): (boolean, any)
	if type(stationIndex) ~= "number" or p.stations[stationIndex] == nil then
		return false, "InvalidStation"
	end
	if not ForgeMath.isValidMaterial(materialIndex) then
		return false, "InvalidMaterial"
	end
	if materialIndex > p.unlockedTier then
		return false, "MaterialLocked"
	end
	if not ForgeMath.isValidClass(classIndex) then
		return false, "InvalidClass"
	end
	if type(keep) ~= "number" or keep ~= math.floor(keep) or keep < 1 or keep > 7 then
		return false, "InvalidSetting"
	end
	local station = p.stations[stationIndex]
	station.m, station.c, station.keep = materialIndex, classIndex, keep
	return true, station
end

-- True when weapon of `rarity` has been forged from `materialIndex` (collection journal).
function Economy.hasDiscovered(p: Profile, materialIndex: number, rarity: number): boolean
	return bit32.btest(p.journal[materialIndex] or 0, bit32.lshift(1, rarity - 1))
end

return Economy
