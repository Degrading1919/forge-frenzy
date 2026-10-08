--[[
	v2 progression simulation (docs/23). Real Economy / ForgeMath / Companion / Evolution rules;
	simulated player decisions. Not Studio evidence and not a human playtest.

	    lune run tools/lune/simulate-v2.luau [scenario=free] [hours=600] [seed=1] [json-output]

	Scenarios:
	  free     free Auto Forge (1.5x luck) on every owned forge, no purchases
	  premium  premium Auto Forge (4x), Multi-Forge, VIP + Titan passes (Robux-free simulation)
	  manual   a free player who hammers manually at 2.5x luck on one forge (others on free auto)

	Stealing stress tests (free auto plus a steal on a fixed schedule; worst case: every steal
	lands a top-roll Mythic Primordium greatsword from a rank-13 player, the best weapon in the
	game, which is then displayed or sold for whatever it is worth to the thief):
	  steal2m          one such steal every 2 minutes, for the whole run (with the value cap)
	  steal15m         one every 15 minutes (with the value cap)
	  steal2m-uncapped every 2 minutes, with weapons selling at full value (before this fix)
	  evolve-sell      free auto, but after each evolution sells every kept weapon at once
	  evolve-sell-uncapped  the same, with weapons selling at full value (before this fix)
	  free-uncapped    plain free auto with weapons selling at full value (before this fix)

	The simulated player is attentive: every few seconds it buys the next material when it can,
	builds pads and machine upgrades that cost a small share of the next material, hatches and
	merges pets, re-picks forge recipes to match ingot supply, displays its best weapons,
	collects display cash, sells its backpack, and evolves as soon as it is eligible. Walking,
	menus and reveal animations are not modelled, so real players will be somewhat slower.
]]

local process = require("@lune/process")
local serde = require("@lune/serde")
local fs = require("@lune/fs")
local env = require("./env")
local Shared = env.services.ReplicatedStorage.Shared
local Services = env.services.ServerScriptService.Server.Services
local Economy = env.require(Shared.Economy)
local ForgeMath = env.require(Shared.ForgeMath)
local Balance = env.require(Shared.Config.Balance)
local Materials = env.require(Shared.Config.Materials)
local BuildPads = env.require(Shared.Config.BuildPads)
local Eggs = env.require(Shared.Config.Eggs)
local EvolutionCfg = env.require(Shared.Config.Evolution)
local Pets = env.require(Services.CompanionService).Logic
local Evolution = env.require(Services.EvolutionService).Logic

local scenarioName = process.args[1] or "free"
local hours = tonumber(process.args[2]) or 600
local seed = tonumber(process.args[3]) or 1
local jsonOut = process.args[4]
DEBUG = process.env.SIM_DEBUG == "1"

local SCENARIOS = {
	free = { luck = 1.5, mode = "free", rolls = 1, passes = {} },
	premium = { luck = 4, mode = "premium", rolls = 2, passes = { "VIPWorkshop", "TitanExcavator", "DragonFurnace" } },
	manual = { luck = 1.5, manualLuck = 2.5, mode = "free", rolls = 1, passes = {} },
	steal2m = { luck = 1.5, mode = "free", rolls = 1, passes = {}, stealEvery = 120, capped = true },
	steal15m = { luck = 1.5, mode = "free", rolls = 1, passes = {}, stealEvery = 900, capped = true },
	["steal2m-uncapped"] = { luck = 1.5, mode = "free", rolls = 1, passes = {}, stealEvery = 120, capped = false, uncapped = true },
	["evolve-sell"] = { luck = 1.5, mode = "free", rolls = 1, passes = {}, sellOnEvolve = true },
	["free-uncapped"] = { luck = 1.5, mode = "free", rolls = 1, passes = {}, uncapped = true },
	["evolve-sell-uncapped"] = { luck = 1.5, mode = "free", rolls = 1, passes = {}, sellOnEvolve = true, uncapped = true },
}
local scenario = assert(SCENARIOS[scenarioName], "unknown scenario " .. scenarioName)

if scenario.uncapped then
	-- Reproduces the economy before the usable-value rule: every weapon sells for its full value.
	Economy.usableValue = function(_p, weapon)
		return weapon.v
	end
end

