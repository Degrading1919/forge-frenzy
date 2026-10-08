--!strict
--[[
	CompanionService: server-owned Forge Companion inventory, egg hatching, equipping and
	bonuses. No remotes or UI; the Studio thread maps remotes onto these functions.

	Profile fields owned here:
	  pets      { [petId]: Pet }       Pet = { id, k (kind id), ts, src? ("dev" for Studio grants) }
	  equipped  { petId }              at most `slotsFor(profile)` entries
	  petSlots  number                 cached slot count for the client
	  petSerial number                 monotonically increasing id counter (ids never reused)
	Read-only profile fields: coins (spent on eggs), unlockedTier, highestTierEver,
	evolutionRank.

	Player-level functions return (ok, resultOrError). `CompanionService.Logic` holds the
	same operations on a bare profile table so they are testable without Studio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Companions = require(Config:WaitForChild("Companions"))
local Eggs = require(Config:WaitForChild("Eggs"))

export type Pet = { id: string, k: string, ts: number, src: string? }
export type Bonuses = { extract: number, smelt: number, prep: number, storage: number }

local CompanionService = {}
local Logic = {}
CompanionService.Logic = Logic

-- Dependencies wired in init(); tests replace them through CompanionService._inject.
local deps = {
	getProfile = function(_player: any): any
		return nil
	end,
	markDirty = function(_player: any) end,
	ownsPass = function(_player: any, _key: string): boolean
		return false
	end,
	paidRandomAllowed = function(_player: any): boolean
		return false
	end,
	clock = os.clock,
	now = os.time,
	isStudio = function(): boolean
		return false
	end,
}
local rng: any = nil
local lastHatchAt: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any

local function dataOf(player: any): any
	local profile = deps.getProfile(player)
	if type(profile) ~= "table" then
		return nil
	end
	return if type(profile.Data) == "table" then profile.Data else profile
end

--------------------------------------------------------------------------------
-- Pure profile logic
--------------------------------------------------------------------------------

-- Fill in this service's fields on a profile that predates them; drop dangling equips.
function Logic.ensure(profile: any)
	if type(profile.pets) ~= "table" then
		profile.pets = {}
	end
	if type(profile.equipped) ~= "table" then
		profile.equipped = {}
	end
	if type(profile.petSerial) ~= "number" or profile.petSerial ~= profile.petSerial or profile.petSerial < 0 or profile.petSerial == math.huge then
		profile.petSerial = 0
	end
	profile.petSerial = math.min(2 ^ 53 - 1, math.floor(profile.petSerial))
	-- Recover the counter in migrated saves before any hatch/grant can reuse an owned ID.
	for id, pet in profile.pets do
		for _, candidate in { id, if type(pet) == "table" then pet.id else nil } do
			local serial = if type(candidate) == "string" then tonumber(candidate:match("^p(%d+)$")) else nil
			if serial and serial < 2 ^ 53 then profile.petSerial = math.max(profile.petSerial, serial) end
		end
	end
	local seen = {}
	for i = #profile.equipped, 1, -1 do
		local id = profile.equipped[i]
		if profile.pets[id] == nil or seen[id] then
			table.remove(profile.equipped, i)
		else
			seen[id] = true
		end
	end
	profile.petSlots = Logic.slotsFor(profile)
	while #profile.equipped > profile.petSlots do
		table.remove(profile.equipped)
	end
end

function Logic.slotsFor(profile: any): number
	local slots = Companions.BaseSlots
	if (profile.evolutionRank or 0) >= Companions.EarnedSlotAtEvolutionRank then
		slots += 1
	end
	return math.min(slots, Companions.MaxSlots)
end

function Logic.petCount(profile: any): number
	local n = 0
	for _ in profile.pets do
		n += 1
	end
	return n
end

local function newPet(profile: any, kindId: string, now: number, src: string?): Pet
	repeat
		profile.petSerial = if profile.petSerial >= 2 ^ 53 - 1 then 1 else profile.petSerial + 1
	until profile.pets["p" .. profile.petSerial] == nil
	local pet: Pet = { id = "p" .. profile.petSerial, k = kindId, ts = now, src = src }
	profile.pets[pet.id] = pet
	return pet
end

-- Weighted pick from an egg. `roll` is in [0, 1).
function Logic.pickKind(egg: Eggs.Egg, roll: number): string
	local total = 0
	for _, entry in egg.kinds do
		total += entry.weight
	end
	local target = roll * total
	for _, entry in egg.kinds do
		target -= entry.weight
		if target < 0 then
			return entry.kind
		end
	end
	return egg.kinds[#egg.kinds].kind
end

function Logic.eggUnlocked(profile: any, egg: Eggs.Egg, now: number): (boolean, string?)
	local tier = math.max(profile.unlockedTier or 1, profile.highestTierEver or 1)
	if tier < egg.unlockTier then
		return false, "egg locked"
	end
	if egg.availableFrom and now < egg.availableFrom then
		return false, "egg not available yet"
	end
	if egg.availableUntil and now >= egg.availableUntil then
		return false, "egg no longer available"
	end
	return true, nil
end

--[[
	opts = { multiHatch: boolean, rng: Random, now: number }
	Validates everything before mutating, so a failed hatch changes nothing.
]]
function Logic.hatch(profile: any, eggId: any, count: any, opts: any): (boolean, any)
	Logic.ensure(profile)
	if type(eggId) ~= "string" then
		return false, "bad egg"
	end
	local egg = Eggs.ById[eggId]
	if egg == nil then
		return false, "unknown egg"
	end
	if count == nil then
		count = 1
	end
	if count ~= 1 and count ~= 3 and count ~= 5 then
		return false, "bad count"
	end
	if count > 1 and not opts.multiHatch then
		return false, "multi-hatch not owned"
	end
	local unlocked, why = Logic.eggUnlocked(profile, egg, opts.now)
	if not unlocked then
		return false, why
	end
	if Logic.petCount(profile) + count > Companions.InventoryCapacity then
		return false, "inventory full"
	end
	local cost = egg.coinCost * count
	local coins = profile.coins
	if type(coins) ~= "number" or coins ~= coins or coins < cost then
		return false, "not enough coins"
	end

	profile.coins = coins - cost
	local hatched = {}
	for _ = 1, count do
		local kindId = Logic.pickKind(egg, opts.rng:NextNumber())
		table.insert(hatched, newPet(profile, kindId, opts.now))
	end
	return true, hatched
end

local function bonusTotal(kindId: string): number
	local kind = Companions.ById[kindId]
	local total = 0
	if kind then
		for _, v in kind.bonus do
			total += v
		end
	end
	return total
end

function Logic.equip(profile: any, petId: any): (boolean, any)
	Logic.ensure(profile)
	if type(petId) ~= "string" or profile.pets[petId] == nil then
		return false, "not owned"
	end
	if table.find(profile.equipped, petId) then
		return false, "already equipped"
	end
	if #profile.equipped >= profile.petSlots then
		return false, "no free slot"
	end
	table.insert(profile.equipped, petId)
	return true, profile.equipped
end

function Logic.unequip(profile: any, petId: any): (boolean, any)
	Logic.ensure(profile)
	local index = if type(petId) == "string" then table.find(profile.equipped, petId) else nil
	if index == nil then
		return false, "not equipped"
	end
	table.remove(profile.equipped, index)
	return true, profile.equipped
end

-- Equip the strongest companions by summed bonus. Convenience for the UI.
function Logic.equipBest(profile: any): (boolean, any)
	Logic.ensure(profile)
	local ids = {}
	for id in profile.pets do
		table.insert(ids, id)
	end
	table.sort(ids, function(a: string, b: string)
		local ta, tb = bonusTotal(profile.pets[a].k), bonusTotal(profile.pets[b].k)
		if ta ~= tb then
			return ta > tb
		end
		return a < b
	end)
	table.clear(profile.equipped)
	for i = 1, math.min(profile.petSlots, #ids) do
		profile.equipped[i] = ids[i]
	end
	return true, profile.equipped
end

-- Permanently remove a companion (frees inventory space). Premium companions cannot go.
function Logic.release(profile: any, petId: any): (boolean, any)
	Logic.ensure(profile)
	local pet = if type(petId) == "string" then profile.pets[petId] else nil
	if pet == nil then
		return false, "not owned"
	end
	local kind = Companions.ById[pet.k]
	if kind and kind.premium then
		return false, "premium companions cannot be released"
	end
	local index = table.find(profile.equipped, petId)
	if index then
		table.remove(profile.equipped, index)
	end
	profile.pets[petId] = nil
	return true, petId
end

-- Grant a specific kind (premium pass/product). With `unique`, a second grant is a no-op,
-- which makes re-running a pass grant on every join safe.
function Logic.grantKind(profile: any, kindId: string, opts: any?): (boolean, any)
	Logic.ensure(profile)
	if Companions.ById[kindId] == nil then
		return false, "unknown kind"
	end
	local o = opts or {}
	if o.unique then
		for _, pet in profile.pets do
			if pet.k == kindId then
				return true, pet
			end
		end
	end
	-- Purchased companions bypass the inventory cap: a paid grant must never be refused.
	return true, newPet(profile, kindId, o.now or 0, o.src)
end

-- Remove companions granted by Studio dev-test mode. Called on load outside Studio so a
-- test grant can never leak into live data.
function Logic.stripDevGrants(profile: any): number
	Logic.ensure(profile)
	local removed = 0
	for id, pet in profile.pets do
		if pet.src == "dev" then
			profile.pets[id] = nil
			removed += 1
		end
	end
	Logic.ensure(profile)
	return removed
end

-- Additive per family from equipped companions, each family capped at Companions.FamilyCap.
function Logic.bonuses(profile: any): Bonuses
	Logic.ensure(profile)
	local out: { [string]: number } = { extract = 0, smelt = 0, prep = 0, storage = 0 }
	for _, petId in profile.equipped do
		local kind = Companions.ById[profile.pets[petId].k]
		if kind then
			for family, value in kind.bonus do
				out[family] += value
			end
		end
	end
	for family, value in out do
		out[family] = math.min(value, Companions.FamilyCap)
	end
	return out :: any
end

--------------------------------------------------------------------------------
-- Player-level API (what remotes map onto)
--------------------------------------------------------------------------------

local function withProfile(player: any, fn: (any) -> (boolean, any)): (boolean, any)
	local profile = dataOf(player)
	if profile == nil then
		return false, "profile not loaded"
	end
	local ok, result = fn(profile)
	if ok then
		deps.markDirty(player)
	end
	return ok, result
end

function CompanionService.hatch(player: any, eggId: any, count: any): (boolean, any)
	if count ~= nil and count ~= 1 and not deps.paidRandomAllowed(player) then
		return false, "PaidRandomRestricted"
	end
	local t = deps.clock()
	local last = lastHatchAt[player]
	if last and t - last < Companions.HatchCooldownSec then
		return false, "hatching too fast"
	end
	if rng == nil then
		rng = Random.new()
	end
	local ok, result = withProfile(player, function(profile)
		return Logic.hatch(profile, eggId, count, {
			multiHatch = count ~= 1 and count ~= nil and deps.ownsPass(player, "MultiHatch"),
			rng = rng,
			now = deps.now(),
		})
	end)
	if ok then
		lastHatchAt[player] = t
	end
	return ok, result
end

function CompanionService.equip(player: any, petId: any): (boolean, any)
	return withProfile(player, function(profile)
		return Logic.equip(profile, petId)
	end)
end

function CompanionService.unequip(player: any, petId: any): (boolean, any)
	return withProfile(player, function(profile)
		return Logic.unequip(profile, petId)
	end)
end

function CompanionService.equipBest(player: any): (boolean, any)
	return withProfile(player, Logic.equipBest)
end

function CompanionService.release(player: any, petId: any): (boolean, any)
	return withProfile(player, function(profile)
		return Logic.release(profile, petId)
	end)
end

function CompanionService.grantKind(player: any, kindId: string, src: string?): (boolean, any)
	return withProfile(player, function(profile)
		return Logic.grantKind(profile, kindId, { unique = true, now = deps.now(), src = src })
	end)
end

function CompanionService.bonuses(player: any): Bonuses
	local profile = dataOf(player)
	if profile == nil then
		return { extract = 0, smelt = 0, prep = 0, storage = 0 }
	end
	return Logic.bonuses(profile)
end

-- Exact egg odds for the disclosure UI.
function CompanionService.odds(eggId: string)
	return Eggs.odds(eggId)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function CompanionService._inject(overrides: { [string]: any })
	for key, value in overrides do
		(deps :: any)[key] = value
	end
	if overrides.rng then
		rng = overrides.rng
	end
	table.clear(lastHatchAt)
end

function CompanionService.init()
	local DataService = require(script.Parent:WaitForChild("DataService")) :: any
	local RunService = game:GetService("RunService")
	deps.getProfile = function(player)
		return DataService.get(player)
	end
	deps.markDirty = function(player)
		DataService.markDirty(player)
	end
	deps.isStudio = function()
		return RunService:IsStudio()
	end
	deps.ownsPass = function(player, key)
		local found = script.Parent:FindFirstChild("MonetizationService")
		return found ~= nil and (require(found) :: any).owns(player, key) == true
	end
	deps.paidRandomAllowed = function(player)
		local found = script.Parent:FindFirstChild("MonetizationService")
		return found ~= nil and (require(found) :: any).canOfferPaidRandom(player) == true
	end
end

function CompanionService.start()
	local DataService = require(script.Parent:WaitForChild("DataService")) :: any
	local Players = game:GetService("Players")
	local function prepare(player: Player)
		local profile = DataService.waitFor(player)
		local data = if profile and type(profile.Data) == "table" then profile.Data else profile
		if data == nil then
			return
		end
		if not deps.isStudio() then
			Logic.stripDevGrants(data)
		end
		Logic.ensure(data)
		DataService.markDirty(player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(prepare, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(prepare, player)
	end
end

return CompanionService
