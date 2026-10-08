--!nonstrict
--[[
	Manual forging minigame (v2): HEAT -> TAP TAP TAP -> QUENCH -> reveal.

	One giant tap target in the middle (taps anywhere on screen also count), a big hit counter,
	a luck meter that fills as you tap faster, and a labeled countdown. The server counts the
	real strikes; the client number is only feedback.
]]
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local Data = require(script.Parent.Data)
local Panels = require(script.Parent.Panels)
local Toast = require(script.Parent.Toast)
local ForgeSignals = require(script.Parent.ForgeSignals)

local ForgeGame = {}
ForgeGame.onReveal = nil :: ((any) -> ())?

local C = Theme.Colors

local ui: any = {}
local active = false
local session: any = nil
local t0 = 0
local phase = "idle"
local hits = 0
local finalLuck = nil
local result = nil
local ring = {}
local ringI = 0
local conns = {}

local function luckFrom(h: number, secs: number): number
	return math.clamp(1 + Data.LuckPerCps * h / math.max(secs, 0.001), 1, 5)
end

local function build()
	local layer = Panels.layer("Panels")
	local root = Theme.make("Frame", {
		Name = "ForgeGame",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(40, 12, 4),
		BackgroundTransparency = 0.45,
		Parent = layer,
	})
	local glow = Theme.make("Frame", {
		Size = UDim2.new(1, 0, 0.7, 0),
		Position = UDim2.new(0, 0, 0.3, 0),
		BackgroundColor3 = C.orange,
		Parent = root,
	})
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.55) })
	g.Parent = glow
	local stage = Theme.make("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(520, 620),
		BackgroundTransparency = 1,
		Parent = root,
	})
	Theme.autoScale(stage, 1, Vector2.new(520, 620))
	ui.root, ui.stage = root, stage
	ui.recipe = Theme.text({ Text = "", Size = UDim2.new(1, 0, 0, 34), TextSize = 28, TextColor3 = C.yellow, Parent = stage })
	ui.title = Theme.text({ Text = "HEAT UP", Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 70), TextSize = 64, TextColor3 = C.orange, Parent = stage })
	ui.timer = Theme.bar({ Position = UDim2.new(0.5, 0, 0, 112), AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(420, 36), FillColor = C.orange, Parent = stage })
	-- Giant tap target.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.new(0.5, 0, 0, 340)
	hit.Size = UDim2.fromOffset(280, 280)
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundColor3 = C.grey
	hit.BorderSizePixel = 0
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0.5, 0)
	hc.Parent = hit
	local hs = Instance.new("UIStroke")
	hs.Color = C.ink
	hs.Thickness = 6
	hs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hs.Parent = hit
	local hg = Instance.new("UIGradient")
	hg.Rotation = 90
	hg.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	hg.Parent = hit
	hit.Parent = stage
	ui.hit = hit
	ui.hitScale = Instance.new("UIScale")
	ui.hitScale.Parent = hit
	ui.hitIcon = Theme.text({ Text = "🔨", Size = UDim2.new(1, 0, 0.55, 0), Position = UDim2.fromScale(0, 0.08), TextSize = 110, TextStroke = false, Parent = hit })
	ui.hitText = Theme.text({ Text = "WAIT", Size = UDim2.new(1, 0, 0.3, 0), Position = UDim2.fromScale(0, 0.62), TextSize = 54, Parent = hit })
	ui.hits = Theme.text({ Text = "0", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.5, -150, 0, 340), Size = UDim2.fromOffset(110, 80), TextSize = 72, TextColor3 = C.yellow, Parent = stage })
	Theme.text({ Text = "HITS", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, -150, 0, 378), Size = UDim2.fromOffset(110, 28), TextSize = 24, Parent = stage })
	-- Luck meter.
	ui.luckBar = Theme.bar({ Position = UDim2.new(0.5, 0, 0, 500), AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(420, 44), FillColor = C.green, Parent = stage })
	ui.luck = Theme.text({ Text = "LUCK 1.0x", Position = UDim2.new(0.5, 0, 0, 548), AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(420, 40), TextSize = 34, TextColor3 = C.green, Parent = stage })
	Theme.text({ Text = "Tap fast for better weapons!", Position = UDim2.new(0.5, 0, 0, 586), AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(460, 30), TextSize = 22, TextColor3 = C.dim, Parent = stage })
	ui.sparks = {}
	for i = 1, 10 do
		ui.sparks[i] = Theme.text({ Text = "✦", Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(0.5, 0.5), TextSize = 40, TextColor3 = C.yellow, TextTransparency = 1, TextStroke = false, Parent = stage })
	end
	Panels.register("ForgeGame", root, nil, { locked = true, noBackdrop = true })
end

local sparkI = 0
local function spark()
	sparkI = sparkI % #ui.sparks + 1
	local s = ui.sparks[sparkI]
	s.Position = UDim2.new(0.5, math.random(-90, 90), 0, 340 + math.random(-60, 20))
	s.TextTransparency = 0
	s.Rotation = math.random(-40, 40)
	Theme.tween(s, 0.45, { Position = s.Position + UDim2.fromOffset(math.random(-80, 80), -math.random(80, 180)), TextTransparency = 1 })
