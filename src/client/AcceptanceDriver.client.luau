--!nonstrict
--[[
	Studio-only client half of the multiplayer acceptance (src/server/Tests/MultiplayerAcceptance).
	Does nothing in live servers, and nothing in Studio unless the acceptance run creates
	ReplicatedStorage.FFAcceptanceDriver.

	The server asks a real client to use the real world prompts the way a player does:
	  prompt {plot, slot}           read the steal prompt (enabled, hold time, text, keys)
	  hold {plot?, slot?, lock?, sec}  ProximityPrompt:InputHoldBegin, wait, InputHoldEnd
	  walk {x, y, z}                walk there with Humanoid:MoveTo (real character physics)
	  ui                            what this player sees: toasts, banners, carry marker
	InputHoldBegin/End is the prompt's own input API; it runs the same PromptButtonHoldBegan,
	PromptButtonHoldEnded and Triggered path as holding E, ButtonX or a touch.
]]
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local toasts = {}
local function hookToasts()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	local push = remotes and remotes:WaitForChild("Push", 30)
	if push then
		push.OnClientEvent:Connect(function(kind, payload)
			if kind == "Toast" and type(payload) == "table" then
				table.insert(toasts, tostring(payload.text))
			end
		end)
	end
end

local function stealPrompt(plotIndex: number, slot: number): ProximityPrompt?
	local plot = workspace:FindFirstChild("World") and workspace.World.Plots:FindFirstChild("Plot" .. plotIndex)
	local ped = plot and plot.Showcase:FindFirstChild("Pedestal" .. slot)
	local spot = ped and ped:FindFirstChild("DisplaySpot", true)
	return spot and spot:FindFirstChild("WorldPrompt")
end

local function lockPrompt(): ProximityPrompt?
	local index = player:GetAttribute("PlotIndex")
	local plot = index and workspace.World.Plots:FindFirstChild("Plot" .. index)
	local point = plot and plot:FindFirstChild("LockButton") and plot.LockButton:FindFirstChild("PromptPoint")
	return point and point:FindFirstChild("WorldPrompt")
end

local function visibleText(match: string): string?
	for _, d in player.PlayerGui:GetDescendants() do
		if d:IsA("TextLabel") and d.Visible and d.Text:find(match, 1, true) then
			local shown = true
			local node = d.Parent
			while node and node:IsA("GuiObject") do
				if not node.Visible then
					shown = false
					break
				end
				node = node.Parent
			end
			if shown then
				return d.Text
			end
		end
	end
	return nil
end

local handlers = {}
function handlers.prompt(args)
	local p = stealPrompt(args.plot, args.slot)
	if not p then
		return { found = false }
	end
	return {
		found = true,
		enabled = p.Enabled,
		hold = p.HoldDuration,
		action = p.ActionText,
		object = p.ObjectText,
		keyboard = p.KeyboardKeyCode.Name,
		gamepad = p.GamepadKeyCode.Name,
		clickable = p.ClickablePrompt,
		range = p.MaxActivationDistance,
	}
end
function handlers.hold(args)
	local p = if args.lock then lockPrompt() else stealPrompt(args.plot, args.slot)
	if not p then
		return { found = false }
	end
	local began, triggered = false, false
	local c1 = p.PromptButtonHoldBegan:Connect(function() began = true end)
	local c2 = p.Triggered:Connect(function() triggered = true end)
	local enabled = p.Enabled
	local t0 = os.clock()
	p:InputHoldBegin()
	task.wait(args.sec or 0.1)
	p:InputHoldEnd()
	task.wait(0.3)
	c1:Disconnect()
	c2:Disconnect()
	return { found = true, enabled = enabled, began = began, triggered = triggered, heldFor = os.clock() - t0 }
end
function handlers.walk(args)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return { arrived = false }
	end
	local target = Vector3.new(args.x, args.y, args.z)
	local t0 = os.clock()
	local speed = humanoid.WalkSpeed
	while os.clock() - t0 < 30 do
		local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
		if flat.Magnitude < 4 then
			return { arrived = true, elapsed = os.clock() - t0, walkSpeed = speed }
		end
		humanoid:MoveTo(target)
		task.wait(0.25)
	end
	return { arrived = false, elapsed = os.clock() - t0, walkSpeed = speed }
end
function handlers.ui(args)
	return {
		toasts = toasts,
		banner = visibleText(args and args.banner or "RUN HOME"),
		carrying = player:GetAttribute("Carrying"),
	}
end
function handlers.clear()
	table.clear(toasts)
	return true
end

local function attach(driver: RemoteEvent)
	driver.OnClientEvent:Connect(function(requestId, command, args)
		local handler = handlers[command]
		local ok, result = pcall(function()
			return if handler then handler(args or {}) else { error = "unknown command" }
		end)
		driver:FireServer(requestId, if ok then result else { error = tostring(result) })
	end)
	driver:FireServer("ready", { userId = player.UserId })
end

task.spawn(hookToasts)
local existing = ReplicatedStorage:FindFirstChild("FFAcceptanceDriver")
if existing then
	attach(existing)
else
	local conn
	conn = ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "FFAcceptanceDriver" and child:IsA("RemoteEvent") then
			conn:Disconnect()
			attach(child)
		end
	end)
end