local p = Economy.newProfile()
Pets.ensure(p)
Evolution.ensure(p)
local rng = env.Random.new(seed)
local now = 0
local limit = hours * 3600

local stationReadyAt = {}
local eggSpent = 0
local function bonuses()
	local evo = Evolution.bonuses(p.evolutionRank)
	local sources = { Pets.bonuses(p), { extract = evo.production, smelt = evo.production, prep = evo.prep } }
	for _, key in scenario.passes do
		table.insert(sources, Balance.premiumBonuses[key])
	end
	return Economy.combineBonuses(sources)
end
local function cashMult()
	return Evolution.bonuses(p.evolutionRank).cash
end

-- Milestones ----------------------------------------------------------------------------------
local firstTier = { [1] = 0 }
local evolutions = {}
local log = {}
local function note(kind, detail)
	table.insert(log, { t = now, kind = kind, detail = detail })
end

-- Decisions -----------------------------------------------------------------------------------
local function supplyPerSec(b)
	local r = Economy.rates(p, b)
	return math.min(r.orePerSec, r.ingotPerSec) * r.lines
end

local function cycleSec(b)
	local t = Economy.forgeTiming(p, "auto", b)
	return t.heatSec + t.windowSec + t.revealSec
end

-- Re-pick each forge's recipe: top material, the biggest recipe the ingot supply can feed.
local function chooseRecipes(b)
	local supply = supplyPerSec(b)
	local forges = #p.stations
	local perForgeCycles = 1 / cycleSec(b)
	local best = 4
	for _, c in Balance.classDisplayOrder do
		local need = Balance.recipeIngots(c) * perForgeCycles * forges * scenario.rolls
		if need <= supply * 1.15 then
			best = c
		end
	end
	-- With a full vault, temporarily use the biggest recipe to drain it.
	local r = Economy.rates(p, b)
	if p.ingots[p.unlockedTier] >= r.capacity * 0.9 then
		best = 2
	end
	for _, station in p.stations do
		station.m = p.unlockedTier
		station.c = best
		station.keep = 5
	end
	for _, line in p.lines do
		line.m = p.unlockedTier
	end
end

local function nextUnlockCost()
	local mat = Materials[p.unlockedTier + 1]
	return if mat then mat.unlockCost else math.huge
end

local function buyThings()
	local spentSomething = true
	local hatchedThisRound = false
	local guard = 0
	while spentSomething and guard < 200 do
		guard += 1
		spentSomething = false
		local target = nextUnlockCost()
		if p.coins >= target then
			local ok = Economy.unlockMaterial(p, p.unlockedTier + 1)
			if ok then
				p.highestTierEver = math.max(p.highestTierEver or 1, p.unlockedTier)
				if not firstTier[p.unlockedTier] then
					firstTier[p.unlockedTier] = now
				end
				spentSomething = true
				continue
			end
		end
		-- Pads: anything available costing at most half the next material.
		for _, pad in BuildPads.List do
			if pad.kind ~= "decor" and BuildPads.available(pad, p.pads, math.max(p.unlockedTier, p.highestTierEver or 1)) and pad.cost <= target * 0.5 and p.coins >= pad.cost then
				Economy.buyPad(p, pad.id)
				note("pad", pad.id)
				spentSomething = true
			end
		end
		-- Upgrades: the cheapest one costing at most 8% of the next material.
		local cheapest, cheapestCost = nil, math.huge
		for _, group in { Balance.machineTracks, Balance.gearTracks } do
			for _, track in group do
				local cost = Balance.upgradeCost(track, Economy.trackLevel(p, track))
				if cost and cost < cheapestCost then
					cheapest, cheapestCost = track, cost
				end
			end
		end
		if cheapest and cheapestCost <= target * 0.08 and p.coins >= cheapestCost then
			Economy.buyUpgrade(p, cheapest)
			spentSomething = true
		end
		-- Pets: newest unlocked egg, while it costs at most 10% of the next material.
		local egg
		for _, candidate in Eggs.List do
			if Pets.eggUnlocked(p, candidate, now) then
				egg = candidate
			end
		end
		if egg and not hatchedThisRound and egg.coinCost <= target * 0.1 and p.coins >= egg.coinCost and eggSpent + egg.coinCost <= 0.15 * p.lifetimeCoins and Pets.petCount(p) < 90 then
			hatchedThisRound = true
			eggSpent += egg.coinCost
			local ok = Pets.hatch(p, egg.id, 1, { multiHatch = false, rng = rng, now = now })
			if ok then
				spentSomething = true
				Pets.mergeAll(p)
				Pets.equipBest(p)
			end
		end
	end
