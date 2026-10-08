--!nonstrict
-- Full-screen manual forging minigame: HEAT -> STRIKE -> QUENCH, then hands the server result to onReveal.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Net = require(script.Parent.Parent.Net)
local Theme = require(script.Parent.Theme)
local Data = require(script.Parent.Data)
local Panels = require(script.Parent.Panels)
local Toast = require(script.Parent.Toast)
local ForgeSignals = require(script.Parent.ForgeSignals)

local ForgeGame = {}
ForgeGame.onReveal = nil :: ((any) -> ())?

local C = Theme.Colors
local TICKS = { { 1.5, "1.5x\nFree auto" }, { 2.5, "2.5x\nTypical" }, { 4, "4x\nPremium" }, { 5, "5x\nMax" } }

local ui = {}
local active = false
local session = nil
local t0 = 0
local phase = "idle"
local hits = 0
local finalLuck = nil
local result = nil
local ring = {}
local ringI = 0
local sparkI = 0
local conns = {}
local lastLuckText = ""
local lastTimerText = ""

local function luckFrom(h: number, secs: number): number
	return math.clamp(1 + Data.LuckPerCps * h / math.max(secs, 0.001), 1, 5)
end

local function build()
	local layer = Panels.layer("Panels")
	local root = Theme.make("Frame", {
		Name = "ForgeGame",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(22, 14, 10),
		BackgroundTransparency = 0.6,
		ClipsDescendants = true,
		Parent = layer,
	})
	ui.root = root
	local glow = Theme.make("Frame", {
		Size = UDim2.new(1, 0, 0.6, 0),
		Position = UDim2.new(0, 0, 0.4, 0),
		BackgroundColor3 = C.orange,
		BorderSizePixel = 0,
		Parent = root,
	})
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.7) })
	g.Parent = glow

	local stage = Theme.make("Frame", { Name = "Stage", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Parent = root })
	ui.stage = stage
	ui.title = Theme.make("TextLabel", {
		Text = "HEAT UP",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.04, 0),
		Size = UDim2.new(0.9, 0, 0, 56),
		TextSize = Theme.ts(46),
		TextColor3 = C.orange,
		Parent = stage,
	})
	ui.timer = Theme.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.04, 56),
		Size = UDim2.new(0.9, 0, 0, 28),
		TextSize = Theme.ts(22),
		Parent = stage,
	})
	ui.heat = Theme.bar({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.04, 96),
		Size = UDim2.new(0.8, 0, 0, 26),
		FillColor = C.orange,
		Parent = stage,
	})
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(640, 26)
	lim.Parent = ui.heat
	ui.hits = Theme.make("TextLabel", {
		Text = "0",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.36, 0),
		Size = UDim2.new(0.6, 0, 0, 90),
		TextSize = Theme.ts(78),
		TextColor3 = C.coin,
		Parent = stage,
	})
	ui.hitsSub = Theme.label({
		Text = "hits",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, 44),
		Size = UDim2.new(0.6, 0, 0, 22),
		TextSize = Theme.ts(16),
		TextColor3 = C.dim,
		Parent = stage,
	})

	-- luck meter
	local meter = Theme.make("Frame", {
		Name = "Meter",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.58, 0),
		Size = UDim2.new(0.8, 0, 0, 30),
		BackgroundTransparency = 1,
		Parent = stage,
	})
	local mlim = Instance.new("UISizeConstraint")
	mlim.MaxSize = Vector2.new(640, 30)
	mlim.Parent = meter
	ui.luckBar = Theme.bar({ Size = UDim2.new(1, 0, 0, 22), FillColor = C.good, Parent = meter })
	ui.luckBar.Label.Text = ""
	for _, t in TICKS do
		local f = (t[1] - 1) / 4
		Theme.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(f, 0, 0, -3),
			Size = UDim2.new(0, 3, 0, 28),
			BackgroundColor3 = C.text,
			ZIndex = 5,
			Parent = meter,
		})
		Theme.make("TextLabel", {
			Text = t[2],
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(f, 0, 0, 28),
			Size = UDim2.new(0, 70, 0, 28),
			TextSize = 11,
			Font = Theme.Font2,
			TextColor3 = C.dim,
			Parent = meter,
		})
	end
	ui.luck = Theme.make("TextLabel", {
		Text = "Luck 1.00x",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.58, -22),
		Size = UDim2.new(0.8, 0, 0, 34),
		TextSize = Theme.ts(26),
		TextColor3 = C.good,
		Parent = stage,
	})
	ui.note = Theme.label({
		Text = "Preview only - the server decides your final luck.",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.58, 66),
		Size = UDim2.new(0.9, 0, 0, 20),
		TextSize = 12,
		TextColor3 = C.dim,
		Parent = stage,
	})

	-- HIT button
	local size = Theme.compact() and 150 or 180
	ui.hitScale = Instance.new("UIScale")
	ui.hit = Theme.make("TextButton", {
		Name = "Hit",
		Text = "WAIT",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0, size, 0, size),
		BackgroundColor3 = C.steel,
		TextSize = Theme.ts(40),
		AutoButtonColor = false,
		Corner = size,
		Stroke = { Color = C.brass, Thickness = 6 },
		Parent = stage,
	})
	ui.hitScale.Parent = ui.hit

	-- spark pool
	ui.sparks = {}
	for i = 1, 10 do
		ui.sparks[i] = Theme.make("TextLabel", {
			Text = "✦",
			Size = UDim2.new(0, 30, 0, 30),
			AnchorPoint = Vector2.new(0.5, 0.5),
			TextColor3 = C.coin,
			TextSize = 28,
			TextTransparency = 1,
			ZIndex = 8,
			Parent = stage,
		})
	end

	Panels.register("ForgeGame", root, nil, { locked = true, fullscreen = true, noBackdrop = true })
