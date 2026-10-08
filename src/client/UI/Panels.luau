--!nonstrict
-- Owns the ForgeFrenzyUI ScreenGui, its layers, and the one-modal-panel-at-a-time manager.
-- Panels.open(name, arg?) / Panels.close() / Panels.register(name, frame, onOpen?, opts?)
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
Panels.Changed = changed.Event -- (name: string?)
local resizers: { () -> () } = {}

local LAYER_Z = { Hud = 1, Tickers = 5, Panels = 10, Toast = 30 }

function Panels.gui(): ScreenGui
	if gui then return gui end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = pg:FindFirstChild("ForgeFrenzyUI")
	if existing then existing:Destroy() end
	gui = Theme.make("ScreenGui", {
		Name = "ForgeFrenzyUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = pg,
	})
	local function onViewport()
		for _, fn in resizers do
			fn()
		end
	end
	local function hookCamera()
		local cam = workspace.CurrentCamera
		if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(onViewport) end
	end
	hookCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hookCamera()
		onViewport()
	end)
	return gui
end

-- Full-screen transparent container with a fixed z-order name (Hud, Tickers, Panels, Toast).
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
		BackgroundColor3 = Color3.new(0, 0, 0),
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
	local fullscreen = entry.opts.fullscreen
	backdrop.Visible = not entry.opts.noBackdrop
	backdrop.Active = not entry.opts.locked
	backdrop.BackgroundTransparency = 1
	Theme.tween(backdrop, 0.2, { BackgroundTransparency = entry.opts.dim or 0.45 })
	entry.frame.Visible = true
	if not fullscreen then
		local sc = entry.frame:FindFirstChild("OpenScale")
		if sc then
			sc.Scale = 0.9
			Theme.tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	if entry.onOpen then
		task.spawn(entry.onOpen, arg)
	end
	changed:Fire(name)
end

function Panels.toggle(name: string, arg: any?)
	if current == name then Panels.close() else Panels.open(name, arg) end
end

-- Standard modal window. Returns (window, content). Content fills below the header.
-- opts: widthScale, heightScale, maxSize (Vector2)
function Panels.create(name: string, title: string, opts: { [string]: any }?): (Frame, Frame)
	opts = opts or {}
	local C = Theme.Colors
	local window = Theme.make("Frame", {
		Name = name .. "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = C.bg,
		Corner = 16,
		Stroke = { Color = C.brass, Thickness = 3 },
		Parent = Panels.layer("Panels"),
	})
	local sc = Instance.new("UIScale")
	sc.Name = "OpenScale"
	sc.Parent = window
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = opts.maxSize or Vector2.new(900, 640)
	limit.MinSize = Vector2.new(280, 220)
	limit.Parent = window
	local function resize()
		if Theme.compact() then
			window.Size = UDim2.new(0.97, 0, 0.94, 0)
		else
			window.Size = UDim2.new(opts.widthScale or 0.64, 0, opts.heightScale or 0.8, 0)
		end
	end
	resize()
	table.insert(resizers, resize)

	Theme.make("TextLabel", {
		Name = "Title",
		Text = string.upper(title),
		Size = UDim2.new(1, -80, 0, 52),
		Position = UDim2.new(0, 16, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = Theme.ts(28),
		TextColor3 = C.coin,
		TextWrapped = false,
		Parent = window,
	})
	Theme.button({
		Name = "Close",
		Text = "X",
		Color = C.bad,
		Size = UDim2.new(0, 44, 0, 44),
		Position = UDim2.new(1, -8, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 22,
		OnClick = function()
			Panels.close()
		end,
		Parent = window,
	})
	Theme.make("Frame", {
		Size = UDim2.new(1, -24, 0, 2),
		Position = UDim2.new(0, 12, 0, 54),
		BackgroundColor3 = C.brass,
		BackgroundTransparency = 0.4,
		Parent = window,
	})
	local content = Theme.make("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 62),
		Size = UDim2.new(1, -24, 1, -72),
		ClipsDescendants = true,
		Parent = window,
	})
	Panels.register(name, window, opts.onOpen, { onClose = opts.onClose })
	return window, content
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.ButtonB and current then
		Panels.close()
	end
end)

return Panels
