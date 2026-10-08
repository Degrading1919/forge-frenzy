-- Evolution eligibility, reset/keep lists and the protected-evolution anti-loop gate.

local Services = script.Parent.Parent:WaitForChild("Services")
local Config = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config")
local Evolution = require(Config:WaitForChild("Evolution"))
local Logic = require(Services:WaitForChild("EvolutionService")).Logic
local CompanionLogic = require(Services:WaitForChild("CompanionService")).Logic

local function copy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = copy(v)
	end
	return out
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- A mid-game profile shaped like the core thread's schema.
local function profile()
	local p = {
		coins = 50_000,
		lifetimeCoins = 0,
		weaponsForged = 0,
		highestWeaponValue = 900,
		selectedMaterial = 4,
		unlockedTier = 1,
		ore = { [4] = 12 },
		ingots = { [4] = 7 },
		levels = { ExtractorOutput = 3, SmelterSpeed = 2 },
		gear = { Hammer = 2 },
		weapons = { w1 = { id = "w1", m = 4, c = 1, q = 3, r = 5, d = "x", v = 1000, ts = 0 } },
		showcase = { "w1" },
		journal = { [4] = 31 },
		entitlements = { TitanExcavator = true },
		receipts = { abc = 1 },
	}
	CompanionLogic.grantKind(p, "ore_golem")
	CompanionLogic.equipBest(p)
	return p
end

-- Simulate fresh play: forge `n` weapons, earn `coins`, unlock up to `tier`.
local function play(p, n: number, coins: number, tier: number?)
	p.weaponsForged += n
	p.lifetimeCoins += coins
	p.coins += coins
	if tier then
		p.unlockedTier = math.max(p.unlockedTier, tier)
	end
end

local tests = {}

tests["requirements follow docs/13 and cap at tier 32"] = function()
	assert(Evolution.forgeRequirement(0) == 150 and Evolution.tierRequirement(0) == 4)
	assert(Evolution.forgeRequirement(3) == 300 and Evolution.tierRequirement(3) == 10)
	assert(Evolution.tierRequirement(14) == 32 and Evolution.tierRequirement(40) == 32)
end

tests["tierForCoins uses cumulative unlock costs"] = function()
	-- tiers 2..4 cost 414 + 870 + 1836 = 3120
	assert(Logic.tierForCoins(0) == 1)
	assert(Logic.tierForCoins(413) == 1)
	assert(Logic.tierForCoins(414) == 2)
	assert(Logic.tierForCoins(3119) == 3)
	assert(Logic.tierForCoins(3120) == 4)
	assert(Logic.tierForCoins(1e300) == 32)
end

tests["fresh profile is not eligible; 150 forges plus tier 4 is"] = function()
	local p = profile()
	assert(not Logic.eligible(p))
	play(p, 149, 0, 4)
	assert(not Logic.eligible(p), "149 forges should not qualify")
	play(p, 1, 0)
	assert(Logic.eligible(p))
end

tests["forges alone do not qualify without the tier milestone"] = function()
	local p = profile()
	play(p, 1000, 3000, 3)
	assert(not Logic.eligible(p))
end

tests["normal evolution resets exactly the declared fields"] = function()
	local p = profile()
	play(p, 150, 10_000, 5)
	local before = copy(p)
	local ok, rank = Logic.evolve(p, false, 1)
	assert(ok and rank == 1, rank)

	for _, entry in Evolution.Resets do
		assert(deepEqual(p[entry.field], entry.value), "did not reset " .. entry.field)
	end
	local declared = {}
	for _, entry in Evolution.Resets do
		declared[entry.field] = true
	end
	local ownFields = { evolutionRank = true, evolveBaseline = true, evolveLog = true, highestTierEver = true, petSlots = true }
	for key, value in before do
		if not declared[key] and not ownFields[key] then
			assert(deepEqual(value, p[key]), "unexpectedly changed " .. key)
		end
	end
	assert(p.highestTierEver == 5, "highest tier ever should be remembered")
	assert(p.lifetimeCoins == before.lifetimeCoins and p.weaponsForged == before.weaponsForged)
end

tests["reset tables are copies, not shared config tables"] = function()
	local a, b = profile(), profile()
	play(a, 150, 0, 4)
	play(b, 150, 0, 4)
	Logic.evolve(a, false, 1)
	Logic.evolve(b, false, 1)
	a.ore[1] = 99
	assert(b.ore[1] == nil, "profiles share a reset table")
	for _, entry in Evolution.Resets do
		if type(entry.value) == "table" then
			assert(next(entry.value) == nil, "config reset value was mutated")
		end
	end
end

