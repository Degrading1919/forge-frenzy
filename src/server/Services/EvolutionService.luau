--!strict
--[[
	EvolutionService: Blacksmith Evolution (rebirth), normal and protected.

	Profile fields owned here:
	  evolutionRank    number
	  evolveBaseline   { weaponsForged, lifetimeCoins, unlockedTier } snapshot taken right
	                   after the last evolution; "since last evolution" progress is measured
	                   against it, so no other service has to maintain extra counters
	  highestTierEver  number  highest extractor tier ever unlocked (kept for egg access)
	  evolveCharges    number  Protected Evolution charges bought as a dev product
	  evolveLog        { { rank, at, protected } }  last few evolutions, for support/debug
	Read-only: weaponsForged, lifetimeCoins, unlockedTier (core economy thread).
	Reset on a normal evolution: the fields in Config.Evolution.Resets.

	One eligibility predicate serves both paths (docs/13): fresh forges since the last
	evolution and a fresh tier milestone, where retained coins and a retained extractor never
	count. That is what stops a protected evolution from chaining into another.

	Atomicity: evolve() validates first and then mutates the profile without yielding, so the
	in-memory profile (and therefore the saved document) is either fully before or fully
	after the evolution. A repeated request fails eligibility because progress was re-based.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Evolution = require(Config:WaitForChild("Evolution"))

local EvolutionService = {}
local Logic = {}
EvolutionService.Logic = Logic

local LOG_LIMIT = 20

local deps = {
	getProfile = function(_player: any): any
		return nil
	end,
	markDirty = function(_player: any) end,
	now = os.time,
}

local function dataOf(player: any): any
	local profile = deps.getProfile(player)
	if type(profile) ~= "table" then
		return nil
	end
	return if type(profile.Data) == "table" then profile.Data else profile
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

-- Cumulative coin cost to unlock tiers 2..t. Prefers Config.Materials once it exists.
local cumulativeCost: { number }? = nil
local function cumulativeCosts(): { number }
	if cumulativeCost then
		return cumulativeCost
	end
	local costs = Evolution.FallbackUnlockCosts
	local materialsModule = Config:FindFirstChild("Materials")
	if materialsModule then
		local ok, materials = pcall(require, materialsModule)
		if ok and type(materials) == "table" and #materials >= 32 and type(materials[2].unlockCost) == "number" then
			costs = {}
			for i, material in materials do
				costs[i] = material.unlockCost
			end
		end
	end
	local out, sum = {}, 0
	for t = 1, #costs do
		sum += if t == 1 then 0 else costs[t]
		out[t] = sum
	end
	cumulativeCost = out
	return out
end

-- Starting values come from the core schema (Shared.Economy.newProfile) when it exists, so a
-- reset produces exactly what a new player has (dense ore/ingot arrays, starter ingots, track
-- levels). Config.Evolution.Resets values are the fallback.
local function economyModule(): any
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local economy = shared and shared:FindFirstChild("Economy")
	if economy == nil then
		return nil
	end
	local ok, module = pcall(require, economy)
	return if ok and type(module) == "table" then module else nil
end

local function freshProfile(): any
	local module = economyModule()
	if not module or type(module.newProfile) ~= "function" then
		return nil
	end
	local okProfile, profile = pcall(module.newProfile)
	return if okProfile and type(profile) == "table" then profile else nil
end

function Logic.ensure(profile: any)
	if type(profile.evolutionRank) ~= "number" then
		profile.evolutionRank = 0
	end
	if type(profile.evolveCharges) ~= "number" then
		profile.evolveCharges = 0
	end
	if type(profile.evolveLog) ~= "table" then
		profile.evolveLog = {}
	end
	if type(profile.evolveBaseline) ~= "table" then
		-- First sight of this profile: everything so far counts as fresh progress.
		profile.evolveBaseline = { weaponsForged = 0, lifetimeCoins = 0, unlockedTier = 1 }
	end
	profile.highestTierEver = math.max(profile.highestTierEver or 1, profile.unlockedTier or 1)
end

-- Highest tier whose cumulative unlock cost is covered by `coins`.
function Logic.tierForCoins(coins: number): number
	local costs = cumulativeCosts()
	local tier = 1
	for t = 2, #costs do
		if coins >= costs[t] then
			tier = t
		else
			break
		end
	end
	return tier
end

function Logic.progress(profile: any): { forged: number, tier: number, coinsEarned: number }
	Logic.ensure(profile)
	local base = profile.evolveBaseline
	local forged = math.max(0, (profile.weaponsForged or 0) - (base.weaponsForged or 0))
	local earned = math.max(0, (profile.lifetimeCoins or 0) - (base.lifetimeCoins or 0))
	local current = profile.unlockedTier or 1
	-- v2: the tier goal is literal ("Unlock Gold"), which a young player can read. Only a
	-- material bought since the last evolution counts, so a protected evolution that kept a
	-- high tier cannot immediately qualify again.
	local unlockedFresh = if current > (base.unlockedTier or 1) or (base.unlockedTier or 1) <= 1 then current else 1
	return {
		forged = forged,
		tier = unlockedFresh,
		coinsEarned = earned,
	}
end

function Logic.requirements(rank: number): { forged: number, tier: number }
	return { forged = Evolution.forgeRequirement(rank), tier = Evolution.tierRequirement(rank) }
end

-- The single eligibility predicate for both paths.
function Logic.eligible(profile: any): boolean
	local progress = Logic.progress(profile)
	local need = Logic.requirements(profile.evolutionRank)
	return progress.forged >= need.forged and progress.tier >= need.tier
end

function Logic.bonuses(rank: number): { production: number, prep: number, cash: number }
	return {
		production = rank * Evolution.ProductionPerRank,
		prep = rank * Evolution.PrepPerRank,
		cash = Evolution.cashMultiplier(rank),
	}
end

function Logic.status(profile: any)
	Logic.ensure(profile)
	local rank = profile.evolutionRank
	local resets = {}
	for _, entry in Evolution.Resets do
		table.insert(resets, entry.label)
	end
	return {
		rank = rank,
		eligible = Logic.eligible(profile),
		requirements = Logic.requirements(rank),
		progress = Logic.progress(profile),
		protectedCharges = profile.evolveCharges,
		bonuses = Logic.bonuses(rank),
		nextBonuses = Logic.bonuses(rank + 1),
		preview = {
			normal = { keeps = Evolution.Keeps, resets = resets },
			protected = { keeps = Evolution.Keeps, resets = {} },
		},
	}
end

function Logic.evolve(profile: any, protected: boolean, now: number): (boolean, any)
	Logic.ensure(profile)
	if not Logic.eligible(profile) then
		return false, "not eligible"
	end
	if protected and profile.evolveCharges < 1 then
		return false, "no protected evolution charge"
	end

	-- No yields from here on.
	if protected then
		profile.evolveCharges -= 1
	else
		profile.highestTierEver = math.max(profile.highestTierEver, profile.unlockedTier or 1)
		local fresh = freshProfile()
		for _, entry in Evolution.Resets do
			local value = if fresh and fresh[entry.field] ~= nil then fresh[entry.field] else entry.value
			profile[entry.field] = deepCopy(value)
		end
		-- Re-fit ore lines/forges to the (kept) build pads and repair the reset fields.
		local module = economyModule()
		if module and type(module.reconcile) == "function" then
			module.reconcile(profile)
		end
	end
	profile.evolutionRank += 1
	profile.evolveBaseline = {
		weaponsForged = profile.weaponsForged or 0,
		lifetimeCoins = profile.lifetimeCoins or 0,
		unlockedTier = profile.unlockedTier or 1,
	}
	table.insert(profile.evolveLog, { rank = profile.evolutionRank, at = now, protected = protected })
	while #profile.evolveLog > LOG_LIMIT do
		table.remove(profile.evolveLog, 1)
	end
	return true, profile.evolutionRank
end

--------------------------------------------------------------------------------
-- Player-level API
--------------------------------------------------------------------------------

function EvolutionService.status(player: any): (boolean, any)
	local profile = dataOf(player)
	if profile == nil then
		return false, "profile not loaded"
	end
	return true, Logic.status(profile)
end

function EvolutionService.evolve(player: any, protected: any): (boolean, any)
	local profile = dataOf(player)
	if profile == nil then
		return false, "profile not loaded"
	end
	local ok, result = Logic.evolve(profile, protected == true, deps.now())
	if ok then
		deps.markDirty(player)
	end
	return ok, result
end

function EvolutionService.bonuses(player: any): { production: number, prep: number, cash: number }
	local profile = dataOf(player)
	return Logic.bonuses(if profile then profile.evolutionRank or 0 else 0)
end

-- Used by MonetizationService when a Protected Evolution product is purchased.
function Logic.addCharges(profile: any, n: number)
	Logic.ensure(profile)
	profile.evolveCharges += n
end

function EvolutionService._inject(overrides: { [string]: any })
	for key, value in overrides do
		(deps :: any)[key] = value
	end
	cumulativeCost = nil
end

function EvolutionService.init()
	local DataService = require(script.Parent:WaitForChild("DataService")) :: any
	deps.getProfile = function(player)
		return DataService.get(player)
	end
	deps.markDirty = function(player)
		DataService.markDirty(player)
	end
end

return EvolutionService
