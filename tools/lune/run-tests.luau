--[[
	Runs src/server/Tests/*.spec.luau outside Studio with Lune (https://lune-org.github.io),
	then sanity-checks the generated v2 economy curve (materials, pads, eggs, tracks).

	    lune run tools/lune/run-tests.luau [filter]
]]

local process = require("@lune/process")
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

-- v2 economy curve sanity ---------------------------------------------------------------------
-- The v0 numbers in design/balance-v0.json are superseded by the generated v2 curve
-- (Config/Materials, docs/22-23). These checks pin the shape of the curve, not its tuning.
if not filter or ("balance-sync"):find(filter, 1, true) or ("curve"):find(filter, 1, true) then
	print("balance-sync (v2 curve sanity)")
	local Shared = services.ReplicatedStorage.Shared
	local Materials = requireModule(Shared.Config.Materials)
	local Balance = requireModule(Shared.Config.Balance)
	local BuildPads = requireModule(Shared.Config.BuildPads)
	local Eggs = requireModule(Shared.Config.Eggs)
	local ForgeMath = requireModule(Shared.ForgeMath)
	local function check(label, fn)
		local ok, err = pcall(fn)
		report(ok, label, err)
	end
	local function finitePositive(n)
		return type(n) == "number" and n == n and n > 0 and n < math.huge
	end
	check("32 materials with sequential indices and unique ids", function()
		assert(#Materials == 32, "material count " .. #Materials)
		local ids = {}
		for i, m in Materials do
			assert(m.index == i, "index at " .. i)
			assert(not ids[m.id], "duplicate id " .. m.id)
			ids[m.id] = true
		end
	end)
	check("priceMin and unlockCost strictly increase; Copper is free", function()
		assert(Materials[1].unlockCost == 0, "Copper unlock must be free")
		assert(finitePositive(Materials[1].priceMin))
		assert(Materials[2].unlockCost > 0, "Tin must cost something")
		for i = 2, #Materials do
			assert(Materials[i].priceMin > Materials[i - 1].priceMin, "priceMin not increasing at " .. i)
			if i > 2 then
				assert(Materials[i].unlockCost > Materials[i - 1].unlockCost, "unlockCost not increasing at " .. i)
			end
			assert(finitePositive(Materials[i].unlockCost) and Materials[i].unlockCost <= Balance.maxCoins, "unlockCost range at " .. i)
		end
	end)
	check("priceMax is about bandRatio x priceMin for every material", function()
		for i, m in Materials do
			local ratio = m.priceMax / m.priceMin
			assert(ratio >= 17 and ratio <= 19, `material {i} band ratio {ratio}`)
		end
	end)
	check("value ratio between tiers stays between 2x and 3x", function()
		for i = 2, #Materials do
			local ratio = Materials[i].priceMin / Materials[i - 1].priceMin
			assert(ratio >= 2.0 and ratio <= 3.05, `tier {i} ratio {ratio}`)
		end
	end)
	check("Primordium's best weapon exceeds 1e15 and stays under the cash ceiling", function()
		local best = ForgeMath.maxValue(32)
		assert(best > 1e15, "maxValue " .. best)
		assert(best < Balance.maxCoins, "maxValue above the cash ceiling")
		for i = 2, #Materials do
			assert(ForgeMath.maxValue(i) > ForgeMath.maxValue(i - 1), "maxValue not increasing at " .. i)
		end
	end)
	check("weapon classes: five, bigger recipes are worth more per forge", function()
		assert(#Balance.weaponClasses == 5)
		local seen = {}
		for _, class in Balance.weaponClasses do
			assert(not seen[class.id], "duplicate class " .. class.id)
			seen[class.id] = true
			assert(class.ingots >= 1 and class.ingots == math.floor(class.ingots))
			assert(class.valueMult > 0)
		end
		local ordered = table.clone(Balance.weaponClasses)
		table.sort(ordered, function(a, b) return a.ingots < b.ingots end)
		for i = 2, #ordered do
			assert(ordered[i].valueMult > ordered[i - 1].valueMult, "value must rise with recipe size")
		end
	end)
	check("every pad cost is positive and finite", function()
		assert(#BuildPads.List > 0)
		for _, pad in BuildPads.List do
			assert(finitePositive(pad.cost) and pad.cost <= Balance.maxCoins, pad.id)
		end
	end)
	check("every egg cost is positive and finite and rises with its tier", function()
		assert(#Eggs.List > 0)
		local last = 0
		for _, egg in Eggs.List do
			assert(finitePositive(egg.coinCost), egg.id)
			assert(egg.coinCost > last, egg.id .. " is not dearer than the previous egg")
			last = egg.coinCost
		end
	end)
	check("every upgrade level costs a positive finite amount", function()
		for name, def in Balance.tracks do
			for level = 0, def.maxLevel - 1 do
				assert(finitePositive(Balance.upgradeCost(name, level)), `{name} level {level}`)
			end
		end
	end)
end

print(string.format("\n%d passed, %d failed", passed, failed))
process.exit(if failed == 0 then 0 else 1)
