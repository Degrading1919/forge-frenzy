--[[
	Roblox-style module loader so src/ modules and src/server/Tests specs run under Lune
	(https://lune-org.github.io), outside Studio.

	Emulates only what pure modules need, following default.project.json:
	  * script / .Parent / child indexing / WaitForChild / FindFirstChild / Clone
	  * game:GetService("ReplicatedStorage").Shared  -> src/shared
	  * game:GetService("ServerScriptService").Server -> src/server
	  * globals: Color3 (from @lune/roblox), a seeded Random, warn
	Anything else (Players, DataStoreService, Instance, task loops) is deliberately absent:
	modules must keep Roblox service use inside init()/start().
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Loader = {}

local root = "."
local cache: { [string]: any } = {}
-- Lune's fs calls can yield, which is not allowed inside __index, so the tree is scanned
-- once up front: dirs[path] = sorted child names, files[path without .luau] = source.
local dirs: { [string]: { string } } = {}
local files: { [string]: string } = {}

local function scan(dir: string)
	if not fs.isDir(dir) then
		return
	end
	local names = {}
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			table.insert(names, entry)
			scan(full)
		else
			local stem = string.match(entry, "^(.*)%.luau$")
			if stem then
				files[dir .. "/" .. stem] = fs.readFile(full)
				if stem ~= "init" then
					table.insert(names, stem)
				end
			end
		end
	end
	table.sort(names)
	dirs[dir] = names
end
local nodeMeta = {}

local function makeNode(path: string, parentPath: string?, fresh: boolean?)
	return setmetatable({ __path = path, __parent = parentPath, __fresh = fresh }, nodeMeta)
end

local function childOf(node, name: string)
	local path = node.__path .. "/" .. name
	if dirs[path] or files[path] then
		return makeNode(path, node.__path)
	end
	return nil
end

nodeMeta.__index = function(node, key)
	if key == "Parent" then
		local parentPath = rawget(node, "__parent")
		if parentPath == nil then
			return nil
		end
		return makeNode(parentPath, string.match(parentPath, "^(.*)/[^/]+$"))
	elseif key == "Name" then
		return string.match(node.__path, "([^/]+)$")
	elseif key == "WaitForChild" or key == "FindFirstChild" then
		return function(self, name)
			local child = childOf(self, name)
			if child == nil and key == "WaitForChild" then
				error("Infinite yield possible on " .. self.__path .. "/" .. name)
			end
			return child
		end
	elseif key == "Clone" then
		-- Roblox: require(module:Clone()) yields a fresh module instance with no Parent.
		return function(self)
			return makeNode(self.__path, nil, true)
		end
	elseif key == "GetChildren" then
		return function(self)
			local out = {}
			for _, name in dirs[self.__path] or {} do
				table.insert(out, makeNode(self.__path .. "/" .. name, self.__path))
			end
			return out
		end
	end
	local child = childOf(node, key)
	if child == nil then
		error(string.format("%s is not a valid member of %s", tostring(key), node.__path))
	end
	return child
end

-- Seeded PRNG matching the subset of Roblox's Random API we use.
local Random = {}
Random.__index = Random
local seedCounter = 0
function Random.new(seed: number?)
	if seed == nil then
		seedCounter += 1
		seed = os.time() + seedCounter
	end
	local s = math.floor(seed :: number) % 4294967296
	if s == 0 then
		s = 0x9E3779B9
	end
	return setmetatable({ state = s }, Random)
end
function Random:NextNumber(min: number?, max: number?): number
	-- xorshift32
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	local unit = x / 4294967296
	if min ~= nil and max ~= nil then
		return min + unit * (max - min)
	end
	return unit
end
function Random:NextInteger(min: number, max: number): number
	return min + math.floor(self:NextNumber() * (max - min + 1))
end

local services: { [string]: any } = {}
local fakeGame = {
	GetService = function(_, name: string)
		return services[name] or error("Service not emulated under Lune: " .. name)
	end,
}

local requireNode

local function makeEnv(scriptNode)
	return {
		script = scriptNode,
		game = fakeGame,
		Color3 = roblox.Color3,
		Random = Random,
		warn = function(...)
			if Loader.verbose then
				print("[warn]", ...)
			end
		end,
		require = function(target)
			if type(target) == "table" and rawget(target, "__path") then
				return requireNode(target)
			end
			error("Lune loader only supports instance-style require, got " .. tostring(target))
		end,
	}
end

function requireNode(node)
	local path = node.__path
	local fresh = rawget(node, "__fresh")
	if not fresh and cache[path] ~= nil then
		return cache[path]
	end
	local source = files[path] or files[path .. "/init"]
	if source == nil then
		error("No module at " .. path)
	end
	local chunk = luau.load(source, { debugName = path, environment = makeEnv(node) })
	local result = chunk()
	if not fresh then
		cache[path] = result
	end
	return result
end

local function container(childName: string, dir: string)
	local function get()
		return makeNode(root .. "/" .. dir, nil)
	end
	return setmetatable({}, {
		__index = function(_, key)
			if key == childName then
				return get()
			elseif key == "WaitForChild" or key == "FindFirstChild" then
				return function(_, name)
					return if name == childName then get() else nil
				end
			end
			error(tostring(key) .. " is not emulated under Lune")
		end,
	})
end

function Loader.init(repoRoot: string?)
	root = repoRoot or "."
	table.clear(cache)
	table.clear(dirs)
	table.clear(files)
	scan(root .. "/src")
	services.ReplicatedStorage = container("Shared", "src/shared")
	services.ServerScriptService = container("Server", "src/server")
	return Loader
end

-- Load a module by repo-relative path without extension.
function Loader.load(relPath: string)
	local full = root .. "/" .. relPath
	return requireNode(makeNode(full, string.match(full, "^(.*)/[^/]+$")))
end

return Loader
