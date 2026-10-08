-- Runs every ServerScriptService.Server.Tests *.spec module inside Studio (edit mode).
-- Usage: return require(game.ServerStorage.Build.RunSpecs)(filter?)
-- Clones the Server folder first so each run gets fresh module state after a sync.
return function(filter: string?)
	local source = game:GetService("ServerScriptService"):FindFirstChild("Server")
	assert(source, "Server folder missing; run DevSync first")
	local temp = Instance.new("Folder")
	temp.Name = "SpecRun"
	temp.Parent = game:GetService("ServerStorage")
	local copy = source:Clone()
	-- Disable scripts in the copy so nothing boots.
	for _, d in copy:GetDescendants() do
		if d:IsA("Script") then
			d.Disabled = true
		end
	end
	copy.Parent = temp
	local passed, failed, lines = 0, 0, {}
	local tests = copy:FindFirstChild("Tests")
	for _, mod in (tests and tests:GetChildren() or {}) do
		if mod:IsA("ModuleScript") and (not filter or string.find(mod.Name, filter, 1, true)) then
			local okLoad, spec = pcall(require, mod)
			if not okLoad then
				failed += 1
				table.insert(lines, "FAIL " .. mod.Name .. " (load): " .. tostring(spec))
			else
				local names = {}
				for name in spec do
					table.insert(names, name)
				end
				table.sort(names)
				for _, name in names do
					local ok, err = pcall(spec[name])
					if ok then
						passed += 1
					else
						failed += 1
						table.insert(lines, "FAIL " .. mod.Name .. " / " .. name .. ": " .. tostring(err))
					end
				end
			end
		end
	end
	temp:Destroy()
	table.insert(lines, 1, string.format("%d passed, %d failed", passed, failed))
	return table.concat(lines, "\n")
end
