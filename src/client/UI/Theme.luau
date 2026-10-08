--!nonstrict
--[[
	Theme v2 — the loud, chunky, mobile-first look (docs/21 §2, docs/22 "UI kit").

	Everything is designed in "design pixels" for a ~520x620 safe area and scaled per device by
	Theme.autoScale, so a button that is 72 design px tall stays a comfortable touch target on a
	phone and does not look tiny on a monitor.

	Building blocks: make (instance builder), text (stroked label), button (gradient, outline,
	drop shadow, squish on press), card, bar, pill, chip, pulse/pop/shake helpers.
]]
local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.Font2 = Enum.Font.FredokaOne

local rgb = Color3.fromRGB
Theme.Colors = {
	-- Panels
	panel = rgb(58, 76, 214),
	panelDark = rgb(36, 44, 150),
	panelEdge = rgb(18, 20, 70),
	card = rgb(255, 255, 255),
	cardDark = rgb(232, 236, 255),
	ink = rgb(22, 18, 48), -- outlines and text stroke
	text = rgb(255, 255, 255),
	dim = rgb(196, 204, 255),
	-- Buttons
	green = rgb(76, 222, 92),
	yellow = rgb(255, 210, 46),
	orange = rgb(255, 140, 30),
	red = rgb(255, 70, 90),
	blue = rgb(70, 170, 255),
	purple = rgb(176, 96, 255),
	pink = rgb(255, 100, 190),
	teal = rgb(40, 220, 200),
	grey = rgb(150, 156, 176),
	-- Meaning
	cash = rgb(90, 235, 100),
	coin = rgb(255, 214, 46),
	good = rgb(76, 222, 92),
	bad = rgb(255, 70, 90),
	-- Legacy names some older helpers still read
	bg = rgb(36, 44, 150),
	panel2 = rgb(80, 96, 230),
	brass = rgb(255, 210, 46),
	steel = rgb(150, 156, 176),
}

Theme.RarityNames = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
Theme.RarityColors = {
	rgb(200, 204, 214),
	rgb(80, 230, 100),
	rgb(60, 160, 255),
	rgb(190, 90, 255),
	rgb(255, 190, 30),
	rgb(255, 60, 120),
}

function Theme.rarityColor(r: number): Color3
	return Theme.RarityColors[math.clamp(math.floor(r or 1), 1, 6)]
end

local function shade(c: Color3, f: number): Color3
	if f >= 0 then return c:Lerp(Color3.new(1, 1, 1), f) end
	return c:Lerp(Color3.new(0, 0, 0), -f)
end
Theme.shade = shade

function Theme.viewport(): Vector2
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

-- Device scale for design pixels: phones ~0.6-0.75, tablets ~1, monitors up to 1.3.
function Theme.scale(): number
	local v = Theme.viewport()
	return math.clamp(math.min(v.X / 560, v.Y / 640), 0.55, 1.3)
end

function Theme.compact(): boolean
	local size = Theme.viewport()
	return size.X < 700 or size.Y < 500
end

-- Text size helper kept for older callers (design pixels are scaled by UIScale instead).
function Theme.ts(n: number): number
	return n
end

local scaled: { UIScale } = {}
local function scaleFor(sc: UIScale): number
	local s = Theme.scale() * (sc:GetAttribute("Factor") or 1)
	local fitW, fitH = sc:GetAttribute("FitW"), sc:GetAttribute("FitH")
	if fitW and fitH then
		-- Never let a big centered element run off a short or narrow screen (top bar ~60px).
		local v = Theme.viewport()
		s = math.min(s, (v.X - 20) / fitW, (v.Y - 70) / fitH)
	end
	return s
end
local function refreshScales()
	for i = #scaled, 1, -1 do
		local sc = scaled[i]
		if sc.Parent then
			sc.Scale = scaleFor(sc)
		else
			table.remove(scaled, i)
		end
	end
end
local hooked = false
local function hookViewport()
	if hooked then return end
	hooked = true
	local function hookCam()
		local cam = workspace.CurrentCamera
		if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScales) end
	end
	hookCam()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hookCam()
		refreshScales()
	end)
end

-- Adds a UIScale that tracks the device scale. `factor` tweaks it per element; `fit` (design
-- size) additionally shrinks it so the whole element always fits on screen.
function Theme.autoScale(inst: Instance, factor: number?, fit: Vector2?): UIScale
	hookViewport()
	local sc = Instance.new("UIScale")
	sc.Name = "AutoScale"
	sc:SetAttribute("Factor", factor or 1)
	if fit then
		sc:SetAttribute("FitW", fit.X)
		sc:SetAttribute("FitH", fit.Y)
	end
	sc.Scale = scaleFor(sc)
	sc.Parent = inst
	table.insert(scaled, sc)
	return sc
