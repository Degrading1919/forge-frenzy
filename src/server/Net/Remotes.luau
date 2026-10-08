--!strict
-- Network glue (v2). Creates ReplicatedStorage.Remotes, maps Protocol actions onto the gameplay
-- services, enforces "where you must stand" rules with the world hooks in Net/Plots, and
-- replicates profile snapshots. This is the single adapter to adjust when service APIs change.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Protocol = require(Shared.Protocol)
local A = Protocol.Actions

local Remotes = {}
Remotes.studioLog = {} :: { any }

local servicesFolder = script.Parent.Parent:FindFirstChild("Services")
local cache: { [string]: any } = {}
local function svc(name: string): any
	if cache[name] ~= nil then
		return cache[name] or nil
	end
	local m = servicesFolder and servicesFolder:FindFirstChild(name)
	local ok, mod = false, nil
	if m then
		ok, mod = pcall(require, m)
	end
	cache[name] = ok and mod or false
	return ok and mod or nil
end
Remotes.svc = svc

local function config(name: string): any
	local m = Shared:FindFirstChild("Config") and Shared.Config:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, mod = pcall(require, m)
	return ok and mod or nil
end
Remotes.config = config

local function plots(): any
	return require(script.Parent.Plots) :: any
end

local folder: Folder
local push: RemoteEvent
local strikeEvent: RemoteEvent
local actionFn: RemoteFunction

local dirty: { [Player]: boolean } = {}
local lastAction: { [Player]: { [string]: number } } = {}
local session: { [Player]: { settings: any, plotIndex: number } } = {}
-- Weapons are the bulk of a snapshot; resend the list only when it may have changed.
local lastWeaponsKey: { [Player]: string } = {}

local MATERIAL_COUNT = 32
local MACHINE_TRACKS = { "ExtractorOutput", "SmelterSpeed", "StorageCapacity", "FurnaceHeat", "AnvilFinish" }
local GEAR_TRACKS = { "Hammer", "Gloves", "Apron" }

function Remotes.push(player: Player, kind: string, payload: any)
	if push and player.Parent then
		push:FireClient(player, kind, payload)
	end
end

function Remotes.pushAll(kind: string, payload: any)
	if push then
		push:FireAllClients(kind, payload)
	end
end

function Remotes.toast(player: Player, text: string, kind: string?)
	Remotes.push(player, Protocol.Push.Toast, { text = text, kind = kind or "info" })
end

function Remotes.markDirty(player: Player)
	dirty[player] = true
end

function Remotes.session(player: Player)
	local s = session[player]
	if not s then
		s = { settings = nil, plotIndex = 0 }
		session[player] = s
	end
	return s
end

local function toArray(map: any, n: number): { number }
	local out = table.create(n, 0)
	if type(map) == "table" then
		for k, v in map do
			local i = tonumber(k)
			if i and i >= 1 and i <= n then
				out[i] = v
			end
		end
	end
	return out
end

local function safe(fn: any, ...: any): any
	if type(fn) ~= "function" then
		return nil
	end
	local ok, res = pcall(fn, ...)
	return ok and res or nil
end

