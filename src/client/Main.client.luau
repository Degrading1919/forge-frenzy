--!strict
-- Client bootstrap: wires Net + State, then init()/start() every controller in Controllers.
local Net = require(script.Parent.Net)
local State = require(script.Parent.State)

Net.init()
State.init(Net)

local controllers = {}
for _, m in script.Parent.Controllers:GetChildren() do
	if m:IsA("ModuleScript") then
		local ok, c = pcall(require, m)
		if ok then
			table.insert(controllers, { name = m.Name, c = c })
		else
			warn("[Client] failed to load", m.Name, c)
		end
	end
end
table.sort(controllers, function(a, b)
	return (a.c.Priority or 0) > (b.c.Priority or 0)
end)
for _, entry in controllers do
	if entry.c.init then
		local ok, err = pcall(entry.c.init)
		if not ok then warn("[Client] init", entry.name, err) end
	end
end
for _, entry in controllers do
	if entry.c.start then
		task.spawn(function()
			local ok, err = pcall(entry.c.start)
			if not ok then warn("[Client] start", entry.name, err) end
		end)
	end
end