end

local function spark()
	sparkI = sparkI % #ui.sparks + 1
	local s = ui.sparks[sparkI]
	local bx = ui.hit.AbsolutePosition.X + ui.hit.AbsoluteSize.X * (0.2 + math.random() * 0.6)
	local by = ui.hit.AbsolutePosition.Y + ui.hit.AbsoluteSize.Y * 0.2
	local o = ui.stage.AbsolutePosition
	s.Position = UDim2.new(0, bx - o.X, 0, by - o.Y)
	s.TextTransparency = 0
	s.Rotation = math.random(-40, 40)
	Theme.tween(s, 0.45, {
		Position = UDim2.new(0, bx - o.X + math.random(-60, 60), 0, by - o.Y - math.random(80, 200)),
		TextTransparency = 1,
	})
end

local function hit()
	if phase ~= "strike" or not session then return end
	local now = os.clock()
	local idx = ringI % 20 + 1
	if now - ring[idx] < 1 then return end -- client cap 20/s
	ring[idx] = now
	ringI = idx
	hits += 1
	Net.strike(session.sessionId)
	ForgeSignals.Hit:Fire()
	ui.hits.Text = tostring(hits)
	ui.hitScale.Scale = 0.88
	Theme.tween(ui.hitScale, 0.1, { Scale = 1 }, Enum.EasingStyle.Back)
	ui.stage.Position = UDim2.new(0, math.random(-7, 7), 0, math.random(-7, 7))
	Theme.tween(ui.stage, 0.07, { Position = UDim2.new(0, 0, 0, 0) })
	spark()
end