-- Builds the replicated snapshot from the authoritative profile (docs/22 "Client snapshot").
function Remotes.snapshot(player: Player): any?
	local Data = svc("DataService")
	local p = Data and Data.get(player)
	if not p then
		return nil
	end
	local Production, Upgrade, Monet, Evo, Forge, Workshop = svc("ProductionService"), svc("UpgradeService"), svc("MonetizationService"), svc("EvolutionService"), svc("ForgeService"), svc("WorkshopService")
	local Products = config("Products")
	local Balance = config("Balance")
	local Economy = require(Shared.Economy) :: any
	local weaponCount = 0
	for _ in p.weapons or {} do
		weaponCount += 1
	end
	local weaponsKey = table.concat({ weaponCount, p.weaponsForged or 0, p.weaponsSold or 0, p.weaponsStolen or 0, p.weaponsLost or 0, p.nextWeaponId or 0 }, ":")
	local weapons = nil
	if lastWeaponsKey[player] ~= weaponsKey then
		lastWeaponsKey[player] = weaponsKey
		weapons = {}
		for _, w in p.weapons or {} do
			table.insert(weapons, w)
		end
		table.sort(weapons, function(a, b)
			return (a.v or 0) > (b.v or 0)
		end)
	end
	local pets = {}
	for id, pet in p.pets or {} do
		table.insert(pets, { id = pet.id or id, kind = pet.kind or pet.k, lv = pet.lv or 1 })
	end
	local showcase = {}
	for i = 1, 8 do
		showcase[i] = (p.showcase and p.showcase[i]) or ""
	end
	local upgradeCosts = {}
	for _, info in (Upgrade and safe(Upgrade.list, player)) or {} do
		upgradeCosts[info.track] = info.cost or false
	end
	local bonuses = Production and safe(Production.bonuses, player)
	local rates = Production and safe(Production.rates, player) or {}
	local manual = safe(Economy.forgeTiming, p, "manual", bonuses) or {}
	local auto = safe(Economy.forgeTiming, p, "free", bonuses) or {}
	local Materials = config("Materials")
	local nextMat = Materials and Materials[(p.unlockedTier or 1) + 1]
	local evolutionStatus = Evo and safe(function()
		local ok, status = Evo.status(player)
		return ok and status or nil
	end) or nil
	local s = Remotes.session(player)
	local entitlements = {}
	for k, v in p.entitlements or {} do
		entitlements[k] = v and true or false
	end
	if Monet and Monet.ownedKeys then
		for k in safe(Monet.ownedKeys, player) or {} do
			entitlements[k] = true
		end
	end
	local lines = {}
	for i, line in p.lines or {} do
		lines[i] = { m = line.m, ore = line.ore }
	end
	local stations = {}
	for i, station in p.stations or {} do
		stations[i] = { m = station.m, c = station.c, keep = station.keep }
	end
	local carry = Workshop and Workshop.carryOf(player)
	local carried = Workshop and Workshop.carriedFrom(player) or {}
	local carriedList = {}
	for id in carried do
		table.insert(carriedList, id)
	end
	return {
		coins = p.coins or 0,
		lifetimeCoins = p.lifetimeCoins or 0,
		weaponsForged = p.weaponsForged or 0,
		highestWeaponValue = p.highestWeaponValue or 0,
		unlockedTier = p.unlockedTier or 1,
		highestTierEver = p.highestTierEver or p.unlockedTier or 1,
		selectedMaterial = p.selectedMaterial or 1,
		ingots = toArray(p.ingots, MATERIAL_COUNT),
		lines = lines,
		stations = stations,
		forgeStatus = Forge and safe(Forge.status, player) or {},
		pads = p.pads or {},
		levels = p.levels or {},
		gear = p.gear or {},
		costs = {
			upgrades = upgradeCosts,
			unlockNext = nextMat and nextMat.unlockCost or false,
		},
		weapons = weapons, -- nil when unchanged since the last snapshot (client keeps its copy)
		weaponCount = weaponCount,
		maxWeapons = Balance and Balance.inventory.maxWeapons or 250,
		showcase = showcase,
		showcaseSlots = safe(Economy.showcaseSlots, p) or 2,
		carried = carriedList,
		bank = p.bank or 0,
		incomePerSec = Workshop and safe(Workshop.incomePerSec, player) or 0,
		journal = toArray(p.journal, MATERIAL_COUNT),
		pets = pets,
		equipped = p.equipped or {},
		petSlots = p.petSlots or 2,
		evolutionRank = p.evolutionRank or 0,
		cashMult = Forge and safe(Forge.cashMultiplier, player) or 1,
		forgedSinceEvolve = evolutionStatus and evolutionStatus.progress.forged or 0,
		highestTierSinceEvolve = evolutionStatus and evolutionStatus.progress.tier or 1,
		evolution = evolutionStatus,
		evolutionEligible = evolutionStatus ~= nil and evolutionStatus.eligible == true,
		evolveCharges = p.evolveCharges or 0,
		entitlements = entitlements,
		settings = p.settings or { music = true, sfx = true, vfx = true },
		tutorial = p.tutorial or 0,
		autoUnlocked = (p.weaponsForged or 0) >= (Balance and Balance.forge.autoUnlockAfterForges or 3),
		rates = {
			orePerSec = rates.orePerSec or 0,
			ingotPerSec = rates.ingotPerSec or 0,
			lines = rates.lines or 1,
			capacity = rates.capacity or 25,
			heatSec = manual.heatSec or 2,
			windowSec = manual.windowSec or 6,
			revealSec = manual.revealSec or 1.5,
			autoWindowSec = auto.windowSec or 4,
		},
		carrying = if carry then { weapon = carry.weapon, deadline = carry.deadline, victim = carry.victim.UserId } else nil,
		plotIndex = s.plotIndex,
		isStudio = RunService:IsStudio(),
		productsLive = Products ~= nil and Products.LIVE == true,
		paidRandomAllowed = Monet ~= nil and safe(Monet.canOfferPaidRandom, player) == true,
		saveStatus = Data.getStatus and safe(Data.getStatus, player) or { persistent = false, mode = "Unknown" },
	}
