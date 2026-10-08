--[[
	Economy pacing simulation for balance tuning (PROPOSED v0 numbers).

	    lune run tools/lune/simulate-economy.luau [minutes] [seed]

	Plays one forge cycle at a time against the real Economy rules for four player profiles
	(free auto 1.5x, typical manual 2.5x, paid auto 4x, skilled manual 5x), selling every
	weapon, unlocking the next material as soon as it is affordable and buying any upgrade that
	costs at most 20% of the next unlock. Prints minutes to reach each material tier.
	No companions, evolution or premium production bonuses are applied.
]]

local process = require("@lune/process")
local env = require("./env")

local Shared = env.services.ReplicatedStorage.Shared
local Economy = env.require(Shared.Economy)
local Balance = env.require(Shared.Config.Balance)
local Materials = env.require(Shared.Config.Materials)
local ForgeMath = env.require(Shared.ForgeMath)

local minutes = tonumber(process.args[1]) or 60
local seed = tonumber(process.args[2]) or 1

local profiles = {
	{ label = "free auto 1.5x", luck = 1.5, mode = "free" },
	{ label = "manual 2.5x", luck = 2.5, mode = "manual" },
	{ label = "paid auto 4x", luck = 4, mode = "premium" },
	{ label = "skilled 5x", luck = 5, mode = "manual" },
}

local tracks = {}
for _, t in Balance.machineTracks do
	table.insert(tracks, t)
end
for _, t in Balance.gearTracks do
	table.insert(tracks, t)
end

local function run(profile)
	local p = Economy.newProfile()
	local rng = env.Random.new(seed)
	local clock, forges, starved = 0, 0, 0
	local reached = { [1] = 0 }
	while clock < minutes * 60 do
		local timing = Economy.forgeTiming(p, profile.mode)
		local cycle = timing.heatSec + timing.windowSec + timing.revealSec
		Economy.settle(p, cycle, Economy.rates(p))
		clock += cycle
		-- forge the best material that has ingots
		local material = nil
		for index = p.unlockedTier, 1, -1 do
			if p.ingots[index] > 0 then
				material = index
				break
			end
		end
		if material and Economy.completeForge(p, material, 1, profile.luck, rng, clock) then
			forges += 1
			Economy.resolvePending(p, "sell")
		else
			starved += 1
		end
		while Economy.unlockNextMaterial(p) do
			reached[p.unlockedTier] = clock
		end
		local nextMat = Materials[p.unlockedTier + 1]
		local budget = if nextMat then 0.2 * nextMat.unlockCost else math.huge
		for _, track in tracks do
			local cost = Balance.upgradeCost(track, Economy.trackLevel(p, track) or 0)
			if cost and cost <= budget then
				Economy.buyUpgrade(p, track)
			end
		end
	end
	return p, reached, forges, starved
end

print(`Forge Frenzy economy sim: {minutes} min, seed {seed}`)
for _, profile in profiles do
	local p, reached, forges, starved = run(profile)
	local marks = {}
	for tier = 2, p.unlockedTier do
		if reached[tier] and (tier <= 6 or tier % 4 == 0 or tier == p.unlockedTier) then
			table.insert(marks, `{Materials[tier].name} {string.format("%.1f", reached[tier] / 60)}m`)
		end
	end
	print(string.format("\n%-15s tier %2d (%s)  forges %d  starved cycles %d  lifetime %s",
		profile.label, p.unlockedTier, Materials[p.unlockedTier].name, forges, starved, ForgeMath.formatCoins(p.lifetimeCoins)))
	print("  " .. table.concat(marks, ", "))
	local levels = {}
	for _, track in tracks do
		table.insert(levels, `{track} {Economy.trackLevel(p, track)}`)
	end
	print("  " .. table.concat(levels, ", "))
end
