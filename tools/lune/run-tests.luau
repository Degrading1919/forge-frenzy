--[[
	Runs src/server/Tests/*.spec.luau outside Studio with Lune (https://lune-org.github.io),
	then checks Config/Materials and Config/Balance against design/balance-v0.json.

	    lune run tools/lune/run-tests.luau [filter]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local env = require("./env")

local ROOT = env.root
local filter = process.args[1]
local services = env.services
local requireModule = env.require

-- Run specs --------------------------------------------------------------------------------------
local passed, failed = 0, 0
local function report(ok, label, err)
	if ok then
		passed += 1
		print("  PASS " .. label)
	else
		failed += 1
		print("  FAIL " .. label .. "\n       " .. tostring(err))
	end
end

local testsNode = services.ServerScriptService.Server.Tests
for _, spec in testsNode:GetChildren() do
	if spec.Name:match("%.spec$") and (not filter or spec.Name:find(filter, 1, true)) then
		print(spec.Name)
		local okLoad, tests = pcall(requireModule, spec)
		if not okLoad then
			report(false, "<load>", tests)
		else
			local names = {}
			for name in tests do
				table.insert(names, name)
			end
			table.sort(names)
			for _, name in names do
				local ok, err = pcall(tests[name])
				report(ok, name, err)
			end
		end
	end
end

-- design/balance-v0.json sync ---------------------------------------------------------------------
if not filter or ("balance-sync"):find(filter, 1, true) then
	print("balance-sync (design/balance-v0.json)")
	local json = serde.decode("json", fs.readFile(ROOT .. "/design/balance-v0.json"))
	local Shared = services.ReplicatedStorage.Shared
	local Materials = requireModule(Shared.Config.Materials)
	local Balance = requireModule(Shared.Config.Balance)
	local function check(label, fn)
		local ok, err = pcall(fn)
		report(ok, label, err)
	end
	check("materials match", function()
		assert(#Materials == #json.materials, "material count differs")
		for i, m in json.materials do
			local c = Materials[i]
			for _, pair in { { "id", "id" }, { "name", "name" }, { "index", "index" }, { "era", "era" }, { "priceMin", "priceMin" }, { "priceMax", "priceMax" }, { "extractorUnlockCoinCost", "unlockCost" } } do
				assert(m[pair[1]] == c[pair[2]], `material {i} {pair[2]}: json {m[pair[1]]} vs config {c[pair[2]]}`)
			end
		end
	end)
	check("weapon classes match", function()
		for i, name in json.weaponClasses do
			assert(Balance.weaponClasses[i].id == name, "class " .. i)
		end
		assert(#Balance.weaponClasses == #json.weaponClasses)
	end)
	check("forge tables match", function()
		local f, jf = Balance.forge, json.forge
		assert(f.manual.strikeWindowSec == jf.manual.strikeWindowSec)
		assert(f.manual.baseLuck == jf.manual.baseLuck)
		assert(f.manual.luckPerCps == jf.manual.luckPerCps)
		assert(f.manual.maxLuck == jf.manual.maxLuck)
		assert(f.manual.inputRateGuardCps == jf.manual.inputRateGuardCps)
		assert(f.auto.freeLuck == jf.auto.freeLuck and f.auto.premiumLuck == jf.auto.premiumLuck)
		assert(f.timing.baseHeatSec == jf.timing.baseHeatSec)
		assert(f.timing.baseQuenchAndRevealSec == jf.timing.baseQuenchAndRevealSec)
		assert(f.materialUnitsPerRoll == jf.materialUnitsPerRoll)
		for i, v in jf.rarity.baseChancePercent do
			assert(f.rarity.baseChancePercent[i] == v, "rarity chance " .. i)
			assert(f.rarity.valueBandPositions[i] == jf.rarity.valueBandPositions[i], "band " .. i)
			assert(f.rarity.names[i] == jf.rarity.names[i], "rarity name " .. i)
			assert(f.trait.baseChanceByRarityPercent[i] == jf.trait.baseChanceByRarityPercent[i], "trait " .. i)
		end
		for _, name in jf.rarity.scaledWithLuck do
			assert(table.find(f.rarity.scaledWithLuck, table.find(f.rarity.names, name)), "scaled " .. name)
		end
		assert(f.rarity.names[f.rarity.remainder] == jf.rarity.remainderCategory)
		for i, v in jf.craftsmanship.baseChancePercent do
			assert(f.craftsmanship.baseChancePercent[i] == v, "craft chance " .. i)
			assert(f.craftsmanship.valueBandOffsets[i] == jf.craftsmanship.valueBandOffsets[i], "craft offset " .. i)
		end
		assert(f.trait.bonusToValuePosition == jf.trait.bonusToValuePosition)
		for key, v in jf.payout do
			assert(f.payout[key] == v, "payout " .. key)
		end
	end)
	check("production matches", function()
		local p, jp = Balance.production, json.production
		for _, key in { "baseOreIntervalSec", "baseSmeltIntervalSec", "maxOlderMaterialRateMultiplier", "olderMaterialRateMultiplierPerTier", "baseIngotStorageCapacity", "maxConfiguredProductionFamilyMultiplier" } do
			assert(p[key] == jp[key], key)
		end
	end)
end

print(string.format("\n%d passed, %d failed", passed, failed))
process.exit(if failed == 0 then 0 else 1)