end

--------------------------------------------------------------------------------
-- Action handlers: each returns (ok, result)
--------------------------------------------------------------------------------

local MIN_INTERVAL = 0.08 -- per-action spam guard (seconds)

-- Short, kid-readable messages for every error code a service can return.
local FRIENDLY = {
	NotLoaded = "Your save is still loading", NoMaterial = "Not enough ingots! Wait for your ore line",
	PaidRandomRestricted = "Premium luck features are unavailable for this account",
	InventoryFull = "Backpack full! Sell at the booth", Busy = "You're already hammering",
	NotOwned = "You don't own that yet", NotEnoughCoins = "Not enough cash", MaxTier = "You have every material!",
	MaxLevel = "Already maxed", MaterialLocked = "Buy that material at the Ore Drill first",
	InvalidMaterial = "Pick a material", InvalidClass = "Pick a weapon",
	AutoLocked = "Forge 3 weapons by hand to unlock Auto Forge", TooFar = "Walk closer first",
	UnlockPrevious = "Buy the material before it first", AlreadyUnlocked = "You already have it",
	PadLocked = "Unlock more materials to build this", AlreadyBuilt = "Already built",
	NothingSold = "Nothing to sell", NothingToCollect = "No cash yet",
	SlotLocked = "Build more podiums first", ShowcaseFull = "All podiums are full",
	UnknownWeapon = "That weapon is gone", InvalidStation = "Build that forge first",
	ForgeLocked = "This forge is locked!", Shielded = "New players are protected",
	EmptySlot = "Nothing there to steal", AlreadyCarried = "Someone is already stealing that",
	StealCooldown = "Catch your breath first", Moved = "The weapon moved!", TooSlow = "Too slow, try again", AlreadyCarrying = "You're already carrying loot",
	OwnWeapon = "That's yours!", SlotCooldown = "That podium was just robbed", TooFast = "Hold to steal",
	LockCooldown = "Lock is recharging", AlreadyLocked = "Already locked", NoWorkshop = "No workshop",
	["egg locked"] = "Unlock more materials to open this egg",
	["not enough coins"] = "Not enough cash", ["inventory full"] = "Pet inventory full",
	["multi-hatch not owned"] = "Multi-Hatch pass required", ["not eligible"] = "Not ready to evolve yet",
	["need more copies"] = "Need 3 of the same pet", ["max level"] = "Already max level",
	["nothing to merge"] = "No pets to merge", ["premium companions cannot be merged"] = "Premium pets can't merge",
	["hatching too fast"] = "Hatching too fast",
}
Remotes.FRIENDLY = FRIENDLY

