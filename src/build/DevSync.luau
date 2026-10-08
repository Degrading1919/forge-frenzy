-- Mirrors repo scripts into the open place. Usage (Studio command bar / MCP): require(game.ServerStorage.Build.DevSync)()
return function(url: string?)
	local HttpService = game:GetService("HttpService")
	local prev = HttpService.HttpEnabled
	HttpService.HttpEnabled = true
	local ok, raw = pcall(HttpService.GetAsync, HttpService, url or "http://127.0.0.1:34872/bundle")
	HttpService.HttpEnabled = prev
	assert(ok, raw)
	local bundle = HttpService:JSONDecode(raw)
	local seen, created, updated, removed = {}, 0, 0, 0
	local function resolve(path, class)
		local node = game:GetService(path[1])
		for i = 2, #path do
			local child = node:FindFirstChild(path[i])
			local isLeaf = i == #path
			if child and isLeaf and class and child.ClassName ~= class then
				-- class changed (e.g. Folder -> ModuleScript): move children across
				local replacement = Instance.new(class)
				replacement.Name = path[i]
				for _, c in child:GetChildren() do c.Parent = replacement end
				child:Destroy()
				replacement.Parent = node
				child = replacement
			end
			if not child then
				child = Instance.new(isLeaf and class or "Folder")
				child.Name = path[i]
				child.Parent = node
				created += 1
			end
			node = child
		end
		return node
	end
	for _, item in bundle.items do
		local inst = resolve(item.path, item.class)
		if item.source and inst.Source ~= item.source then
			if inst:IsA("ModuleScript") and inst.Name ~= "DevSync" then
				-- Replace changed modules so edit-mode require() caches can't serve stale code.
				local fresh = Instance.new("ModuleScript")
				fresh.Name = inst.Name
				fresh.Source = item.source
				for _, c in inst:GetChildren() do
					c.Parent = fresh
				end
				fresh.Parent = inst.Parent
				inst:Destroy()
				inst = fresh
			else
				inst.Source = item.source
			end
			updated += 1
		end
		seen[inst] = true
	end
	for _, rootPath in bundle.roots do
		local root = resolve(rootPath, nil)
		for _, d in root:GetDescendants() do
			if (d:IsA("LuaSourceContainer") or d:IsA("Folder")) and not seen[d] and d.Parent then
				d:Destroy()
				removed += 1
			end
		end
	end
	return string.format("synced %d items: %d created, %d updated, %d removed", #bundle.items, created, updated, removed)
end
