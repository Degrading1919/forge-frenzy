--!strict
-- Thin wrapper over ReplicatedStorage.Remotes (see Shared.Protocol).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}
local remotes: Folder
local handlers: { [string]: { (any) -> () } } = {}

function Net.init()
	remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	(remotes:WaitForChild("Push") :: RemoteEvent).OnClientEvent:Connect(function(kind: string, payload: any)
		for _, fn in handlers[kind] or {} do
			task.spawn(fn, payload)
		end
	end)
end

-- Returns (ok, result). Never throws.
function Net.call(action: string, ...: any): (boolean, any)
	local fn = remotes:WaitForChild("Action") :: RemoteFunction
	local ok, a, b = pcall(fn.InvokeServer, fn, action, ...)
	if not ok then
		return false, tostring(a)
	end
	return a == true, b
end

function Net.strike(sessionId: string)
	(remotes:WaitForChild("Strike") :: RemoteEvent):FireServer(sessionId)
end

function Net.on(kind: string, fn: (any) -> ())
	handlers[kind] = handlers[kind] or {}
	table.insert(handlers[kind], fn)
end

return Net
