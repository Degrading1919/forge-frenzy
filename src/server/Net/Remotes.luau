--!strict
-- Network glue (Studio thread owns this). Creates ReplicatedStorage.Remotes, maps Protocol actions onto
-- the gameplay services, and replicates profile snapshots (docs/17_CLIENT_SNAPSHOT.md).
-- This is the single adapter to adjust when service APIs change.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Protocol = require(Shared.Protocol)
local A = Protocol.Actions

local Remotes = {}

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

local folder: Folder
local push: RemoteEvent
local strikeEvent: RemoteEvent
local actionFn: RemoteFunction

local dirty: { [Player]: boolean } = {}
local lastAction: { [Player]: { [string]: number } } = {}
local session: { [Player]: { autoMode: string, settings: any, plotIndex: number } } = {}

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
		s = { autoMode = "off", settings = nil, plotIndex = 0 }
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

-- Builds the replicated snapshot from the authoritative profile.
function Remotes.snapshot(player: Player): any?
	local Data = svc("DataService")
	local p = Data and Data.get(player)
	if not p then
		return nil
	end
	local Production, Upgrade, Monet, Evo = svc("ProductionService"), svc("UpgradeService"), svc("MonetizationService"), svc("EvolutionService")
	local Products = config("Products")
	local weapons = {}
	for _, w in p.weapons or {} do
		table.insert(weapons, w)
	end
	table.sort(weapons, function(a, b)
		return (a.v or 0) > (b.v or 0)
	end)
	local pets = {}
	for id, pet in p.pets or {} do
		table.insert(pets, { id = pet.id or id, kind = pet.kind or pet.k })
	end
	local showcase = {}
	for i = 1, 6 do
		showcase[i] = (p.showcase and p.showcase[i]) or ""
	end
	local upgradeCosts = {}
	for _, t in MACHINE_TRACKS do
		upgradeCosts[t] = Upgrade and safe(Upgrade.cost, player, t) or false
	end
	for _, t in GEAR_TRACKS do
		upgradeCosts[t] = Upgrade and safe(Upgrade.cost, player, t) or false
	end
	local rates = Production and safe(Production.rates, player) or {}
	local Forge = svc("ForgeService")
	local timings = Forge and safe(Forge.timings, player) or {}
	local s = Remotes.session(player)
	local entitlements = {}
	for k, v in p.entitlements or {} do
		entitlements[k] = v and true or false
	end
	if Monet and Products then
		for key in Products do
			if type(key) == "string" and key ~= "LIVE" and safe(Monet.owns, player, key) then
				entitlements[key] = true
			end
		end
	end
	return {
		coins = p.coins or 0,
		lifetimeCoins = p.lifetimeCoins or 0,
		weaponsForged = p.weaponsForged or 0,
		highestWeaponValue = p.highestWeaponValue or 0,
		selectedMaterial = p.selectedMaterial or 1,
		unlockedTier = p.unlockedTier or 1,
		ore = toArray(p.ore, MATERIAL_COUNT),
		ingots = toArray(p.ingots, MATERIAL_COUNT),
		levels = p.levels or {},
		gear = p.gear or {},
		costs = {
			upgrades = upgradeCosts,
			unlockNext = Production and safe(Production.unlockCost, player) or false,
		},
		weapons = weapons,
		pending = p.pending,
		showcase = showcase,
		journal = toArray(p.journal, MATERIAL_COUNT),
		pets = pets,
		equipped = p.equipped or {},
		petSlots = p.petSlots or 2,
		evolutionRank = p.evolutionRank or 0,
		forgedSinceEvolve = p.forgedSinceEvolve or 0,
		highestTierSinceEvolve = p.highestTierSinceEvolve or 1,
		entitlements = entitlements,
		settings = p.settings or { autoSellBelow = 0, music = true, sfx = true, vfx = true },
		tutorial = p.tutorial or 0,
		rates = {
			orePerSec = rates.orePerSec or 0,
			ingotPerSec = rates.ingotPerSec or 0,
			capacity = rates.capacity or 30,
			heatSec = timings.heatSec or 2,
			windowSec = timings.windowSec or 6,
			revealSec = timings.revealSec or 1.5,
		},
		autoMode = s.autoMode,
		plotIndex = s.plotIndex,
		isStudio = RunService:IsStudio(),
		productsLive = Products ~= nil and Products.LIVE == true,
		paidRandomAllowed = Monet == nil or (safe(Monet.canOfferPaidRandom, player) ~= false),
		evolutionEligible = Evo and (safe(function()
			local st = Evo.status(player)
			return st and st.eligible
		end) or false) or false,
	}
end

--------------------------------------------------------------------------------
-- Action handlers: each returns (ok, result)
--------------------------------------------------------------------------------

local MIN_INTERVAL = 0.08 -- per-action spam guard (seconds)

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
		return a, b
	end
	return true, a
end

local function isInt(n: any, lo: number, hi: number): boolean
	return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi
end

local handlers: { [string]: (Player, ...any) -> (boolean, any) } = {}

handlers[A.ForgeStart] = function(player, classIndex, materialIndex, mode)
	if not isInt(classIndex, 1, 5) or not isInt(materialIndex, 1, MATERIAL_COUNT) then
		return false, "Invalid recipe"
	end
	if mode ~= "manual" and mode ~= "free" and mode ~= "premium" then
		return false, "Invalid mode"
	end
	local ok, res = call("ForgeService", "start", player, classIndex, materialIndex, mode)
	if ok then
		Remotes.session(player).autoMode = mode == "manual" and "off" or mode
	end
	return ok, res
end
handlers[A.ForgeResolve] = function(player, action)
	if action ~= "sell" and action ~= "keep" then
		return false, "Invalid choice"
	end
	return call("ForgeService", "resolve", player, action)