end

local function manageDisplays()
	-- Show the weapons that earn the most on a podium for this player.
	local list = {}
	for id, w in p.weapons do
		table.insert(list, { id = id, v = Economy.displayIncome(p, w, cashMult()) })
	end
	table.sort(list, function(a, b)
		return a.v > b.v
	end)
	local slots = Economy.showcaseSlots(p)
	for slot = 1, Balance.inventory.showcaseSlots do
		p.showcase[slot] = if slot <= slots and list[slot] then list[slot].id else ""
	end
	-- Walk to the booth and sell everything that is not on display.
	Economy.sellAll(p, nil, nil, cashMult())
	Economy.collectBank(p)
end

local function tryEvolve()
	if Evolution.eligible(p) then
		local rank = p.evolutionRank
		local ok = Evolution.evolve(p, false, now)
		if ok then
			table.insert(evolutions, { t = now, rank = rank + 1 })
			if scenario.sellOnEvolve then
				for slot = 1, #p.showcase do
					p.showcase[slot] = ""
				end
				Economy.sellAll(p, nil, nil, cashMult())
			end
		end
	end
end

-- Main loop -----------------------------------------------------------------------------------
-- Production settles in DT-second chunks; each forge completes at its own ready time inside a
-- chunk. Bonuses and rates are refreshed every few seconds (they only change on purchases).
local DT = 5
local nextDecision, nextDisplay, nextRecipe = 0, 0, 0
local nextSteal = scenario.stealEvery or math.huge
local steals, stealCash = 0, 0
local stealRng = { NextNumber = function() return 0.999 end }
local forges = 0
local snapshots = {}
local SNAP_HOURS = { 0.0167, 0.05, 0.1667, 0.5, 1, 2, 5, 10, 25, 50, 100, 200, 300, 400, 500, 600, 800, 1000 }
local snapIndex = 1
local b, rates, timing, mult = bonuses(), nil, nil, cashMult()
local function refresh()
	b = bonuses()
	rates = Economy.rates(p, b)
	timing = Economy.forgeTiming(p, scenario.mode, b)
	mult = cashMult()