end

function Theme.onScaleChanged(fn: () -> ())
	hookViewport()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(fn) end
end

function Theme.tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

local function addStroke(inst: Instance, stroke: any)
	local s = Instance.new("UIStroke")
	if typeof(stroke) == "Color3" then
		s.Color = stroke
		s.Thickness = 3
	else
		s.Color = stroke.Color or Theme.Colors.ink
		s.Thickness = stroke.Thickness or 3
		s.Transparency = stroke.Transparency or 0
	end
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = inst
	return s
end

-- Text outline (contextual stroke) so white text reads on any color.
local function addTextStroke(inst: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Name = "TextStroke"
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Color = color or Theme.Colors.ink
	s.Thickness = thickness or 2.5
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = inst
	return s
end
Theme.textStroke = addTextStroke

--[[
	make(className, props, children). Special props: Parent (applied last), Corner (number),
	Stroke (Color3 or {Color, Thickness, Transparency}), Padding (number), AspectRatio (number),
	TextStroke (true or Color3), Gradient ({Color3 top, Color3 bottom}).
]]
function Theme.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent, corner, stroke, padding, aspect, textStroke, gradient
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
		if TEXT_CLASSES[className] then
			inst.BackgroundTransparency = 1
			inst.Font = Theme.Font
			inst.TextColor3 = Theme.Colors.text
			inst.TextSize = 22
			inst.TextWrapped = true
		elseif className == "Frame" or className == "ScrollingFrame" then
			inst.BackgroundColor3 = Theme.Colors.panel
		end
	end
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			elseif k == "Corner" then
				corner = v
			elseif k == "Stroke" then
				stroke = v
			elseif k == "Padding" then
				padding = v
			elseif k == "AspectRatio" then
				aspect = v
			elseif k == "TextStroke" then
				textStroke = v
			elseif k == "Gradient" then
				gradient = v
			else
				inst[k] = v
			end
		end
	end
	if corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, corner)
		c.Parent = inst
	end
	if stroke then
		addStroke(inst, stroke)
	end
	if textStroke then
		addTextStroke(inst, if typeof(textStroke) == "Color3" then textStroke else nil)
	end
	if gradient then
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(gradient[1], gradient[2])
		g.Parent = inst
	end
	if padding then
		local p = Instance.new("UIPadding")
		local u = UDim.new(0, padding)
		p.PaddingLeft, p.PaddingRight, p.PaddingTop, p.PaddingBottom = u, u, u, u
		p.Parent = inst
	end
	if aspect then
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = aspect
		a.Parent = inst
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Theme.list(parent: Instance, padding: number?, dir: Enum.FillDirection?, hAlign: Enum.HorizontalAlignment?)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, padding or 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = dir or Enum.FillDirection.Vertical
	if hAlign then l.HorizontalAlignment = hAlign end
	l.Parent = parent
	return l
end

function Theme.grid(parent: Instance, cell: Vector2, padding: number?)
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	g.CellPadding = UDim2.fromOffset(padding or 8, padding or 8)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.HorizontalAlignment = Enum.HorizontalAlignment.Center
	g.Parent = parent
	return g
end

function Theme.scroll(props: { [string]: any }): any
	local p = table.clone(props)
	p.BackgroundTransparency = p.BackgroundTransparency or 1
	p.ScrollBarThickness = p.ScrollBarThickness or 8
	p.ScrollBarImageColor3 = Theme.Colors.yellow
	p.CanvasSize = UDim2.new()
	p.AutomaticCanvasSize = p.AutomaticCanvasSize or Enum.AutomaticSize.Y
	p.ScrollingDirection = p.ScrollingDirection or Enum.ScrollingDirection.Y
	return Theme.make("ScrollingFrame", p)
end

-- Big stroked label (white text with a dark outline by default).
function Theme.text(props: { [string]: any }): TextLabel
	local p = table.clone(props)
	if p.TextStroke == nil then p.TextStroke = true end
	return Theme.make("TextLabel", p)
end
Theme.label = Theme.text

