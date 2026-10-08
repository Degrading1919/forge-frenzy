--!nonstrict
--[[
	Onboarding v2 (docs/21 §14): one idea at a time, almost no reading.

	A short banner under the cash pill says what to do next ("Walk to your FORGE"), a glowing
	trail runs from your character to the target and a big bouncing arrow sits over it. Each step
	completes from real game state, so the loop is learned by doing:
	  forge -> forge 3 -> sell at the booth -> buy Tin -> Auto Forge -> build a pad -> display
	The banner hides while a panel or reveal is open so it never covers buttons.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Common = require(script.Parent.WorldUtil.Common)
local State = Common.State
local UI = Common.Client.UI
local Theme = require(UI.Theme)
local Panels = require(UI.Panels)
local Reveal = require(UI.Reveal)
local Toast = require(UI.Toast)
local Net = require(Common.Client.Net)

local WorldOnboarding = { Priority = 0 }
local C = Theme.Colors

local function hub()
	return Common.hub()
end

local function plotFind(...)
	local plot = Common.myPlot()
	return plot and Common.find(plot, ...)
end

local STEPS = {
	{
		text = "🔨 Walk to your FORGE and press BEGIN!",
		target = function() return plotFind("Machines", "Forge1", "Base") end,
		done = function(p) return (p.weaponsForged or 0) >= 1 end,
	},
	{
		text = "🔨 Forge 2 more weapons! Tap FAST for better luck",
		target = function() return plotFind("Machines", "Forge1", "Base") end,
		done = function(p) return (p.weaponsForged or 0) >= 3 end,
	},
	{
		text = "💰 Run to the SELL booth in town!",
		target = function() local h = hub(); return h and Common.find(h, "SellBooth", "Base") end,
		done = function(p) return (p.lifetimeCoins or 0) > 0 end,
	},
	{
		text = "⛏️ Buy TIN at your Ore Drill!",
		target = function() return plotFind("Machines", "Line1", "Drill", "Base") end,
		done = function(p) return (p.unlockedTier or 1) >= 2 end,
	},
	{
		text = "⚙️ Turn on AUTO FORGE at your forge!",
		target = function() return plotFind("Machines", "Forge1", "Base") end,
		done = function(p)
			for _, st in p.forgeStatus or {} do
				if st.auto then return true end
			end
			return false
		end,
	},
	{
		text = "🏗️ Step on a glowing pad to BUILD!",
		target = function()
			local pads = plotFind("BuildPads")
			return pads and pads:GetChildren()[1]
		end,
		done = function(p) return next(p.pads or {}) ~= nil end,
	},
	{
		text = "🏆 Put a weapon on a podium. It makes cash!",
		target = function() return plotFind("Showcase", "Pedestal1", "Top") end,
		done = function(p)
			for _, id in p.showcase or {} do
				if id ~= "" then return true end
			end
			return false
		end,
	},
}

local ui: any = {}
local step = 0
local finished = false

local function build()
	-- Lives inside the HUD's top cluster (already device-scaled), right under the cash pill.
	local layer = Panels.layer("Hud")
	local top = layer:FindFirstChild("Top")
	local banner = Theme.make("Frame", {
		Name = "Tutorial",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(470, 66),
		BackgroundColor3 = C.yellow,
		Corner = 18,
		Stroke = { Color = C.ink, Thickness = 4 },
		Visible = false,
		Parent = top or layer,
	})
	if not top then
		Theme.autoScale(banner)
	end
	ui.banner = banner
	ui.text = Theme.text({ Text = "", Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(60, 0), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.ink, TextStroke = false, Parent = banner })
	ui.count = Theme.text({ Text = "1", Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = C.orange, BackgroundTransparency = 0, Corner = 23, Stroke = { Color = C.ink, Thickness = 3 }, TextSize = 28, Parent = banner })
	Theme.pulse(banner, 0.03)
end

-- Trail + arrow toward the current target.
local trail = { beam = nil, a0 = nil, a1 = nil, arrow = nil, target = nil }

local function clearTrail()
	for _, key in { "beam", "a0", "a1", "arrow" } do
		if trail[key] then
			trail[key]:Destroy()
			trail[key] = nil
		end
	end
	trail.target = nil
end

local function pointAt(target: Instance?)
	if trail.target == target and trail.beam and trail.beam.Parent then
		return
	end
	clearTrail()
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not target or not root or not target:IsA("BasePart") then
		return
	end
	trail.target = target
	local a0 = Instance.new("Attachment")
	a0.Name = "TutorialFrom"
	a0.Position = Vector3.new(0, -2, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "TutorialTo"
	a1.Position = Vector3.new(0, target.Size.Y / 2 + 1, 0)
	a1.Parent = target
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(C.yellow, C.orange)
	beam.LightEmission = 0.6
	beam.Width0 = 1.4
	beam.Width1 = 1.4
	beam.FaceCamera = true
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Static
	beam.TextureLength = 3
	beam.TextureSpeed = 2
	beam.Transparency = NumberSequence.new(0.2)
	beam.Parent = root
	local arrow = Instance.new("BillboardGui")
	arrow.Name = "TutorialArrow"
	arrow.Adornee = target
	arrow.Size = UDim2.fromOffset(110, 110)
	arrow.StudsOffset = Vector3.new(0, 9, 0)
	arrow.AlwaysOnTop = true
	arrow.MaxDistance = 400
	local label = Theme.text({ Text = "⬇", Size = UDim2.new(1, 0, 1, 0), TextSize = 96, TextColor3 = C.yellow, Parent = arrow })
	label.Name = "Arrow"
	arrow.Parent = Common.player:WaitForChild("PlayerGui")
	trail.beam, trail.a0, trail.a1, trail.arrow = beam, a0, a1, arrow
end

local function currentStep(p: any): number
	local s = math.max(step, p.tutorial or 0)
	while s < #STEPS and STEPS[s + 1].done(p) do
		s += 1
	end
	return s
end

local function update()
	local p = State.profile
	if not p or finished then
		return
	end
	local s = currentStep(p)
	if s > step then
		step = s
		Net.call("TutorialStep", s)
		if s >= #STEPS then
			finished = true
			ui.banner.Visible = false
			clearTrail()
			Toast.show("You're a real blacksmith! Tip: LOCK your forge to stop thieves", "good")
			return
		end
		Theme.pop(ui.banner, 0.8)
	end
	local def = STEPS[step + 1]
	if not def then
		finished = true
		ui.banner.Visible = false
		clearTrail()
		return
	end
	local busy = Panels.isOpen() or Reveal.isOpen()
	ui.banner.Visible = not busy
	ui.text.Text = def.text
	ui.count.Text = tostring(step + 1)
	if busy then
		clearTrail()
	else
		local ok, target = pcall(def.target)
		pointAt(ok and target or nil)
	end
end

function WorldOnboarding.init()
	build()
end

function WorldOnboarding.start()
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		if trail.arrow then
			trail.arrow.StudsOffset = Vector3.new(0, 9 + math.sin(t * 4) * 1.2, 0)
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		clearTrail()
	end)
	while true do
		local ok, err = pcall(update)
		if not ok then
			warn("[Onboarding]", err)
		end
		task.wait(0.4)
	end
end

return WorldOnboarding
