-- Actual Economy/Companion/Evolution rules; simulated decisions, never Studio evidence.
-- lune run tools/lune/simulate-progression.luau [minutes=360] [seed=all 1,2,3] [json-output]
local process = require("@lune/process")
local serde = require("@lune/serde")
local fs = require("@lune/fs")
local env = require("./env")
local Shared = env.services.ReplicatedStorage.Shared
local Services = env.services.ServerScriptService.Server.Services
local Economy = env.require(Shared.Economy)
local Balance = env.require(Shared.Config.Balance)
local Materials = env.require(Shared.Config.Materials)
local Eggs = env.require(Shared.Config.Eggs)
local Companions = env.require(Shared.Config.Companions)
local Pets = env.require(Services.CompanionService).Logic
local Evolution = env.require(Services.EvolutionService).Logic
local minutes = tonumber(process.args[1]) or 360
assert(minutes > 0 and minutes <= 1440, "minutes must be within (0,1440]")
local seeds = if tonumber(process.args[2]) then { tonumber(process.args[2]) } else { 1, 2, 3 }
local scenarios = {
	{ label = "free-auto-collector", mode = "free", luck = 1.5, keepFrom = 4 },
	{ label = "free-auto-seller", mode = "free", luck = 1.5, keepFrom = 7 },
	{ label = "manual-seller", mode = "manual", luck = 2.5, keepFrom = 7 },
}
local tracks = {}
for _, name in Balance.machineTracks do table.insert(tracks, name) end
for _, name in Balance.gearTracks do table.insert(tracks, name) end

local function score(pet)
	local sum = 0
	for _, value in Companions.ById[pet.k].bonus do sum += value end
	return sum
end