--[[
	Chunky button: gradient fill, thick dark outline, bottom lip, squish on press, bounce on
	release. props: Text, Color, OnClick, TextSize, plus any TextButton props (Size, Position...).
	The visible text lives in a child "Label" (UIGradient would tint the button's own text), so
	change it with Theme.setText(button, text).
]]
function Theme.button(props: { [string]: any }): TextButton
	local p = table.clone(props)
	local base: Color3 = p.Color or Theme.Colors.green
	local onClick = p.OnClick
	local text = p.Text or ""
	local textSize = p.TextSize or 26
	local corner = p.Corner or 14
	local textColor = p.TextColor3 or Theme.Colors.text
	p.OnClick, p.Color, p.Text, p.TextSize, p.Corner, p.TextColor3 = nil, nil, nil, nil, nil, nil
	p.Icon = nil
	p.BackgroundTransparency = 1
	p.AutoButtonColor = false
	p.Size = p.Size or UDim2.fromOffset(180, 64)
	local b = Theme.make("TextButton", p)
	b.Text = ""
	b:SetAttribute("On", true)
	b:SetAttribute("Base", base)
	local bg = Theme.make("Frame", {
		Name = "Bg",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Corner = corner,
		Stroke = { Color = Theme.Colors.ink, Thickness = 3 },
		ZIndex = b.ZIndex,
		Parent = b,
	})
	local grad = Instance.new("UIGradient")
	grad.Name = "Fill"
	grad.Rotation = 90
	grad.Color = ColorSequence.new(shade(base, 0.28), shade(base, -0.1))
	grad.Parent = bg
	Theme.make("Frame", {
		Name = "Lip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 7),
		BackgroundColor3 = shade(base, -0.38),
		Corner = corner,
		ZIndex = b.ZIndex,
		Parent = b,
	})
	-- Glossy highlight across the top third.
	Theme.make("Frame", {
		Name = "Gloss",
		Position = UDim2.new(0, 6, 0, 4),
		Size = UDim2.new(1, -12, 0.32, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.72,
		Corner = math.max(4, corner - 6),
		ZIndex = b.ZIndex,
		Parent = b,
	})
	Theme.make("TextLabel", {
		Name = "Label",
		Text = text,
		TextSize = textSize,
		TextColor3 = textColor,
		TextStroke = true,
		Size = UDim2.new(1, -10, 1, -6),
		Position = UDim2.new(0, 5, 0, 0),
		ZIndex = b.ZIndex + 1,
		Parent = b,
	})
	local scale = Instance.new("UIScale")
	scale.Name = "PressScale"
	scale.Parent = b
	b.MouseEnter:Connect(function()
		if b:GetAttribute("On") then
			Theme.tween(scale, 0.12, { Scale = 1.05 })
		end
	end)
	b.MouseLeave:Connect(function()
		Theme.tween(scale, 0.12, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		if b:GetAttribute("On") then Theme.tween(scale, 0.06, { Scale = 0.9 }) end
	end)
	b.MouseButton1Up:Connect(function()
		Theme.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	if onClick then
		b.Activated:Connect(function()
			if b:GetAttribute("On") then
				onClick()
			else
				-- A disabled button still answers with a wiggle so kids know it was heard.
				Theme.shake(b)
			end
		end)
	end
	return b
end

function Theme.setText(b: GuiObject, text: string)
	local label = b:FindFirstChild("Label")
	if label then
		label.Text = text
	elseif b:IsA("TextButton") or b:IsA("TextLabel") then
		(b :: any).Text = text
	end
end

local function paint(b: GuiObject, c: Color3)
	local bg = b:FindFirstChild("Bg")
	local grad = bg and bg:FindFirstChild("Fill")
	if grad then grad.Color = ColorSequence.new(shade(c, 0.28), shade(c, -0.1)) end
	local lip = b:FindFirstChild("Lip")
	if lip then lip.BackgroundColor3 = shade(c, -0.38) end
end

function Theme.setColor(b: GuiObject, c: Color3)
	b:SetAttribute("Base", c)
	if b:GetAttribute("On") == false then return end
	paint(b, c)
end

function Theme.setEnabled(b: GuiObject, on: boolean)
	b:SetAttribute("On", on)
	paint(b, if on then b:GetAttribute("Base") else Theme.Colors.grey)
	local label = b:FindFirstChild("Label")
	if label then
		label.TextTransparency = if on then 0 else 0.2
	end
end

-- Rounded card. Light cards by default.
function Theme.card(props: { [string]: any }): Frame
	local p = table.clone(props)
	p.BackgroundColor3 = p.BackgroundColor3 or Theme.Colors.panelDark
	p.Corner = p.Corner or 14
	p.Stroke = p.Stroke or { Color = Theme.Colors.ink, Thickness = 3 }
	return Theme.make("Frame", p)
end

-- Progress bar: returns root; root.Fill is the colored child, root.Label is centered text.
function Theme.bar(props: { [string]: any }): any
	local p = table.clone(props)
	local color = p.FillColor or Theme.Colors.yellow
	p.FillColor = nil
	p.BackgroundColor3 = Theme.Colors.panelEdge
	p.Corner = p.Corner or 10
	p.Stroke = p.Stroke or { Color = Theme.Colors.ink, Thickness = 3 }
	local root = Theme.make("Frame", p)
	Theme.make("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		Size = UDim2.new(0, 0, 1, 0),
		Corner = p.Corner,
		Gradient = { shade(color, 0.3), shade(color, -0.1) },
		Parent = root,
	})
	Theme.text({
		Name = "Label",
		Text = "",
		Size = UDim2.new(1, 0, 1, 0),
		TextSize = 20,
		ZIndex = 3,
		Parent = root,
	})
	return root
end

function Theme.setBar(root: any, f: number, text: string?)
	root.Fill.Size = UDim2.new(math.clamp(f, 0, 1), 0, 1, 0)
	root.Fill.Visible = f > 0.001
	if text then root.Label.Text = text end
end

-- Small rounded tag (e.g. rarity, counts).
function Theme.chip(text: string, color: Color3, props: { [string]: any }?): TextLabel
	local p = props and table.clone(props) or {}
	p.Text = text
	p.BackgroundColor3 = color
	p.BackgroundTransparency = 0
	p.Corner = p.Corner or 10
	p.Stroke = p.Stroke or { Color = Theme.Colors.ink, Thickness = 2 }
	p.TextSize = p.TextSize or 18
	p.Size = p.Size or UDim2.fromOffset(110, 30)
	p.TextStroke = true
	return Theme.make("TextLabel", p)
end

-- Attention pulse (gentle, slow; never a rapid strobe). Returns a stop function.
function Theme.pulse(inst: GuiObject, amount: number?): () -> ()
	local sc = inst:FindFirstChild("PulseScale") or Instance.new("UIScale")
	sc.Name = "PulseScale"
	sc.Parent = inst
	local running = true
	task.spawn(function()
		while running and inst.Parent do
			Theme.tween(sc, 0.55, { Scale = 1 + (amount or 0.06) }, Enum.EasingStyle.Sine)
			task.wait(0.6)
			Theme.tween(sc, 0.55, { Scale = 1 }, Enum.EasingStyle.Sine)
			task.wait(0.6)
		end
		sc.Scale = 1
	end)
	return function()
		running = false
	end
end

-- Pop-in: grows from small with a springy overshoot.
function Theme.pop(inst: GuiObject, from: number?)
	local sc = inst:FindFirstChild("PopScale") or Instance.new("UIScale")
	sc.Name = "PopScale"
	sc.Parent = inst
	sc.Scale = from or 0.4
	Theme.tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

function Theme.shake(inst: GuiObject)
	local base = inst.Position
	task.spawn(function()
		for _, dx in { -6, 6, -4, 4, 0 } do
			inst.Position = base + UDim2.fromOffset(dx, 0)
			task.wait(0.035)
		end
		inst.Position = base
	end)
end

-- "$1.23K" — every amount of cash in the game is shown with a dollar sign (docs/21 §2).
local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
function Theme.abbr(n: number?): string
	n = n or 0
	if n ~= n then return "0" end
	local neg = n < 0
	n = math.abs(n)
	if n < 1000 then
		return (if neg then "-" else "") .. tostring(math.floor(n + 0.5))
	end
	local i = math.min(math.floor(math.log10(n) / 3), #SUFFIX - 1)
	local v = n / 10 ^ (i * 3)
	if v >= 999.5 and i < #SUFFIX - 1 then
		i += 1
		v = n / 10 ^ (i * 3)
	end
	local s
	if v >= 100 then
		s = string.format("%.0f", v)
	elseif v >= 10 then
		s = string.format("%.1f", v)
	else
		s = string.format("%.2f", v)
	end
	if s:find("%.") then
		s = s:gsub("0+$", ""):gsub("%.$", "")
	end
	return (if neg then "-" else "") .. s .. SUFFIX[i + 1]
end

function Theme.money(n: number?): string
	return "$" .. Theme.abbr(n)
end

-- "+$12/sec", or "+$3/min" when the per-second amount would round to nothing.
function Theme.moneyRate(perSec: number?): string
	perSec = perSec or 0
	if perSec >= 1 or perSec <= 0 then
		return "+$" .. Theme.abbr(perSec) .. "/sec"
	end
	local perMin = perSec * 60
	if perMin >= 10 then
		return "+$" .. Theme.abbr(perMin) .. "/min"
	end
	return string.format("+$%.1f/min", perMin)
end

return Theme