local function call(serviceName: string, fnName: string, ...: any): (boolean, any)
	local s = svc(serviceName)
	if not s or type(s[fnName]) ~= "function" then
		return false, "Not available yet"
	end
	local ok, a, b = pcall(s[fnName], ...)
	if not ok then
		warn("[Remotes]", serviceName, fnName, a)
		return false, "Something went wrong"
	end
	if a == nil then
		return true, nil
	end
	if type(a) == "boolean" then
		if a == false and type(b) == "string" and FRIENDLY[b] then
			return false, FRIENDLY[b]
		end
		return a, b
	end
	return true, a
end

local function isInt(n: any, lo: number, hi: number): boolean
	return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi
end

local function carriedOf(player: Player): { [string]: boolean }
	local Workshop = svc("WorkshopService")
	return Workshop and Workshop.carriedFrom(player) or {}
end

local handlers: { [string]: (Player, ...any) -> (boolean, any) } = {}

-- Station actions must come from the station: the player has to stand where that panel opens
-- (Net/Plots.nearPlace). Automation that is already running keeps going when they walk away.
local AWAY = "Walk back to the station first"
local function at(player: Player, kind: string, arg: any?): boolean
	return plots().nearPlace(player, kind, arg)
end
Remotes.at = at

handlers[A.ForgeBegin] = function(player, station, mode)
	if not isInt(station, 1, 3) then
		return false, "Invalid forge"
	end
	if mode ~= "manual" and mode ~= "free" and mode ~= "premium" then
		return false, "Invalid mode"
	end
	if mode ~= "manual" and not at(player, "Forge", station) then
		return false, AWAY -- manual forging checks its own (closer) range in ForgeService
	end
	return call("ForgeService", "begin", player, station, mode)
end
handlers[A.ForgeStop] = function(player, station)
	if station ~= nil and not isInt(station, 1, 3) then
		return false, "Invalid forge"
	end
	return call("ForgeService", "stopAuto", player, station)
end
handlers[A.ForgeConfigure] = function(player, station, materialIndex, classIndex, keep)
	if not isInt(station, 1, 3) or not isInt(materialIndex, 1, MATERIAL_COUNT) or not isInt(classIndex, 1, 5) or not isInt(keep, 1, 7) then
		return false, "Invalid recipe"
	end
	if not at(player, "Forge", station) then
		return false, AWAY
	end
	return call("ForgeService", "configure", player, station, materialIndex, classIndex, keep)
end
handlers[A.LineMaterial] = function(player, line, index)
	if not isInt(line, 1, 3) or not isInt(index, 1, MATERIAL_COUNT) then
		return false, "Invalid material"
	end
	if not at(player, "Ore", line) then
		return false, AWAY
	end
	return call("ProductionService", "setLineMaterial", player, line, index)
end
handlers[A.UnlockMaterial] = function(player, index, line)
	if not isInt(index, 1, MATERIAL_COUNT) or (line ~= nil and not isInt(line, 1, 3)) then
		return false, "Invalid material"
	end
	if not at(player, "Ore", line) then
		return false, AWAY
	end
	local ok, res = call("ProductionService", "unlockMaterial", player, index, line)
	if ok then
		Remotes.push(player, Protocol.Push.Unlocked, { material = res })
	end
	return ok, res
end
handlers[A.BuyUpgrade] = function(player, track)
	if type(track) ~= "string" or (not table.find(MACHINE_TRACKS, track) and not table.find(GEAR_TRACKS, track)) then
		return false, "Invalid upgrade"
	end
	local Balance = config("Balance")
	local place = Balance and Balance.tracks[track] and Balance.tracks[track].station
	if not place or not at(player, place) then
		return false, AWAY
	end
	return call("UpgradeService", "buy", player, track)
