--[[
	Lune environment for running Studio-style modules from the repo (run from the repo root).

	Builds a virtual instance tree from default.project.json and shims the few Roblox globals the
	pure modules and services touch (Random, Instance.new("BindableEvent"), Players, task,
	Color3). Anything needing real DataStores, physics or UI still has to be tested in Studio.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")
local roblox = require("@lune/roblox")

local ROOT = process.cwd

-- Signals / BindableEvent -------------------------------------------------------------------
local function newSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		table.insert(handlers, fn)
		return {
			Disconnect = function()
				local i = table.find(handlers, fn)
				if i then
					table.remove(handlers, i)
				end
			end,
		}
	end
	function signal:Wait()
		local thread = coroutine.running()
		local conn
		conn = signal:Connect(function(...)
			conn.Disconnect()
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end
	signal._fire = function(...)
		for _, fn in table.clone(handlers) do
			fn(...)
		end
	end
	return signal
end

local Instance = {
	new = function(className)
		assert(className == "BindableEvent", "lune shim only supports BindableEvent, got " .. tostring(className))
		local event = newSignal()
		return {
			ClassName = "BindableEvent",
			Event = event,
			Fire = function(_, ...)
				event._fire(...)
			end,
		}
	end,
}

-- Random (xorshift128; Roblox's real Random is used in Studio) ----------------------------------
local Random = {}
Random.__index = Random
function Random.new(seed)
	local s = math.floor(seed or os.clock() * 1e6) % 4294967296
	local self = setmetatable({}, Random)
	-- splitmix-style spread of the seed into four nonzero words
	self._x = bit32.bxor(s, 0x9E3779B9)
	self._y = bit32.bxor(bit32.lrotate(s, 7), 0x243F6A88)
	self._z = bit32.bxor(bit32.lrotate(s, 19), 0xB7E15162)
	self._w = bit32.bxor(bit32.bnot(s), 0x85A308D3)
	for _ = 1, 16 do
		self:_next32()
	end
	return self
end
function Random:_next32()
	local t = bit32.bxor(self._x, bit32.lshift(self._x, 11))
	self._x, self._y, self._z = self._y, self._z, self._w
	self._w = bit32.bxor(self._w, bit32.rshift(self._w, 19), t, bit32.rshift(t, 8))
	return self._w
end
function Random:NextNumber(min, max)
	local hi = self:_next32()
	local lo = self:_next32()
	local x = (hi * 2097152 + (lo % 2097152)) / 9007199254740992 -- 53 bits
	if min then
		return min + x * (max - min)
	end
	return x
end
function Random:NextInteger(min, max)
	return min + math.floor(self:NextNumber() * (max - min + 1))
end

-- Virtual instance tree ------------------------------------------------------------------------
local Node = {}
Node.__index = function(self, key)
	local method = rawget(Node, key)
	if method then
		return method
	end
	local child = self:FindFirstChild(key)
	if child then
		return child
	end
	error(`{key} is not a valid member of {rawget(self, "Name")}`, 2)
end

local function newNode(name, parent, dir, file)
	return setmetatable({ Name = name, Parent = parent, _dir = dir, _file = file, _children = nil }, Node)
end

local function scriptName(entry)
	for _, suffix in { ".server.luau", ".client.luau", ".luau" } do
		if entry:sub(-#suffix) == suffix then
			return entry:sub(1, -#suffix - 1)
		end
	end
	return nil
end

-- Lune's fs calls yield, which is not allowed inside __index, so the tree and sources are
-- read eagerly before any module runs.
local sources = {}
local function populate(node)
	local children = {}
	local dir = rawget(node, "_dir")
	if dir and fs.isDir(dir) then
		local entries = fs.readDir(dir)
		table.sort(entries)
		for _, entry in entries do
			local full = dir .. "/" .. entry
			if fs.isDir(full) then
				local init = full .. "/init.luau"
				local child = newNode(entry, node, full, if fs.isFile(init) then init else nil)
				populate(child)
				table.insert(children, child)
			else
				local name = scriptName(entry)
				if name and name ~= "init" then
					table.insert(children, newNode(name, node, nil, full))
				end
			end
		end
	end
	for _, child in children do
		local file = rawget(child, "_file")
		if file then
			sources[file] = fs.readFile(file)
		end
	end
	rawset(node, "_children", children)
end

function Node.GetChildren(self)
	return rawget(self, "_children") or {}
end

function Node.FindFirstChild(self, name)
	for _, child in Node.GetChildren(self) do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function Node.WaitForChild(self, name)
	return Node.FindFirstChild(self, name) or error(`WaitForChild: {name} not found under {self.Name}`)
end

-- Fresh copy with its own require cache entry (specs Clone a module to get clean state).
function Node.Clone(self)
	local copy = newNode(rawget(self, "Name"), rawget(self, "Parent"), rawget(self, "_dir"), rawget(self, "_file"))
	rawset(copy, "_children", rawget(self, "_children"))
	return copy
end

function Node.IsA(self, className)
	if className == "ModuleScript" then
		return rawget(self, "_file") ~= nil
	end
	return className == "Instance"
end

-- Services ---------------------------------------------------------------------------------------
local services = {}
local game = {}
function game.GetService(_, name)
	local svc = services[name]
	assert(svc, "lune shim has no service " .. tostring(name))
	return svc
end

local project = serde.decode("json", fs.readFile(ROOT .. "/default.project.json"))
for serviceName, node in project.tree do
	if type(node) == "table" and not serviceName:match("^%$") then
		local root = newNode(serviceName, game, nil, nil)
		local mounts = {}
		for childName, child in node do
			if type(child) == "table" and child["$path"] then
				local mount = newNode(childName, root, ROOT .. "/" .. child["$path"], nil)
				populate(mount)
				table.insert(mounts, mount)
			end
		end
		rawset(root, "_children", mounts)
		services[serviceName] = root
	end
end

local Players = newNode("Players", game, nil, nil)
rawset(Players, "_children", {})
rawset(Players, "PlayerAdded", newSignal())
rawset(Players, "PlayerRemoving", newSignal())
rawset(Players, "GetPlayers", function()
	return {}
end)
services.Players = Players
-- Inert stand-ins so world-glue modules (Net/Plots) can load for their pure helpers.
services.HttpService = {
	JSONEncode = function(_, value)
		return serde.encode("json", value)
	end,
	JSONDecode = function(_, text)
		return serde.decode("json", text)
	end,
}
services.ServerStorage = newNode("ServerStorage", game, nil, nil)
rawset(services.ServerStorage, "_children", {})
services.RunService = {
	IsStudio = function()
		return true
	end,
	IsServer = function()
		return true
	end,
}

-- require ----------------------------------------------------------------------------------------
local cache = {}
local requireModule

local function makeEnv(node)
	return {
		script = node,
		game = game,
		workspace = {},
		Instance = Instance,
		Random = Random,
		Color3 = roblox.Color3,
		task = task,
		require = requireModule,
		__LUNE__ = true,
	}
end

requireModule = function(node)
	if type(node) == "string" then
		return require(node)
	end
	if cache[node] ~= nil then
		return cache[node]
	end
	local file = rawget(node, "_file")
	assert(file, "cannot require " .. tostring(rawget(node, "Name")))
	local chunk = luau.load(sources[file], {
		debugName = file:sub(#ROOT + 2),
		environment = makeEnv(node),
	})
	local result = chunk()
	cache[node] = result
	return result
end

return {
	root = ROOT,
	game = game,
	services = services,
	require = requireModule,
	Random = Random,
}
