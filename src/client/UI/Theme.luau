--!nonstrict
-- Colors, fonts, tween helpers and a tiny instance builder shared by every UI controller.
local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.Font2 = Enum.Font.GothamBold

Theme.Colors = {
	bg = Color3.fromRGB(30, 24, 22),
	panel = Color3.fromRGB(44, 35, 31),
	panel2 = Color3.fromRGB(60, 49, 42),
	brass = Color3.fromRGB(201, 152, 58),
	orange = Color3.fromRGB(240, 130, 36),
	text = Color3.fromRGB(246, 237, 222),
	dim = Color3.fromRGB(176, 164, 150),
	good = Color3.fromRGB(80, 180, 85),
	bad = Color3.fromRGB(215, 70, 62),
	coin = Color3.fromRGB(255, 214, 70),
	steel = Color3.fromRGB(110, 120, 135),
}

Theme.RarityNames = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
Theme.RarityColors = {
	Color3.fromRGB(200, 200, 200),
	Color3.fromRGB(90, 200, 90),
	Color3.fromRGB(70, 140, 255),
	Color3.fromRGB(170, 80, 255),
	Color3.fromRGB(255, 170, 40),
	Color3.fromRGB(255, 60, 90),
}

function Theme.rarityColor(r: number): Color3
	return Theme.RarityColors[math.clamp(math.floor(r or 1), 1, 6)]
end

function Theme.viewport(): Vector2
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

function Theme.compact(): boolean
	return Theme.viewport().X < 700
end

-- Text size helper: shrinks slightly on phones.
function Theme.ts(n: number): number
	return Theme.compact() and math.max(11, math.floor(n * 0.86)) or n
end

function Theme.tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

-- make(className, props, children). Special props: Parent (applied last), Corner (number),
-- Stroke (Color3 or {Color, Thickness, Transparency}), Padding (number), AspectRatio (number).
function Theme.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent, corner, stroke, padding, aspect
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
		if TEXT_CLASSES[className] then
			inst.BackgroundTransparency = 1
			inst.Font = Theme.Font
			inst.TextColor3 = Theme.Colors.text
			inst.TextSize = Theme.ts(18)
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
		local s = Instance.new("UIStroke")
		if typeof(stroke) == "Color3" then
			s.Color = stroke
			s.Thickness = 2
		else
			s.Color = stroke.Color or Theme.Colors.brass
			s.Thickness = stroke.Thickness or 2
			s.Transparency = stroke.Transparency or 0
		end
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = inst
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
	l.Padding = UDim.new(0, padding or 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = dir or Enum.FillDirection.Vertical
	if hAlign then l.HorizontalAlignment = hAlign end
	l.Parent = parent
	return l
end

function Theme.scroll(props: { [string]: any }): any
	local p = table.clone(props)
	p.BackgroundTransparency = p.BackgroundTransparency or 1
	p.ScrollBarThickness = p.ScrollBarThickness or 6
	p.ScrollBarImageColor3 = Theme.Colors.brass
	p.CanvasSize = UDim2.new()
	p.AutomaticCanvasSize = Enum.AutomaticSize.Y
	p.ScrollingDirection = Enum.ScrollingDirection.Y
	return Theme.make("ScrollingFrame", p)
end

local function shade(c: Color3, f: number): Color3
	if f >= 0 then return c:Lerp(Color3.new(1, 1, 1), f) end
	return c:Lerp(Color3.new(0, 0, 0), -f)
end
Theme.shade = shade

-- Chunky button with hover/press tweens. props: Text, Color, OnClick, plus any TextButton props.
function Theme.button(props: { [string]: any }): TextButton
	local p = table.clone(props)
	local base: Color3 = p.Color or Theme.Colors.orange
	local onClick = p.OnClick
	p.OnClick = nil
	p.Color = nil
	p.BackgroundColor3 = base
	p.AutoButtonColor = false
	p.Text = p.Text or ""
	p.TextSize = p.TextSize or Theme.ts(20)
	p.Font = p.Font or Theme.Font
	p.Corner = p.Corner or 10
	p.Stroke = p.Stroke or { Color = shade(base, -0.45), Thickness = 2 }
	p.Size = p.Size or UDim2.new(0, 140, 0, 48)
	local b = Theme.make("TextButton", p)
	b:SetAttribute("Base", base)
	b:SetAttribute("On", true)
	local scale = Instance.new("UIScale")
	scale.Name = "PressScale"
	scale.Parent = b
	b.MouseEnter:Connect(function()
		if b:GetAttribute("On") then
			Theme.tween(b, 0.12, { BackgroundColor3 = shade(b:GetAttribute("Base"), 0.15) })
		end
	end)
	b.MouseLeave:Connect(function()
		Theme.tween(b, 0.12, { BackgroundColor3 = b:GetAttribute("On") and b:GetAttribute("Base") or Theme.Colors.steel })
		Theme.tween(scale, 0.1, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		if b:GetAttribute("On") then Theme.tween(scale, 0.08, { Scale = 0.93 }) end
	end)
	b.MouseButton1Up:Connect(function()
		Theme.tween(scale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	if onClick then
		b.Activated:Connect(function()
			if b:GetAttribute("On") then onClick() end
		end)
	end
	return b
end

function Theme.setEnabled(b: TextButton, on: boolean)
	b:SetAttribute("On", on)
	b.BackgroundColor3 = on and b:GetAttribute("Base") or Theme.Colors.steel
	b.TextTransparency = on and 0 or 0.45
end

function Theme.setColor(b: TextButton, c: Color3)
	b:SetAttribute("Base", c)
	b.BackgroundColor3 = b:GetAttribute("On") and c or Theme.Colors.steel
end

-- Progress bar: returns root frame; root.Fill is the colored child, root.Label is centered text.
function Theme.bar(props: { [string]: any }): any
	local p = table.clone(props)
	local color = p.FillColor or Theme.Colors.orange
	p.FillColor = nil
	p.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
	p.Corner = p.Corner or 8
	p.Stroke = p.Stroke or { Color = Theme.Colors.brass, Thickness = 1.5 }
	local root = Theme.make("Frame", p)
	Theme.make("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		Size = UDim2.new(0, 0, 1, 0),
		Corner = p.Corner,
		Parent = root,
	})
	Theme.make("TextLabel", {
		Name = "Label",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		TextSize = Theme.ts(14),
		Font = Theme.Font2,
		ZIndex = 3,
		Parent = root,
	})
	return root
end

function Theme.setBar(root: any, f: number, text: string?)
	root.Fill.Size = UDim2.new(math.clamp(f, 0, 1), 0, 1, 0)
	if text then root.Label.Text = text end
end

-- Quick label constructor (GothamBold by default).
function Theme.label(props: { [string]: any }): TextLabel
	local p = table.clone(props)
	p.Font = p.Font or Theme.Font2
	return Theme.make("TextLabel", p)
end

return Theme