end
handlers[A.BuyPad] = function(player, padId)
	if type(padId) ~= "string" or #padId > 32 then
		return false, "Invalid pad"
	end
	local ok, res = call("WorkshopService", "buyPad", player, padId)
	if ok then
		Remotes.push(player, Protocol.Push.Built, { padId = padId })
	end
	return ok, res
end
handlers[A.SellAll] = function(player, keepFrom)
	if keepFrom ~= nil and not isInt(keepFrom, 1, 7) then
		return false, "Invalid choice"
	end
	if not plots().nearBooth(player) then
		return false, "Sell at the booth in the middle of town!"
	end
	local Forge = svc("ForgeService")
	local mult = Forge and safe(Forge.cashMultiplier, player) or 1
	local ok, res = call("ForgeService", "sellAll", player, keepFrom, carriedOf(player), mult)
	if ok then
		Remotes.push(player, Protocol.Push.Sold, { coins = res.coins, count = #res.sold })
	end
	return ok, res
end
handlers[A.SellWeapons] = function(player, ids)
	if type(ids) ~= "table" or #ids == 0 or #ids > 250 then
		return false, "Invalid weapons"
	end
	for _, id in ids do
		if type(id) ~= "string" or #id > 64 then
			return false, "Invalid weapons"
		end
	end
	if not plots().nearBooth(player) then
		return false, "Sell at the booth in the middle of town!"
	end
	local Forge = svc("ForgeService")
	local mult = Forge and safe(Forge.cashMultiplier, player) or 1
	local ok, res = call("ForgeService", "sellWeapons", player, ids, carriedOf(player), mult)
	if ok then
		Remotes.push(player, Protocol.Push.Sold, { coins = res.coins, count = #res.sold })
	end
	return ok, res
end
handlers[A.SetShowcase] = function(player, slot, weaponId)
	if not isInt(slot, 1, 8) or (weaponId ~= nil and (type(weaponId) ~= "string" or #weaponId > 64)) then
		return false, "Invalid podium"
	end
	local Data = svc("DataService")
	local p = Data and Data.get(player)
	if not p then
		return false, FRIENDLY.NotLoaded
	end
	local current = p.showcase[slot]
	local carried = carriedOf(player)
	if (current and carried[current]) or (weaponId and carried[weaponId]) then
		return false, "Someone is stealing that weapon!"
	end
	local Economy = require(Shared.Economy) :: any
	local ok, res = Economy.setShowcase(p, slot, weaponId)
	if ok then
		Data.markDirty(player)
		return true, res
	end
	return false, FRIENDLY[res] or res
end
handlers[A.ToggleShowcase] = function(player, weaponId)
	if type(weaponId) ~= "string" or #weaponId > 64 then
		return false, "Invalid weapon"
	end
	if carriedOf(player)[weaponId] then
		return false, "Someone is stealing that weapon!"
	end
	local Data = svc("DataService")
	local p = Data and Data.get(player)
	if not p then
		return false, FRIENDLY.NotLoaded
	end
	local Economy = require(Shared.Economy) :: any
	local ok, res = Economy.toggleShowcase(p, weaponId)
	if ok then
		Data.markDirty(player)
		return true, res
	end
	return false, FRIENDLY[res] or res
end
handlers[A.CollectCash] = function(player)
	return call("WorkshopService", "collect", player)
end
handlers[A.LockForge] = function(player)
	return call("WorkshopService", "lockForge", player)
end
handlers[A.StealBegin] = function(player, plot, slot)
	if not isInt(plot, 1, 6) or not isInt(slot, 1, 8) then
		return false, "Invalid podium"
	end
	return call("WorkshopService", "stealBegin", player, plot, slot)
end
handlers[A.StealCommit] = function(player, plot, slot)
	if not isInt(plot, 1, 6) or not isInt(slot, 1, 8) then
		return false, "Invalid podium"
	end
	return call("WorkshopService", "stealCommit", player, plot, slot)
end
handlers[A.StealCancel] = function(player)
	return call("WorkshopService", "stealCancel", player)
end
handlers[A.Hatch] = function(player, eggId, count)
	if type(eggId) ~= "string" or #eggId > 32 or not (count == 1 or count == 3 or count == 5) then
		return false, "Invalid hatch"
	end
	if not at(player, "Egg", eggId) then
		return false, "Walk to that egg first"
	end
	local ok, pets = call("CompanionService", "hatch", player, eggId, count)
	if ok then
		Remotes.push(player, Protocol.Push.Hatched, { pets = pets })
	end
	return ok, pets
end
handlers[A.EquipPet] = function(player, petId)
	if type(petId) ~= "string" or #petId > 64 then
		return false, "Invalid pet"
	end
	return call("CompanionService", "equip", player, petId)
end
handlers[A.UnequipPet] = function(player, petId)
	if type(petId) ~= "string" or #petId > 64 then
		return false, "Invalid pet"
	end
	return call("CompanionService", "unequip", player, petId)
end
handlers[A.EquipBestPets] = function(player)
	return call("CompanionService", "equipBest", player)
end
handlers[A.ReleasePet] = function(player, petId)
	if type(petId) ~= "string" or #petId > 64 then return false, "Invalid pet" end
	return call("CompanionService", "release", player, petId)
end
handlers[A.MergePet] = function(player, petId)
	if type(petId) ~= "string" or #petId > 64 then return false, "Invalid pet" end
	local ok, res = call("CompanionService", "merge", player, petId)
	if ok then
		Remotes.push(player, Protocol.Push.Merged, { pets = { res.pet } })
	end
	return ok, res
end
handlers[A.MergeAll] = function(player)
	local ok, res = call("CompanionService", "mergeAll", player)
	if ok then
		Remotes.push(player, Protocol.Push.Merged, { pets = res })
	end
	return ok, res
end
handlers[A.EvolutionStatus] = function(player)
	return call("EvolutionService", "status", player)
end
handlers[A.Evolve] = function(player, protected)
	if not at(player, "Altar") then
		return false, "Walk to the Evolution Altar first"
	end
	local Forge = svc("ForgeService")
	if Forge then
		safe(Forge.stopAuto, player, nil)
	end
	local ok, rank = call("EvolutionService", "evolve", player, protected == true)
	if ok then
		Remotes.push(player, Protocol.Push.Evolved, { rank = rank, protected = protected == true })
	end
	return ok, rank
end
local boardCache: { at: number, data: any } = { at = 0, data = {} }
handlers[A.Leaderboards] = function(_player)
	if boardCache.at > 0 and os.clock() - boardCache.at < 20 then
		return true, boardCache.data
	end
	local LB = svc("LeaderboardService")
	local data = {}
	data.scopes = {}
	if LB and LB.getTop then
		-- Client boards are keyed by profile field; LeaderboardService keys its stores by short names.
		local keys = { lifetimeCoins = "wealth", weaponsForged = "forged", evolutionRank = "evolutions", highestWeaponValue = "bestWeapon" }
		for field, key in keys do
			local ok, top = pcall(LB.getTop, key, 10)
			data.scopes[field] = RunService:IsStudio() and "Studio global" or "Global"
			if not ok or type(top) ~= "table" or #top == 0 then
				-- Global boards are unavailable in Studio or still warming up: show this server's ranking.
				ok, top = pcall(LB.getServerTop, key, 10)
				data.scopes[field] = "This server"
			end
			data[field] = ok and top or {}
		end
	end
	boardCache = { at = os.clock(), data = data }
	return true, data
end
handlers[A.Purchase] = function(player, key)
	if type(key) ~= "string" or #key > 48 then
		return false, "Invalid product"
	end
	return call("MonetizationService", "prompt", player, key)
end
handlers[A.DevGrant] = function(player, key)
	if not RunService:IsStudio() then
		return false, "Test entitlements only work in Studio"
	end
	if type(key) ~= "string" or #key > 48 then
		return false, "Invalid product"
	end
	return call("MonetizationService", "grantDev", player, key)
end
local SETTINGS = { music = "boolean", sfx = "boolean", vfx = "boolean" }
handlers[A.SetSetting] = function(player, key, value)
	if type(key) ~= "string" or SETTINGS[key] == nil or type(value) ~= SETTINGS[key] then
		return false, "Invalid setting"
	end
	local Data = svc("DataService")
	local p = Data and Data.get(player)
	if not p then
		return false, "Profile not loaded"
	end
	p.settings = p.settings or { music = true, sfx = true, vfx = true }
	p.settings[key] = value
	Data.markDirty(player)
	return true, nil
end
handlers[A.TutorialStep] = function(player, step)
	if not isInt(step, 0, 50) then
		return false, "Invalid step"
	end
	local Data = svc("DataService")
	local p = Data and Data.get(player)
	if not p then
		return false, "Profile not loaded"
	end
	if step > (p.tutorial or 0) then
		p.tutorial = step
		Data.markDirty(player)
	end
	return true, nil
end
handlers[A.Rates] = function(player)
	local snap = Remotes.snapshot(player)
	return snap ~= nil, snap and snap.rates
end
Remotes.handlers = handlers

--------------------------------------------------------------------------------

local RARITY_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local CLASS_NAMES = { "Sword", "Greatsword", "Axe", "Dagger", "Hammer" }
local lastAnnounce = 0

local function onForgeCompleted(player: Player, info: any)
	Remotes.push(player, Protocol.Push.ForgeResult, info)
	Remotes.markDirty(player)
	for _, result in info.results or {} do
		local weapon = result.weapon
		if weapon and (weapon.r or 0) >= 5 and os.clock() - lastAnnounce > 8 then
			lastAnnounce = os.clock()
			local Materials = config("Materials")
			local mat = Materials and Materials[weapon.m]
			local text = string.format("%s forged a %s %s %s!", player.DisplayName, RARITY_NAMES[weapon.r], mat and mat.name or "", CLASS_NAMES[weapon.c] or "weapon")
			Remotes.pushAll(Protocol.Push.Announce, { text = text, rarity = weapon.r })
		end
	end
end

function Remotes.init()
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	actionFn = Instance.new("RemoteFunction")
	actionFn.Name = "Action"
	actionFn.Parent = folder
	strikeEvent = Instance.new("RemoteEvent")
	strikeEvent.Name = "Strike"
	strikeEvent.Parent = folder
	push = Instance.new("RemoteEvent")
	push.Name = "Push"
	push.Parent = folder
	folder.Parent = ReplicatedStorage

	actionFn.OnServerInvoke = function(player: Player, name: any, ...: any)
		if type(name) ~= "string" then
			return false, "Bad request"
		end
		local handler = handlers[name]
		if not handler then
			return false, "Unknown action"
		end
		local times = lastAction[player]
		if not times then
			times = {}
			lastAction[player] = times
		end
		local now = os.clock()
		if times[name] and now - times[name] < MIN_INTERVAL then
			return false, "Slow down"
		end
		times[name] = now
		local ok, res = handler(player, ...)
		Remotes.markDirty(player)
		if RunService:IsStudio() then
			-- Studio-only trail of recent actions for acceptance diagnostics.
			table.insert(Remotes.studioLog, { player = player.UserId, action = name, ok = ok, result = if type(res) == "string" then res else nil, at = os.clock() })
			if #Remotes.studioLog > 50 then
				table.remove(Remotes.studioLog, 1)
			end
		end
		return ok, res
	end

	if RunService:IsStudio() then
		-- Studio-only test bridge so MCP/command-bar scripts can drive real profiles (never exists live).
		local ServerStorage = game:GetService("ServerStorage")
		local old = ServerStorage:FindFirstChild("DevBridge")
		if old then
			old:Destroy()
		end
		local bridge = Instance.new("BindableFunction")
		bridge.Name = "DevBridge"
		bridge.OnInvoke = function(cmd: string, userId: number?, ...: any)
			local player = userId and Players:GetPlayerByUserId(userId) or Players:GetPlayers()[1]
			local Data = svc("DataService")
			local p = player and Data and Data.get(player)
			if not p then
				return nil
			end
			local args = { ... }
			if cmd == "profile" then
				return p
			elseif cmd == "set" then
				p[args[1]] = args[2]
			elseif cmd == "add" then
				p[args[1]] = (p[args[1]] or 0) + args[2]
			elseif cmd == "ingots" then
				p.ingots[args[1]] = args[2]
			elseif cmd == "snapshot" then
				lastWeaponsKey[player] = nil
				local snap = Remotes.snapshot(player)
				lastWeaponsKey[player] = nil -- the next real push still carries the list
				return snap
			elseif cmd == "action" then
				local handler = handlers[args[1]]
				if not handler then return false, "Unknown action" end
				local ok, result = handler(player, table.unpack(args, 2))
				Remotes.markDirty(player)
				return ok, result
			elseif cmd == "save" then
				return Data.saveNow(player, 20), Data.getStatus(player)
			elseif cmd == "status" then
				return Data.getStatus(player)
			elseif cmd == "reconcile" then
				local Economy = require(Shared.Economy) :: any
				Economy.reconcile(p)
			elseif cmd == "revoke" then
				local Monet = svc("MonetizationService")
				local ok, result = Monet.revokeDev(player, args[1])
				Remotes.markDirty(player)
				return ok, result
			end
			Data.markDirty(player)
			return true
		end
		bridge.Parent = ServerStorage
	end

	strikeEvent.OnServerEvent:Connect(function(player: Player, sessionId: any)
		if type(sessionId) ~= "string" or #sessionId > 64 then
			return
		end
		local Forge = svc("ForgeService")
		if Forge and Forge.strike then
			Forge.strike(player, sessionId)
		end
	end)
end

function Remotes.start()
	local Data = svc("DataService")
	if Data and Data.profileChanged then
		local ev: any = Data.profileChanged
		local signal = ev.Event or ev
		signal:Connect(function(player: Player)
			dirty[player] = true
		end)
	end
	local Forge = svc("ForgeService")
	if Forge and Forge.completed then
		Forge.completed.Event:Connect(onForgeCompleted)
	end
	if Forge and Forge.stopped then
		Forge.stopped.Event:Connect(function(player: Player, station: any, reason: any)
			dirty[player] = true
			local msg = ({ InventoryFull = "Auto Forge stopped: backpack full", ProgressReset = "Auto Forge stopped" })[tostring(reason)]
			if msg then
				Remotes.toast(player, msg, "info")
			end
		end)
	end
	if Forge and Forge.phase then
		Forge.phase.Event:Connect(function(player: Player, info: any)
			Remotes.push(player, Protocol.Push.ForgePhase, info)
			dirty[player] = true
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		lastAction[player] = nil
		session[player] = nil
		lastWeaponsKey[player] = nil
	end)
	-- Snapshot replication loop (~4 Hz, only for changed players; full resync every 2 s for ticking resources).
	local tick = 0
	while true do
		task.wait(0.25)
		tick += 1
		for _, player in Players:GetPlayers() do
			if dirty[player] or tick % 8 == 0 then
				dirty[player] = nil
				local snap = Remotes.snapshot(player)
				if snap then
					Remotes.push(player, Protocol.Push.Profile, snap)
				end
			end
		end
	end
end

return Remotes
