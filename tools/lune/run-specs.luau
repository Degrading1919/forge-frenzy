--[[
	Runs src/server/Tests/*.spec.luau under Lune, outside Studio.

	  lune run tools/lune/run-specs.luau                 -- every spec
	  lune run tools/lune/run-specs.luau Companion Evo   -- specs whose name contains a filter

	Specs return { [testName] = function() ... end } and fail by erroring (assert).
	Exit code is non-zero if any test fails.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local Loader = require("./loader")

Loader.init(".")

local filters = process.args
local files = {}
for _, entry in fs.readDir("src/server/Tests") do
	local name = string.match(entry, "^(.+%.spec)%.luau$")
	if name then
		local wanted = #filters == 0
		for _, filter in filters do
			if string.find(name, filter, 1, true) then
				wanted = true
			end
		end
		if wanted then
			table.insert(files, name)
		end
	end
end
table.sort(files)

local passed, failed = 0, 0
for _, name in files do
	local okLoad, spec = pcall(Loader.load, "src/server/Tests/" .. name)
	if not okLoad then
		failed += 1
		print(`FAIL {name} (load): {spec}`)
		continue
	end
	local testNames = {}
	for testName in spec do
		table.insert(testNames, testName)
	end
	table.sort(testNames)
	for _, testName in testNames do
		local ok, err = pcall(spec[testName])
		if ok then
			passed += 1
			print(`  ok   {name} :: {testName}`)
		else
			failed += 1
			print(`  FAIL {name} :: {testName}\n       {err}`)
		end
	end
end

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
