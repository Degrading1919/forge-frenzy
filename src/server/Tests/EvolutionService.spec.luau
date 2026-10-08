-- Evolution v2: literal requirements, fresh-tier rule, reset/keep lists, pad re-fit, cash multiplier.

local Services = script.Parent.Parent:WaitForChild("Services")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Evolution = require(Config:WaitForChild("Evolution"))
local Materials = require(Config:WaitForChild("Materials"))
local Economy = require(Shared:WaitForChild("Economy"))
local EvolutionService = require(Services:WaitForChild("EvolutionService"))
local Logic = EvolutionService.Logic
local CompanionLogic = require(Services:WaitForChild("CompanionService")).Logic
local ForgeService = require(Services:WaitForChild("ForgeService"))

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

-- A mid-game v2 profile.
local function profile()
	local p = Economy.newProfile()
	p.coins = 50_000
	p.highestWeaponValue = 900
	p.unlockedTier = 4
	p.lines[1].m = 4
	p.stations[1].m = 4
	p.selectedMaterial = 4
	p.ingots[4] = 7
	p.bank = 321
	p.levels.ExtractorOutput = 3
	p.levels.SmelterSpeed = 2
	p.gear.Hammer = 2
	p.weapons.w1 = { id = "w1", m = 4, c = 1, q = 3, r = 5, d = "x", v = 1000, ts = 0 }
	p.showcase[1] = "w1"
	p.nextWeaponId = 2
	p.journal[4] = 31
	p.entitlements = { TitanExcavator = true }
	p.receipts = { abc = 1 }
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