local function run(scenario, seed)
	local p = Economy.newProfile()
	Pets.ensure(p)
	Evolution.ensure(p)
	local rng = env.Random.new(seed)
	local clock, eggSpent, hatches, released, starved, idleSeconds = 0, 0, 0, 0, 0, 0
	local firstUnlock, firstEgg, firstEvolution, reached32
	local eggsOpened = {}
	local snapshots, reachedEver = {}, { [1] = 0 }
	local checkpoints = {}
	for _, mark in { 10, 30, 60, 360 } do if mark <= minutes then table.insert(checkpoints, mark * 60) end end
	if checkpoints[#checkpoints] ~= minutes * 60 then table.insert(checkpoints, minutes * 60) end
	local checkpoint = 1
	local function bonuses()
		local evolution = Evolution.bonuses(p.evolutionRank)
		return Economy.combineBonuses({ Pets.bonuses(p), { extract = evolution.production, smelt = evolution.production, prep = evolution.prep } })
	end
	local function snapshot(at)
		table.insert(snapshots, {
			minutes = at / 60, tier = p.unlockedTier, highestTier = p.highestTierEver,
			forges = p.weaponsForged, coins = p.coins, lifetimeCoins = p.lifetimeCoins,
			pets = Pets.petCount(p), hatches = hatches, petsReleased = released,
			evolutionRank = p.evolutionRank, starvedAttempts = starved, materialIdleSeconds = idleSeconds,
			keptWeapons = Economy.weaponCount(p), eggCoinsSpent = eggSpent,
		})
	end
	local function advance(seconds, idle)
		local target = math.min(clock + seconds, minutes * 60)
		while clock < target do
			local nextMark = checkpoints[checkpoint] or math.huge
			local stepEnd = math.min(target, nextMark)
			local dt = stepEnd - clock
			Economy.settle(p, dt, Economy.rates(p, bonuses()))
			if idle then idleSeconds += dt end
			clock = stepEnd
			if clock == nextMark then snapshot(clock); checkpoint += 1 end
		end
		return clock < minutes * 60
	end
	local function managePets()
		local budget = math.max(0, 0.20 * p.lifetimeCoins - eggSpent)
		local candidate
		for _, egg in Eggs.List do
			if Pets.eggUnlocked(p, egg, clock) then candidate = egg end
		end
		-- A bounded player decision policy: seek six rolls of the newest egg, then save for
		-- the next family instead of endlessly buying cheaper, weaker duplicates.
		if not candidate or (eggsOpened[candidate.id] or 0) >= 6 or candidate.coinCost > budget or candidate.coinCost > p.coins then return end
		if Pets.petCount(p) >= Companions.InventoryCapacity then
			local weakest
			for id, pet in p.pets do
				if not weakest or score(pet) < score(p.pets[weakest]) or (score(pet) == score(p.pets[weakest]) and id < weakest) then weakest = id end
			end
			assert(Pets.release(p, weakest))
			released += 1
		end
		assert(Pets.hatch(p, candidate.id, 1, { multiHatch = false, now = clock, rng = rng }))
		eggSpent += candidate.coinCost
		eggsOpened[candidate.id] = (eggsOpened[candidate.id] or 0) + 1
		hatches += 1
		firstEgg = firstEgg or clock
		Pets.equipBest(p)
	end
	while clock < minutes * 60 do
		if not Economy.hasRoom(p) then
			local cheapest
			for id, weapon in p.weapons do
				if not cheapest or weapon.v < p.weapons[cheapest].v then cheapest = id end
			end
			assert(Economy.sellWeapons(p, { cheapest }))
		end
		local material
		for index = p.unlockedTier, 1, -1 do if p.ingots[index] > 0 then material = index; break end end
		if not material then
			starved += 1
			advance(1, true)
			continue
		end
		assert(Economy.canForge(p, material, 1))
		local timing = Economy.forgeTiming(p, scenario.mode, bonuses())
		local grace = if scenario.mode == "manual" then Balance.forge.manual.latencyGraceSec else 0
		if not advance(timing.heatSec + timing.windowSec + grace, false) then break end
		local ok, weapon = Economy.completeForge(p, material, 1, scenario.luck, rng, clock)
		assert(ok, weapon)
		assert(Economy.resolvePending(p, if weapon.r >= scenario.keepFrom then "keep" else "sell"))
		Evolution.ensure(p)
		while Economy.unlockNextMaterial(p) do
			firstUnlock = firstUnlock or clock
			reachedEver[p.unlockedTier] = reachedEver[p.unlockedTier] or clock
			if p.unlockedTier == 32 then reached32 = reached32 or clock end
		end
		Evolution.ensure(p)
		managePets()
		if not firstEvolution and Evolution.eligible(p) then
			assert(Evolution.evolve(p, false, clock))
			firstEvolution = clock
			Pets.equipBest(p)
		else
			local nextMat = Materials[p.unlockedTier + 1]
			local budget = if nextMat then 0.20 * nextMat.unlockCost else math.huge
			for _, track in tracks do
				local cost = Balance.upgradeCost(track, Economy.trackLevel(p, track) or 0)
				if cost and cost <= budget then Economy.buyUpgrade(p, track) end
			end
		end
		advance(timing.revealSec, false)
	end
	return {
		scenario = scenario.label, seed = seed, firstUnlockSec = firstUnlock,
		firstEggSec = firstEgg, firstEvolutionSec = firstEvolution, tier32Sec = reached32,
		firstTierSeconds = reachedEver, snapshots = snapshots,
	}
end

local results = {}
print("scenario,seed,minutes,tier,highestTier,forges,pets,hatches,evolutions,starvedAttempts,materialIdleSeconds,firstTinMin,firstEggMin,firstEvolutionMin,tier32Min")
local function at(value) return if value then string.format("%.3f", value / 60) else "-" end
for _, scenario in scenarios do
	for _, seed in seeds do
		local result = run(scenario, seed)
		table.insert(results, result)
		for _, row in result.snapshots do
			print(string.format("%s,%d,%.0f,%d,%d,%d,%d,%d,%d,%d,%.3f,%s,%s,%s,%s",
				scenario.label, seed, row.minutes, row.tier, row.highestTier, row.forges, row.pets, row.hatches, row.evolutionRank,
				row.starvedAttempts, row.materialIdleSeconds, at(if result.firstUnlockSec and result.firstUnlockSec <= row.minutes * 60 then result.firstUnlockSec else nil),
				at(if result.firstEggSec and result.firstEggSec <= row.minutes * 60 then result.firstEggSec else nil),
				at(if result.firstEvolutionSec and result.firstEvolutionSec <= row.minutes * 60 then result.firstEvolutionSec else nil),
				at(if result.tier32Sec and result.tier32Sec <= row.minutes * 60 then result.tier32Sec else nil)))
		end
	end
end
if process.args[3] then fs.writeFile(process.args[3], serde.encode("json", results, true)) end