end
handlers[A.ForgeStopAuto] = function(player)
	Remotes.session(player).autoMode = "off"
	return call("ForgeService", "stopAuto", player)
end
handlers[A.SelectMaterial] = function(player, index)
	if not isInt(index, 1, MATERIAL_COUNT) then
		return false, "Invalid material"
	end
	return call("ProductionService", "selectMaterial", player, index)
end
handlers[A.UnlockMaterial] = function(player)
	return call("ProductionService", "unlockNextMaterial", player)
end
handlers[A.BuyUpgrade] = function(player, track)
	if type(track) ~= "string" or (not table.find(MACHINE_TRACKS, track) and not table.find(GEAR_TRACKS, track)) then
		return false, "Invalid upgrade"
	end
	return call("UpgradeService", "buy", player, track)
end
handlers[A.SellWeapon] = function(player, weaponId)
	if type(weaponId) ~= "string" or #weaponId > 64 then
		return false, "Invalid weapon"
	end
	return call("ForgeService", "sellKept", player, weaponId)
end
handlers[A.SetShowcase] = function(player, slot, weaponId)
	if not isInt(slot, 1, 6) or (weaponId ~= nil and (type(weaponId) ~= "string" or #weaponId > 64)) then
		return false, "Invalid showcase"
	end
	local Data = svc("DataService")
	local p = Data and Data.get(player)
	if not p then
		return false, "Profile not loaded"
	end
	if weaponId and weaponId ~= "" then
		if not (p.weapons and p.weapons[weaponId]) then
			return false, "You don't own that weapon"
		end
		for i = 1, 6 do -- a weapon can only stand on one pedestal
			if p.showcase and p.showcase[i] == weaponId then
				p.showcase[i] = ""
			end
		end
	end
	p.showcase = p.showcase or {}
	for i = 1, 6 do
		p.showcase[i] = p.showcase[i] or ""
	end
	p.showcase[slot] = weaponId or ""
	Data.markDirty(player)
	return true, nil
end
handlers[A.Hatch] = function(player, eggId, count)
	if type(eggId) ~= "string" or #eggId > 32 or not (count == 1 or count == 3 or count == 5) then
		return false, "Invalid hatch"
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
handlers[A.EvolutionStatus] = function(player)
	return call("EvolutionService", "status", player)
end
handlers[A.Evolve] = function(player, protected)
	local ok, rank = call("EvolutionService", "evolve", player, protected == true)
	if ok then
		Remotes.push(player, Protocol.Push.Evolved, { rank = rank, protected = protected == true })
	end
	return ok, rank
end
local boardCache: { at: number, data: any } = { at = 0, data = {} }
handlers[A.Leaderboards] = function(_player)
	if os.clock() - boardCache.at < 20 then
		return true, boardCache.data
	end
	local LB = svc("LeaderboardService")
	local data = {}
	if LB and LB.getTop then
		for _, metric in { "lifetimeCoins", "weaponsForged", "evolutionRank", "highestWeaponValue" } do
			local ok, top = pcall(LB.getTop, metric, 10)
			data[metric] = ok and top or {}
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
local SETTINGS = { autoSellBelow = "number", music = "boolean", sfx = "boolean", vfx = "boolean" }
handlers[A.SetSetting] = function(player, key, value)
	if type(key) ~= "string" or SETTINGS[key] == nil or type(value) ~= SETTINGS[key] then
		return false, "Invalid setting"
	end
	if key == "autoSellBelow" and not isInt(value, 0, 6) then
		return false, "Invalid setting"
	end
	local Data = svc("DataService")
	local p = Data and Data.get(player)
	if not p then
		return false, "Profile not loaded"
	end
	p.settings = p.settings or { autoSellBelow = 0, music = true, sfx = true, vfx = true }
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

--------------------------------------------------------------------------------

local RARITY_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local CLASS_NAMES = { "Sword", "Greatsword", "Axe", "Dagger", "Hammer" }
local lastAnnounce = 0

local function onForgeCompleted(player: Player, weapon: any, luck: number, auto: boolean?, strikes: number?)
	Remotes.push(player, Protocol.Push.ForgeResult, { weapon = weapon, luck = luck, strikes = strikes or 0, auto = auto == true })
	Remotes.markDirty(player)
	if weapon and (weapon.r or 0) >= 5 and os.clock() - lastAnnounce > 8 then
		lastAnnounce = os.clock()
		local Materials = config("Materials")
		local mat = Materials and Materials[weapon.m]
		local text = string.format("%s forged a %s %s %s!", player.DisplayName, RARITY_NAMES[weapon.r], mat and mat.name or "", CLASS_NAMES[weapon.c] or "weapon")
		Remotes.pushAll(Protocol.Push.Announce, { text = text, rarity = weapon.r })
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
		return ok, res
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
		local ev: any = Forge.completed
		local signal = ev.Event or ev
		signal:Connect(onForgeCompleted)
	end
	if Forge and Forge.phase then
		local ev: any = Forge.phase
		local signal = ev.Event or ev
		signal:Connect(function(player: Player, info: any)
			Remotes.push(player, Protocol.Push.ForgePhase, info)
			if info and (info.phase == "cancelled" or info.phase == "stopped") then
				Remotes.session(player).autoMode = "off"
				dirty[player] = true
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		lastAction[player] = nil
		session[player] = nil
	end)
	-- Snapshot replication loop (~4 Hz, only for changed players; full resync every 5 s for ticking resources).
	local tick = 0
	while true do
		task.wait(0.25)
		tick += 1
		for _, player in Players:GetPlayers() do
			if dirty[player] or tick % 20 == 0 then
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