tests["requirements are literal: forges and a material to unlock, capped at tier 32"] = function()
	assert(Evolution.BaseForges == 120 and Evolution.ForgesPerRank == 60 and Evolution.BaseTier == 6 and Evolution.TierPerRank == 2)
	assert(Evolution.forgeRequirement(0) == 120 and Evolution.tierRequirement(0) == 6)
	assert(Evolution.forgeRequirement(1) == 180 and Evolution.tierRequirement(1) == 8)
	assert(Evolution.forgeRequirement(3) == 300 and Evolution.tierRequirement(3) == 12)
	assert(Evolution.tierRequirement(13) == 32 and Evolution.tierRequirement(14) == 32 and Evolution.tierRequirement(40) == 32)
	local req = Logic.requirements(2)
	assert(req.forged == 240 and req.tier == 10)
	for rank = 0, 60 do
		assert(Evolution.tierRequirement(rank) <= #Materials and Evolution.tierRequirement(rank) >= 6)
	end
end

tests["tierForCoins follows cumulative unlock costs but does not decide eligibility"] = function()
	local sum = 0
	for tier = 2, 6 do
		sum += Materials[tier].unlockCost
		assert(Logic.tierForCoins(sum) >= tier, "tier " .. tier)
		assert(Logic.tierForCoins(sum - 1) >= tier - 1)
	end
	assert(Logic.tierForCoins(0) == 1 and Logic.tierForCoins(1e300) == 32)
	-- earning every coin in the game without unlocking anything is not progress
	local p = profile()
	p.unlockedTier = 1
	play(p, 5000, 1e29)
	assert(not Logic.eligible(p), "no coins-earned path to the tier requirement")
end

tests["fresh profile is not eligible; 120 forges plus a tier-6 material is"] = function()
	local p = profile()
	assert(not Logic.eligible(p))
	play(p, 119, 0, 6)
	assert(not Logic.eligible(p), "119 forges should not qualify")
	play(p, 1, 0)
	assert(Logic.eligible(p))
	local q = profile()
	play(q, 120, 0, 5)
	assert(not Logic.eligible(q), "tier 5 is short of tier 6")
end

tests["forges alone do not qualify without the material, and the material alone does not qualify"] = function()
	local p = profile()
	play(p, 1000, 3000, 3)
	assert(not Logic.eligible(p))
	local q = profile()
	play(q, 0, 0, 20)
	assert(not Logic.eligible(q))
end

tests["normal evolution resets exactly the declared fields"] = function()
	local p = profile()
	play(p, 120, 10_000, 6)
	local before = copy(p)
	local ok, rank = Logic.evolve(p, false, 1)
	assert(ok and rank == 1, rank)

	local fresh = Economy.newProfile()
	local declared = {}
	for _, entry in Evolution.Resets do
		declared[entry.field] = true
		assert(deepEqual(p[entry.field], fresh[entry.field]), "did not reset " .. entry.field)
	end
	for _, field in { "coins", "ingots", "unlockedTier", "levels", "lines", "stations", "selectedMaterial", "bank" } do
		assert(declared[field], field .. " should be in the reset list")
	end
	local ownFields = { evolutionRank = true, evolveBaseline = true, evolveLog = true, highestTierEver = true, petSlots = true }
	for key, value in before do
		if not declared[key] and not ownFields[key] then
			assert(deepEqual(value, p[key]), "unexpectedly changed " .. key)
		end
	end
	assert(p.highestTierEver == 6, "highest tier ever should be remembered")
	assert(p.lifetimeCoins == before.lifetimeCoins and p.weaponsForged == before.weaponsForged)
	assert(p.weapons.w1 ~= nil and p.showcase[1] == "w1" and p.gear.Hammer == 2, "weapons, displays and gear are kept")
	assert(p.unlockedTier == 1 and p.coins == 0 and p.bank == 0 and p.ingots[1] == Economy.STARTER_INGOTS)
end

tests["evolution re-fits ore lines and forges to the kept build pads"] = function()
	local p = profile()
	p.pads = { line_2 = true, forge_2 = true, podiums_1 = true, decor_banners = true }
	Economy.reconcile(p)
	assert(#p.lines == 2 and #p.stations == 2)
	p.lines[2].m = 3
	p.stations[2].m = 3
	p.stations[2].c = 2
	play(p, 120, 0, 6)
	assert(Logic.evolve(p, false, 1))
	assert(p.pads.line_2 and p.pads.forge_2 and p.pads.podiums_1 and p.pads.decor_banners, "pads are permanent")
	assert(#p.lines == 2 and #p.stations == 2, "lines and stations re-fit to the pads")
	for i = 1, 2 do
		assert(p.lines[i].m == 1 and p.lines[i].ore == 0, "line " .. i .. " back to Copper")
		assert(p.stations[i].m == 1 and p.stations[i].c == Economy.STARTER_CLASS and p.stations[i].keep == 4, "station " .. i .. " back to the starter recipe")
	end
	assert(p.selectedMaterial == 1 and Economy.showcaseSlots(p) == 4)
	assert(Economy.rates(p).lines == 2)
	-- a pad for a tier reached before the reset can be bought again after it
	p.pads.line_2 = nil
	Economy.reconcile(p)
	p.coins = 1e9
	assert(Economy.buyPad(p, "line_2"), "highestTierEver keeps pads purchasable")
end

tests["reset tables are copies, not shared config tables"] = function()
	local configBefore = copy(Evolution.Resets)
	local a, b = profile(), profile()
	play(a, 120, 0, 6)
	play(b, 120, 0, 6)
	Logic.evolve(a, false, 1)
	Logic.evolve(b, false, 1)
	a.ingots[1] = 99
	a.lines[1].ore = 5
	a.levels.ExtractorOutput = 7
	assert(b.ingots[1] ~= 99 and b.lines[1].ore == 0 and b.levels.ExtractorOutput == 0, "profiles share a reset table")
	assert(deepEqual(configBefore, Evolution.Resets), "config reset value was mutated")
end

tests["evolving again immediately fails and leaves the profile untouched"] = function()
	local p = profile()
	play(p, 120, 0, 6)
	assert(Logic.evolve(p, false, 1))
	local snapshot = copy(p)
	local ok, why = Logic.evolve(p, false, 2)
	assert(not ok and why == "not eligible")
	assert(deepEqual(snapshot, p))
end

tests["rank 1 needs 180 fresh forges and a fresh tier-8 material"] = function()
	local p = profile()
	play(p, 120, 0, 6)
	assert(Logic.evolve(p, false, 1))
	assert(Logic.progress(p).forged == 0 and Logic.progress(p).tier == 1)
	play(p, 179, 0, 8)
	assert(not Logic.eligible(p))
	play(p, 1, 0)
	assert(Logic.eligible(p))
	local q = profile()
	play(q, 120, 0, 6)
	Logic.evolve(q, false, 1)
	play(q, 500, 0, 7)
	assert(not Logic.eligible(q), "plenty of forges, but tier 7 is short of tier 8")
end

tests["protected evolution needs a charge and consumes exactly one"] = function()
	local p = profile()
	play(p, 120, 0, 6)
	local ok, why = Logic.evolve(p, true, 1)
	assert(not ok and why == "no protected evolution charge")
	Logic.addCharges(p, 2)
	assert(Logic.evolve(p, true, 1))
	assert(p.evolveCharges == 1)
end

tests["protected evolution keeps coins, materials and machines"] = function()
	local p = profile()
	play(p, 120, 0, 9)
	Logic.addCharges(p, 1)
	local before = copy(p)
	assert(Logic.evolve(p, true, 1))
	for _, entry in Evolution.Resets do
		assert(deepEqual(before[entry.field], p[entry.field]), "protected reset " .. entry.field)
	end
	assert(p.evolutionRank == 1)
end

tests["protected evolution cannot chain on a retained material and cash"] = function()
	local p = profile()
	play(p, 120, 0, 20) -- far above the rank-0 tier gate of 6
	p.coins = 1e15 -- huge retained bank
	Logic.addCharges(p, 5)
	assert(Logic.evolve(p, true, 1))
	-- Fresh forges but nothing newly unlocked: the retained tier-20 material does not count.
	play(p, 500, 0)
	assert(Logic.progress(p).tier == 1)
	assert(not Logic.eligible(p), "retained progress must not qualify")
	assert(not Logic.evolve(p, true, 2))
	assert(p.evolveCharges == 4)
	-- Earning coins is not progress either
	play(p, 0, 1e20)
	assert(not Logic.eligible(p))
	-- Unlocking a new material above the kept one is genuine fresh progress (rank 1 needs tier 8)
	p.unlockedTier = 21
	assert(Logic.eligible(p))
end

tests["evolution keeps companions and grants the third slot"] = function()
	local p = profile()
	local pets = copy(p.pets)
	play(p, 120, 0, 6)
	Logic.evolve(p, false, 1)
	assert(deepEqual(pets, p.pets))
	CompanionLogic.ensure(p)
	assert(p.petSlots == 3)
end

tests["bonuses scale with rank and include a permanent cash multiplier"] = function()
	local b = Logic.bonuses(4)
	assert(math.abs(b.production - 0.4) < 1e-9 and math.abs(b.prep - 0.12) < 1e-9)
	assert(math.abs(b.cash - 3) < 1e-9, "rank 4 = x3 cash")
	local z = Logic.bonuses(0)
	assert(z.production == 0 and z.prep == 0 and z.cash == 1)
	assert(Evolution.cashMultiplier(0) == 1 and Evolution.cashMultiplier(2) == 2 and Evolution.cashMultiplier(-5) == 1)
	for rank = 1, 20 do
		assert(Logic.bonuses(rank).cash > Logic.bonuses(rank - 1).cash)
	end
end

tests["the cash multiplier reaches the forge through the player-level API"] = function()
	local Service = EvolutionService
	local data = profile()
	data.evolutionRank = 3
	local player = { UserId = 55 }
	Service._inject({
		getProfile = function(who)
			return if who == player then { Data = data } else nil
		end,
	})
	local ok, err = pcall(function()
		assert(Service.bonuses(player).cash == 2.5)
		assert(ForgeService.cashMultiplier(player) == 2.5, "forge reads the evolution multiplier")
		assert(Service.bonuses({ UserId = 56 }).cash == 1, "no profile, no multiplier")
		data.evolutionRank = 0
		assert(ForgeService.cashMultiplier(player) == 1)
	end)
	Service._inject({
		getProfile = function()
			return nil
		end,
	})
	assert(ok, err)
end

tests["status preview lists every reset and nothing for protected"] = function()
	local p = profile()
	local s = Logic.status(p)
	assert(#s.preview.normal.resets == #Evolution.Resets)
	assert(#s.preview.protected.resets == 0)
	assert(s.requirements.forged == 120 and s.requirements.tier == 6)
	assert(s.eligible == false and s.progress.tier == 4)
	assert(s.nextBonuses.cash == 1.5 and s.bonuses.cash == 1)
	play(p, 120, 0, 6)
	assert(Logic.status(p).eligible == true)
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
		play(p, need.forged, 0, need.tier)
		assert(Logic.evolve(p, false, i), "evolution " .. i)
	end
	assert(#p.evolveLog == 20 and p.evolveLog[20].rank == 30)
end

tests["player evolve requires a loaded profile, coerces protected to boolean and saves"] = function()
	local Service = require(Services:WaitForChild("EvolutionService"):Clone())
	local data = profile()
	play(data, 120, 0, 6)
	data.evolveCharges = 1
	local dirty = 0
	Service._inject({
		getProfile = function(pl)
			return if pl.UserId == 1 then { Data = data } else nil
		end,
		markDirty = function()
			dirty += 1
		end,
	})
	assert(not Service.evolve({ UserId = 2 }, false))
	assert(dirty == 0)
	local ok = Service.evolve({ UserId = 1 }, "yes") -- not `true`, so a normal evolve
	assert(ok and data.evolveCharges == 1 and data.coins == 0 and dirty == 1)
	local again = Service.evolve({ UserId = 1 }, false)
	assert(not again and dirty == 1, "a refused evolve is not saved")
end

return tests
