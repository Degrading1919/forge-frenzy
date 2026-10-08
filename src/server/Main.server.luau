--!strict
-- Server bootstrap: init/start every gameplay service, then the network + world glue in Net/.
local function loadFolder(folder: Instance?): { { name: string, mod: any } }
	local list = {}
	if not folder then
		return list
	end
	for _, m in folder:GetChildren() do
		if m:IsA("ModuleScript") then
			local ok, mod = pcall(require, m)
			if ok then
				table.insert(list, { name = m.Name, mod = mod })
			else
				warn("[Server] failed to load", m:GetFullName(), mod)
			end
		end
	end
	return list
end

local modules = loadFolder(script.Parent:FindFirstChild("Services"))
for _, m in loadFolder(script.Parent:FindFirstChild("Net")) do
	table.insert(modules, m)
end

for _, entry in modules do
	if type(entry.mod) == "table" and entry.mod.init then
		local ok, err = pcall(entry.mod.init)
		if not ok then warn("[Server] init failed", entry.name, err) end
	end
end
for _, entry in modules do
	if type(entry.mod) == "table" and entry.mod.start then
		task.spawn(function()
			local ok, err = pcall(entry.mod.start)
			if not ok then warn("[Server] start failed", entry.name, err) end
		end)
	end
end
print(string.format("[Forge Frenzy] server ready (%d modules)", #modules))