end
refresh()
while now < limit and p.unlockedTier < 32 do
	Economy.settle(p, DT, rates)
	Economy.accrueDisplay(p, DT, mult)
	local chunkEnd = now + DT
	for i, station in p.stations do
		local manual = scenario.manualLuck ~= nil and i == 1
		local luck = if manual then scenario.manualLuck else scenario.luck
		local window = if manual then Balance.forge.manual.strikeWindowSec else timing.windowSec
		local cycle = timing.heatSec + window + timing.revealSec
		local readyAt = stationReadyAt[i] or now
		while readyAt < chunkEnd do
			local ok = Economy.completeForgeBatch(p, station.m, station.c, luck, rng, readyAt, scenario.rolls, { mult = mult, keepFrom = station.keep, allowFullBackpack = true })
			if ok then
				forges += 1
				readyAt += cycle
			else
				readyAt = chunkEnd -- out of ingots: wait for the next production chunk
			end
		end
		stationReadyAt[i] = readyAt
	end
	now = chunkEnd
	if now >= nextRecipe then
		chooseRecipes(b)
		nextRecipe = now + 30
	end
	if now >= nextDecision then
		local tierBefore, rankBefore, padsBefore = p.unlockedTier, p.evolutionRank, #p.stations + #p.lines
		buyThings()
		if p.unlockedTier >= 32 then
			break -- the final material: the goal this simulation measures
		end
		tryEvolve()
		refresh()
		if p.evolutionRank ~= rankBefore or p.unlockedTier ~= tierBefore or #p.stations + #p.lines ~= padsBefore then
			chooseRecipes(b)
		end
		nextDecision = now + 10
	end
	if now >= nextSteal then
		nextSteal = now + scenario.stealEvery
		local w = ForgeMath.rollWeapon(stealRng :: any, 32, 2, 5, { id = "", ts = now, mult = EvolutionCfg.cashMultiplier(13) })
		w.id = Economy.nextWeaponId(p)
		if scenario.capped then
			w.st = 1
		end
		p.weapons[w.id] = w
		steals += 1
		stealCash += Economy.usableValue(p, w, mult)
		nextDisplay = now -- display it or sell it straight away
	end
	if now >= nextDisplay then
		manageDisplays()
		nextDisplay = now + 120
	end
	if os.getenv and false then end
	if DEBUG and now % 3600 < DT then
		local lv = {}
		for _, t in Balance.machineTracks do table.insert(lv, t:sub(1,4) .. "=" .. p.levels[t]) end
		for _, t in Balance.gearTracks do table.insert(lv, t:sub(1,4) .. "=" .. p.gear[t]) end
		print(string.format("[%5.1fh] t%d coins %s life %s next %s ingots %d cap %d sup %.2f/s cyc %.1f st %d/%d %s pets %d", now/3600, p.unlockedTier, ForgeMath.formatCoins(p.coins) .. " ing[" .. (function() local t = {} for i, n in p.ingots do if n > 0 then table.insert(t, i .. ":" .. n) end end return table.concat(t, ",") end)() .. "] st " .. p.stations[1].m .. "/" .. p.stations[1].c .. " lines " .. p.lines[1].m .. " w" .. Economy.weaponCount(p), ForgeMath.formatCoins(p.lifetimeCoins), ForgeMath.formatCoins(nextUnlockCost()), Economy.ingotTotal(p), rates.capacity, supplyPerSec(b), timing.heatSec + timing.windowSec + timing.revealSec, p.stations[1].c, #p.stations, table.concat(lv, " "), Pets.petCount(p)))
	end
	while SNAP_HOURS[snapIndex] and now >= SNAP_HOURS[snapIndex] * 3600 do
		table.insert(snapshots, { h = SNAP_HOURS[snapIndex], tier = p.unlockedTier, best = p.highestTierEver or 1, rank = p.evolutionRank, coins = p.coins, lifetime = p.lifetimeCoins, pets = Pets.petCount(p), lines = #p.lines, forges = #p.stations })
		snapIndex += 1
	end
end

local function fmt(n)
	return ForgeMath.formatCoins(n)
end
local function hm(t)
	if t == nil then
		return "-"
	end
	if t < 3600 then
		return string.format("%.1fm", t / 60)
	end
	return string.format("%.1fh", t / 3600)
end

if steals > 0 then
	print(string.format("steals=%d, usable value when taken: %s total", steals, ForgeMath.formatCoins(stealCash)))
end
print(string.format("scenario=%s seed=%d reached tier %d (best %d) after %s, rank %d", scenarioName, seed, p.unlockedTier, p.highestTierEver or 1, hm(now), p.evolutionRank))
print("first time each material was bought (cumulative):")
local line = {}
for t = 2, 32 do
	table.insert(line, string.format("%s %s", Materials[t].name, hm(firstTier[t])))
	if #line == 4 then
		print("  " .. table.concat(line, " | "))
		line = {}
	end
end
if #line > 0 then
	print("  " .. table.concat(line, " | "))
end
print("evolutions:")
local ev = {}
for _, e in evolutions do
	table.insert(ev, string.format("r%d@%s", e.rank, hm(e.t)))
end
print("  " .. table.concat(ev, ", "))
print("snapshots: hours tier best rank cash lifetime pets lines forges")
for _, s in snapshots do
	print(string.format("  %7.2fh  t%-2d  best %-2d r%-2d  $%-8s  $%-8s  pets %-3d  L%d F%d", s.h, s.tier, s.best, s.rank, fmt(s.coins), fmt(s.lifetime), s.pets, s.lines, s.forges))
end
local padTimes = {}
for _, entry in log do
	if entry.kind == "pad" then
		table.insert(padTimes, entry.detail .. "@" .. hm(entry.t))
	end
end
print("pads: " .. table.concat(padTimes, ", "))

if jsonOut then
	fs.writeFile(jsonOut, serde.encode("json", { scenario = scenarioName, seed = seed, firstTier = firstTier, evolutions = evolutions, snapshots = snapshots, endedAt = now, finalTier = p.unlockedTier }, true))
end