local function setPhase(p: string)
	phase = p
	ForgeSignals.Phase:Fire(p)
	if p == "heat" then
		ui.title.Text = "HEAT UP"
		ui.title.TextColor3 = C.orange
		ui.hit.Text = "WAIT"
		Theme.tween(ui.hit, 0.1, { BackgroundColor3 = C.steel })
	elseif p == "strike" then
		ui.title.Text = "STRIKE!"
		ui.title.TextColor3 = C.coin
		ui.hit.Text = "HIT!"
		ui.heat.Fill.BackgroundColor3 = C.coin
		Theme.tween(ui.hit, 0.1, { BackgroundColor3 = C.orange })
	elseif p == "quench" then
		ui.title.Text = "QUENCH"
		ui.title.TextColor3 = Color3.fromRGB(110, 190, 255)
		ui.hit.Text = "..."
		ui.heat.Fill.BackgroundColor3 = Color3.fromRGB(110, 190, 255)
		Theme.tween(ui.hit, 0.1, { BackgroundColor3 = C.steel })
		if not finalLuck then finalLuck = luckFrom(hits, session.windowSec) end
	elseif p == "waiting" then
		ui.title.Text = "REVEALING..."
		ui.timer.Text = ""
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
	local now = os.clock()
	local t = now - t0
	local s = session
	if not s then return end
	local heatEnd = s.heatSec
	local strikeEnd = heatEnd + s.windowSec
	local quenchEnd = strikeEnd + s.revealSec
	local want
	if t < heatEnd then
		want = "heat"
	elseif t < strikeEnd then
		want = "strike"
	elseif t < quenchEnd then
		want = "quench"
	else
		want = "waiting"
	end
	if want ~= phase then
		-- allow skipping straight through short phases in order
		if want == "strike" and phase == "heat" then setPhase("strike")
		elseif want == "quench" then setPhase("quench")
		elseif want == "waiting" then setPhase("waiting")
		elseif want == "heat" then setPhase("heat") end
	end

	local timerText
	if phase == "heat" then
		Theme.setBar(ui.heat, t / heatEnd)
		timerText = string.format("%.1fs", math.max(0, heatEnd - t))
	elseif phase == "strike" then
		local el = t - heatEnd
		Theme.setBar(ui.heat, 1 - el / s.windowSec)
		timerText = string.format("%.1fs", math.max(0, s.windowSec - el))
		local luck = luckFrom(hits, math.clamp(el, 1, s.windowSec))
		local txt = string.format("Luck %.2fx", luck)
		if txt ~= lastLuckText then
			lastLuckText = txt
			ui.luck.Text = txt
			Theme.setBar(ui.luckBar, (luck - 1) / 4)
		end
	elseif phase == "quench" then
		Theme.setBar(ui.heat, 1 - (t - strikeEnd) / s.revealSec)
		timerText = ""
		local luck = finalLuck or 1
		local txt = string.format("Luck %.2fx", luck)
		if txt ~= lastLuckText then
			lastLuckText = txt
			ui.luck.Text = txt
			Theme.setBar(ui.luckBar, (luck - 1) / 4)
		end
	elseif phase == "waiting" then
		timerText = ""
		if result then
			local r = result
			result = nil
			finish()
			Panels.close(true)
			if ForgeGame.onReveal then ForgeGame.onReveal(r) end
			return
		elseif t > quenchEnd + 20 then
			finish()
			Panels.close(true)
			Toast.show("The forge did not respond. Check your inventory.", "bad")
			return
		end
	end
	if timerText ~= lastTimerText then
		lastTimerText = timerText
		ui.timer.Text = timerText
	end
end

function ForgeGame.isActive(): boolean
	return active
end

-- info = { sessionId, heatSec, windowSec, revealSec }
function ForgeGame.start(info: any)
	if active then return end
	active = true
	session = info
	hits = 0
	finalLuck = nil
	result = nil
	lastLuckText, lastTimerText = "", ""
	for i = 1, 20 do
		ring[i] = -10
	end
	ringI = 0
	ui.hits.Text = "0"
	ui.luck.Text = "Luck 1.00x"
	Theme.setBar(ui.luckBar, 0)
	ui.heat.Fill.BackgroundColor3 = C.orange
	Theme.setBar(ui.heat, 0)
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
		elseif input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.ButtonR2 then
			hit()
		end
	end))
end

-- Server result arrived (ForgeResult push for the active session).
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