end

local function hit()
	if phase ~= "strike" or not session then return end
	local now = os.clock()
	local idx = ringI % 20 + 1
	if now - ring[idx] < 1 then return end -- client cap 20/s, same as the server guard
	ring[idx] = now
	ringI = idx
	hits += 1
	Net.strike(session.sessionId)
	ForgeSignals.Hit:Fire()
	ui.hits.Text = tostring(hits)
	ui.hitScale.Scale = 0.86
	Theme.tween(ui.hitScale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
	if not (State.profile and State.profile.settings and State.profile.settings.vfx == false) then
		spark()
	end
end

local function setHitColor(color: Color3)
	ui.hit.BackgroundColor3 = color
end

local function setPhase(p: string)
	phase = p
	ForgeSignals.Phase:Fire(p)
	if p == "heat" then
		ui.title.Text = "HEAT UP!"
		ui.title.TextColor3 = C.orange
		ui.hitText.Text = "WAIT..."
		setHitColor(C.grey)
	elseif p == "strike" then
		ui.title.Text = "TAP TAP TAP!"
		ui.title.TextColor3 = C.yellow
		ui.hitText.Text = "TAP!"
		ui.timer.Fill.BackgroundColor3 = C.yellow
		setHitColor(C.orange)
		Theme.pop(ui.title, 0.6)
	elseif p == "quench" then
		ui.title.Text = "COOLING..."
		ui.title.TextColor3 = C.blue
		ui.hitText.Text = "💦"
		ui.timer.Fill.BackgroundColor3 = C.blue
		setHitColor(C.blue)
		if not finalLuck then finalLuck = luckFrom(hits, session.windowSec) end
	elseif p == "waiting" then
		ui.title.Text = "HERE IT COMES..."
	end
end

local function disconnectAll()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
end

local function finish()
	disconnectAll()
	active = false
	phase = "idle"
	session = nil
end

local function step()
	local s = session
	if not s then return end
	local t = os.clock() - t0
	local heatEnd = s.heatSec
	local strikeEnd = heatEnd + s.windowSec
	local quenchEnd = strikeEnd + s.revealSec
	local want = if t < heatEnd then "heat" elseif t < strikeEnd then "strike" elseif t < quenchEnd then "quench" else "waiting"
	if want ~= phase then
		setPhase(want)
	end
	if phase == "heat" then
		Theme.setBar(ui.timer, t / heatEnd, string.format("Heating %.1fs", math.max(0, heatEnd - t)))
	elseif phase == "strike" then
		local el = t - heatEnd
		Theme.setBar(ui.timer, 1 - el / s.windowSec, string.format("%.1fs left", math.max(0, s.windowSec - el)))
		local luck = luckFrom(hits, math.clamp(el, 1, s.windowSec))
		ui.luck.Text = string.format("LUCK %.1fx", luck)
		Theme.setBar(ui.luckBar, (luck - 1) / 4)
	elseif phase == "quench" then
		Theme.setBar(ui.timer, 1 - (t - strikeEnd) / s.revealSec, "Cooling")
		local luck = finalLuck or 1
		ui.luck.Text = string.format("LUCK %.1fx", luck)
		Theme.setBar(ui.luckBar, (luck - 1) / 4)
	elseif phase == "waiting" then
		if result then
			local r = result
			result = nil
			finish()
			Panels.close(true)
			if ForgeGame.onReveal then ForgeGame.onReveal(r) end
			return
		elseif t > quenchEnd + 15 then
			finish()
			Panels.close(true)
			Toast.show("The forge didn't answer. Check your backpack!", "bad")
			return
		end
	end
end

function ForgeGame.isActive(): boolean
	return active
end

function ForgeGame.station(): number?
	return session and session.station
end

-- info = { sessionId, station, heatSec, windowSec, revealSec, recipe = "Iron Sword" }
function ForgeGame.start(info: any)
	if active then return end
	active = true
	session = info
	hits = 0
	finalLuck = nil
	result = nil
	for i = 1, 20 do
		ring[i] = -10
	end
	ringI = 0
	ui.hits.Text = "0"
	ui.luck.Text = "LUCK 1.0x"
	ui.recipe.Text = info.recipe or ""
	Theme.setBar(ui.luckBar, 0)
	ui.timer.Fill.BackgroundColor3 = C.orange
	Theme.setBar(ui.timer, 0)
	phase = "idle"
	t0 = os.clock()
	Panels.open("ForgeGame")
	setPhase("heat")
	table.insert(conns, RunService.Heartbeat:Connect(step))
	table.insert(conns, ui.hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			hit()
		end
	end))
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		local ut = input.UserInputType
		if (ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch) and not processed then
			hit()
		elseif input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.ButtonR2 then
			hit()
		end
	end))
end

-- Server result arrived (ForgeResult push for the active station).
function ForgeGame.deliver(payload: any)
	result = payload
end

function ForgeGame.cancel()
	if not active then return end
	finish()
	ForgeSignals.Phase:Fire("cancelled")
	Panels.close(true)
end

function ForgeGame.init()
	build()
end

return ForgeGame
