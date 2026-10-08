--!nonstrict
--[[
	Panels v2 — owns the ForgeFrenzyUI ScreenGui, its layers, and one centered modal at a time.

	Every station panel is a centered, mobile-first sheet: a colored header with a big title and a
	round close button, a scrolling body, and an optional fixed footer for the main action
	(e.g. BEGIN). Sheets are built in design pixels and scaled to the device (Theme.autoScale),
	and their height shrinks to fit short landscape phones.

	Panels.create(name, title, opts) -> (window, body, footer, header)
	  opts: width (480), height (580), color, footer (px), onOpen(arg), onClose(), noScroll
	Panels.open(name, arg?) / Panels.close() / Panels.toggle / Panels.isOpen / Panels.current
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Theme = require(script.Parent.Theme)

local Panels = {}

local gui: ScreenGui? = nil
local layers: { [string]: Frame } = {}
local registry: { [string]: any } = {}
local current: string? = nil
local backdrop: TextButton? = nil
local changed = Instance.new("BindableEvent")
Panels.Changed = changed.Event -- (name: string?, closedName: string?)
local resizers: { () -> () } = {}

local LAYER_Z = { Hud = 1, World = 3, Tickers = 5, Panels = 10, Reveal = 20, Toast = 30 }

function Panels.gui(): ScreenGui
	if gui then return gui end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = pg:FindFirstChild("ForgeFrenzyUI")
	if existing then existing:Destroy() end
	gui = Theme.make("ScreenGui", {
		Name = "ForgeFrenzyUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = pg,
	})
	Theme.onScaleChanged(function()
		for _, fn in resizers do
			fn()
		end
	end)
	return gui
end

-- Full-screen transparent container with a fixed z-order name.
function Panels.layer(name: string): Frame
	if layers[name] then return layers[name] end
	local f = Theme.make("Frame", {
		Name = name .. "Layer",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = LAYER_Z[name] or 2,
		Parent = Panels.gui(),
	})
	layers[name] = f
	f:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		for _, fn in resizers do fn() end
	end)
	return f
end

function Panels.onViewportChanged(fn: () -> ())
	table.insert(resizers, fn)
end

local function ensureBackdrop()
	if backdrop then return end
	backdrop = Theme.make("TextButton", {
		Name = "Backdrop",
		Text = "",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(10, 8, 30),
		BackgroundTransparency = 1,
		Visible = false,
		AutoButtonColor = false,
		ZIndex = 1,
		Parent = Panels.layer("Panels"),
	})
	backdrop.Activated:Connect(function()
		Panels.close()
	end)
end

function Panels.current(): string?
	return current
end

function Panels.isOpen(name: string?): boolean
	if name then return current == name end
	return current ~= nil
end

function Panels.register(name: string, frame: GuiObject, onOpen: ((any) -> ())?, opts: { [string]: any }?)
	ensureBackdrop()
	registry[name] = { frame = frame, onOpen = onOpen, opts = opts or {} }
	frame.Visible = false
	frame.ZIndex = 5
end

function Panels.close(force: boolean?)
	if not current then return end
	local entry = registry[current]
	if entry and entry.opts.locked and not force then return end
	local name = current
	current = nil
	if entry then
		entry.frame.Visible = false
		if entry.opts.onClose then
			task.spawn(entry.opts.onClose)
		end
	end
	if backdrop then
		backdrop.Visible = false
		backdrop.BackgroundTransparency = 1
	end
	changed:Fire(nil, name)
end

function Panels.open(name: string, arg: any?)
	local entry = registry[name]
	if not entry then
		warn("[UI] unknown panel", name)
		return
	end
	if current then
		local cur = registry[current]
		if cur and cur.opts.locked and current ~= name then return end -- minigame in progress
		if current ~= name then Panels.close(true) end
	end
	current = name
	ensureBackdrop()
	backdrop.Visible = not entry.opts.noBackdrop
	backdrop.Active = not entry.opts.locked
	backdrop.BackgroundTransparency = 1
	Theme.tween(backdrop, 0.2, { BackgroundTransparency = entry.opts.dim or 0.5 })
	entry.frame.Visible = true
	local sc = entry.frame:FindFirstChild("OpenScale", true)
	if sc then
		sc.Scale = 0.85
		Theme.tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	if entry.onOpen then
		task.spawn(entry.onOpen, arg)
	end
	changed:Fire(name)
end

function Panels.toggle(name: string, arg: any?)
	if current == name then Panels.close() else Panels.open(name, arg) end
end

-- Standard centered sheet. Returns (window, body, footer?, header).
function Panels.create(name: string, title: string, opts: { [string]: any }?): (Frame, Frame, Frame?, Frame)
	opts = opts or {}
	local C = Theme.Colors
	local color = opts.color or C.panel
	local width = opts.width or 480
	local height = opts.height or 580
	local footerH = opts.footer or 0
	local holder = Theme.make("Frame", {
		Name = name .. "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = 1,
		Parent = Panels.layer("Panels"),
	})
	Theme.autoScale(holder)
	local open = Instance.new("UIScale")
	open.Name = "OpenScale"
	open.Parent = holder
	-- Two nested scales would multiply; OpenScale lives on the inner window instead.
	open.Parent = nil
	local window = Theme.make("Frame", {
		Name = "Window",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = color,
		Corner = 22,
		Stroke = { Color = C.ink, Thickness = 4 },
		Gradient = { Theme.shade(color, 0.12), Theme.shade(color, -0.18) },
		Parent = holder,
	})
	open.Parent = window
	local header = Theme.make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundColor3 = opts.headerColor or Theme.shade(color, -0.25),
		Corner = 22,
		Parent = window,
	})
	-- Square off the header's bottom corners.
	Theme.make("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -22),
		BackgroundColor3 = header.BackgroundColor3,
		Parent = header,
	})
	local titleLabel = Theme.text({
		Name = "Title",
		Text = string.upper(title),
		Size = UDim2.new(1, -150, 0, 46),
		Position = UDim2.new(0.5, 0, 0, 6),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = 38,
		TextWrapped = false,
		TextScaled = true,
		Parent = header,
	})
	local tc = Instance.new("UITextSizeConstraint")
	tc.MaxTextSize = 38
	tc.Parent = titleLabel
	Theme.text({
		Name = "Subtitle",
		Text = opts.subtitle or "",
		Size = UDim2.new(1, -150, 0, 20),
		Position = UDim2.new(0.5, 0, 0, 48),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = 18,
		TextColor3 = C.dim,
		Parent = header,
	})
	local close = Theme.button({
		Name = "Close",
		Text = "X",
		Color = C.red,
		Size = UDim2.fromOffset(54, 54),
		Position = UDim2.new(1, 12, 0, -12),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 30,
		Corner = 27,
		OnClick = function()
			Panels.close()
		end,
		Parent = window,
	})
	close.ZIndex = 8
	local bodyTop = 80
	local body
	if opts.noScroll then
		body = Theme.make("Frame", {
			Name = "Body",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 14, 0, bodyTop),
			Size = UDim2.new(1, -28, 1, -(bodyTop + footerH + 12)),
			Parent = window,
		})
	else
		body = Theme.scroll({
			Name = "Body",
			Position = UDim2.new(0, 10, 0, bodyTop),
			Size = UDim2.new(1, -20, 1, -(bodyTop + footerH + 12)),
			Parent = window,
		})
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingRight = UDim.new(0, 12)
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.Parent = body
		Theme.list(body, 12, nil, Enum.HorizontalAlignment.Center)
	end
	local footer = nil
	if footerH > 0 then
		footer = Theme.make("Frame", {
			Name = "Footer",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 14, 1, -10),
			Size = UDim2.new(1, -28, 0, footerH),
			Parent = window,
		})
	end
	-- Shrink the sheet to fit short screens (landscape phones).
	local function resize()
		local scale = Theme.scale()
		local available = Theme.viewport() / scale
		holder.Size = UDim2.fromOffset(math.min(width, available.X - 24), math.min(height, available.Y - 40))
	end
	resize()
	table.insert(resizers, resize)
	Panels.register(name, holder, opts.onOpen, { onClose = opts.onClose, dim = opts.dim })
	holder:SetAttribute("Title", title)
	return window, body, footer, header
end

function Panels.setTitle(window: Frame, title: string?, subtitle: string?)
	local header = window:FindFirstChild("Header")
	if not header then return end
	if title then header.Title.Text = string.upper(title) end
	if subtitle then header.Subtitle.Text = subtitle end
end

-- Section heading inside a body: a numbered step badge plus label ("1  CHOOSE MATERIAL").
function Panels.section(parent: Instance, order: number, step: string?, text: string, color: Color3?): Frame
	local row = Theme.make("Frame", {
		Name = "Section" .. order,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local x = 0
	if step then
		Theme.make("TextLabel", {
			Text = step,
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = color or Theme.Colors.yellow,
			Corner = 17,
			Stroke = { Color = Theme.Colors.ink, Thickness = 3 },
			TextSize = 22,
			TextColor3 = Theme.Colors.ink,
			Parent = row,
		})
		x = 44
	end
	Theme.text({
		Name = "Text",
		Text = text,
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.new(1, -x, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 26,
		Parent = row,
	})
	return row
end

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.ButtonB and current then
		Panels.close()
	end
end)

return Panels