tests["evolving again immediately fails and leaves the profile untouched"] = function()
	local p = profile()
	play(p, 150, 0, 4)
	assert(Logic.evolve(p, false, 1))
	local snapshot = copy(p)
	local ok, why = Logic.evolve(p, false, 2)
	assert(not ok and why == "not eligible")
	assert(deepEqual(snapshot, p))
end

tests["rank 1 needs 200 fresh forges and fresh tier 6"] = function()
	local p = profile()
	play(p, 150, 0, 4)
	Logic.evolve(p, false, 1)
	play(p, 199, 0, 6)
	assert(not Logic.eligible(p))
	play(p, 1, 0)
	assert(Logic.eligible(p))
end

tests["protected evolution needs a charge and consumes exactly one"] = function()
	local p = profile()
	play(p, 150, 0, 4)
	local ok, why = Logic.evolve(p, true, 1)
	assert(not ok and why == "no protected evolution charge")
	Logic.addCharges(p, 2)
	assert(Logic.evolve(p, true, 1))
	assert(p.evolveCharges == 1)
end

tests["protected evolution keeps coins, materials and machines"] = function()
	local p = profile()
	play(p, 150, 0, 9)
	Logic.addCharges(p, 1)
	local before = copy(p)
	assert(Logic.evolve(p, true, 1))
	for _, entry in Evolution.Resets do
		assert(deepEqual(before[entry.field], p[entry.field]), "protected reset " .. entry.field)
	end
	assert(p.evolutionRank == 1)
end

tests["protected evolution cannot chain on retained coins and extractor"] = function()
	local p = profile()
	play(p, 150, 0, 20) -- far above the rank-1 tier gate of 6
	p.coins = 1e15 -- huge retained bank
	Logic.addCharges(p, 5)
	assert(Logic.evolve(p, true, 1))
	-- Fresh forges but no fresh earning or unlocks: retained tier 20 and coins do not count.
	play(p, 500, 0)
	assert(not Logic.eligible(p), "retained progress must not qualify")
	assert(not Logic.evolve(p, true, 2))
	assert(p.evolveCharges == 4)
	-- Earning the cumulative cost of tiers 2..6 since the evolve is genuine fresh progress.
	play(p, 0, 414 + 870 + 1836 + 3754 + 7451)
	assert(Logic.eligible(p))
end

tests["purchased coins never count as fresh progress"] = function()
	local p = profile()
	play(p, 150, 0, 4)
	Logic.evolve(p, false, 1)
	play(p, 200, 0)
	p.coins += 1e12 -- StarterPack-style grant touches coins only
	assert(not Logic.eligible(p))
end

tests["evolution keeps companions and grants the third slot"] = function()
	local p = profile()
	local pets = copy(p.pets)
	play(p, 150, 0, 4)
	Logic.evolve(p, false, 1)
	assert(deepEqual(pets, p.pets))
	CompanionLogic.ensure(p)
	assert(p.petSlots == 3)
end

tests["bonuses scale with rank"] = function()
	local b = Logic.bonuses(4)
	assert(math.abs(b.production - 0.6) < 1e-9 and math.abs(b.prep - 0.12) < 1e-9)
	local z = Logic.bonuses(0)
	assert(z.production == 0 and z.prep == 0)
end

tests["status preview lists every reset and nothing for protected"] = function()
	local p = profile()
	local s = Logic.status(p)
	assert(#s.preview.normal.resets == #Evolution.Resets)
	assert(#s.preview.protected.resets == 0)
	assert(s.requirements.forged == 150 and s.requirements.tier == 4)
	assert(s.eligible == false)
end

tests["legacy profile without evolution fields is upgraded safely"] = function()
	local p = { weaponsForged = 10, lifetimeCoins = 50, unlockedTier = 2 }
	local s = Logic.status(p)
	assert(s.rank == 0 and p.evolveCharges == 0 and p.highestTierEver == 2)
end

tests["evolution log stays bounded"] = function()
	local p = profile()
	Logic.ensure(p)
	for i = 1, 30 do
		local need = Logic.requirements(p.evolutionRank)
		play(p, need.forged, 1e300, need.tier)
		assert(Logic.evolve(p, false, i))
	end
	assert(#p.evolveLog == 20 and p.evolveLog[20].rank == 30)
end

tests["player evolve requires a loaded profile and coerces protected to boolean"] = function()
	local Service = require(Services:WaitForChild("EvolutionService"):Clone())
	local data = profile()
	play(data, 150, 0, 4)
	data.evolveCharges = 1
	Service._inject({
		getProfile = function(pl)
			return if pl.UserId == 1 then { Data = data } else nil
		end,
	})
	assert(not Service.evolve({ UserId = 2 }, false))
	local ok = Service.evolve({ UserId = 1 }, "yes") -- not `true`, so a normal evolve
	assert(ok and data.evolveCharges == 1 and data.coins == 0)
end

return tests
