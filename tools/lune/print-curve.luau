-- Prints the generated v2 material curve (docs/23): per-ingot band, sample weapon values, prices.
--     lune run tools/lune/print-curve.luau
local env = require("./env")
local Shared = env.services.ReplicatedStorage.Shared
local Materials = env.require(Shared.Config.Materials)
local ForgeMath = env.require(Shared.ForgeMath)
local BuildPads = env.require(Shared.Config.BuildPads)
local Eggs = env.require(Shared.Config.Eggs)
local f = ForgeMath.formatCoins
print("tier material      unlock    dagger(avg@1.5)  greatsword(avg@1.5)  best possible")
for i, m in Materials do
	print(string.format("%2d  %-12s $%-8s $%-14s $%-18s $%s", i, m.name, f(m.unlockCost), f(ForgeMath.expectedValue(i, 1.5, 4)), f(ForgeMath.expectedValue(i, 1.5, 2)), f(ForgeMath.maxValue(i))))
end
for _, pad in BuildPads.List do
	print(string.format("pad %-16s tier %2d  $%s", pad.id, pad.tier, f(pad.cost)))
end
for _, egg in Eggs.List do
	print(string.format("egg %-16s tier %2d  $%s", egg.id, egg.unlockTier, f(egg.coinCost)))
end
