--!nonstrict
--[[
	Reveal — the centered celebration popup for every reward (docs/21 §2, §12).

	A spinning sunburst, a big colored headline, the 3D weapon or pet front and center, its name,
	rarity and value, and one huge AWESOME! button right under it. Rewards queue so several in a
	row never overlap. Rare results get a longer anticipation beat, extra burst and sound.

	Reveal.weapon(weapon, opts)  opts: { sold, extras, onDisplay }
	Reveal.pets(pets, title)     pets: { { kind, lv? } }
	Reveal.message(title, subtitle, color, icon)
]]
local RunService = game:GetService("RunService")
local Theme = require(script.Parent.Theme)
local Panels = require(script.Parent.Panels)
local Data = require(script.Parent.Data)
local Viewport = require(script.Parent.Viewport)

local Reveal = {}
local C = Theme.Colors

local ui: any = nil
local queue = {}
local busy = false
local current: any = nil
local spinConn: RBXScriptConnection? = nil
Reveal.closed = Instance.new("BindableEvent")

local HEADLINES = { "NICE!", "GREAT!", "RARE!", "EPIC!", "LEGENDARY!", "MYTHIC!!" }

local function build()
	local layer = Panels.layer("Reveal")
	local root = Theme.make("Frame", {
		Name = "Reveal",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(10, 8, 30),
		BackgroundTransparency = 0.35,
		Visible = false,
		Active = true,
		Parent = layer,
	})
	local holder = Theme.make("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(460, 560),
		BackgroundTransparency = 1,
		Parent = root,
	})
	Theme.autoScale(holder, 1, Vector2.new(460, 560))
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = holder
	-- Sunburst rays behind the item.
	local rays = Theme.make("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 230),
		Size = UDim2.fromOffset(520, 520),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	-- Twelve bars through the center make 24 spokes that fade toward the edge.
	for i = 0, 11 do
		local ray = Theme.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.fromOffset(40, 520),
			Rotation = i * 15,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.7,
			Parent = rays,
		})
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = ray
	end
	local headline = Theme.text({
		Name = "Headline",
		Text = "NICE!",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 70),
		TextSize = 64,
		Parent = holder,
	})
	local stage = Theme.make("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(300, 300),
		BackgroundColor3 = C.panelDark,
		BackgroundTransparency = 0.25,
		Corner = 150,
		Stroke = { Color = C.ink, Thickness = 4 },
		Parent = holder,
	})
	local grid = Theme.make("Frame", {
		Name = "Grid",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(440, 300),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = holder,
	})
	Theme.grid(grid, Vector2.new(136, 140), 8)
	local name = Theme.text({
		Name = "ItemName",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 388),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 34,
		Parent = holder,
	})
	local detail = Theme.text({
		Name = "Detail",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 428),
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 30,
		TextColor3 = C.cash,
		Parent = holder,
	})
	local buttons = Theme.make("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 470),
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local bl = Theme.list(buttons, 12, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	bl.VerticalAlignment = Enum.VerticalAlignment.Center
	local awesome = Theme.button({
		Name = "Awesome",
		Text = "AWESOME!",
		Color = C.green,
		Size = UDim2.fromOffset(250, 80),
		TextSize = 36,
		LayoutOrder = 1,
		OnClick = function()
			Reveal.dismiss()
		end,
		Parent = buttons,
	})
	local second = Theme.button({
		Name = "Second",
		Text = "DISPLAY",
		Color = C.purple,
		Size = UDim2.fromOffset(170, 80),
		TextSize = 28,
		LayoutOrder = 2,
		OnClick = function()
			if current and current.onSecond then
				task.spawn(current.onSecond)
			end
			Reveal.dismiss()
		end,
		Parent = buttons,
	})
	ui = { root = root, holder = holder, pop = pop, rays = rays, headline = headline, stage = stage, grid = grid, name = name, detail = detail, awesome = awesome, second = second }
end

local function burst(color: Color3, n: number)
	for _ = 1, n do
		local s = Theme.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 230),
			Size = UDim2.fromOffset(14, 14),
			Rotation = math.random(0, 90),
			BackgroundColor3 = if math.random() < 0.5 then color else C.yellow,
			Corner = 3,
			Parent = ui.holder,
		})
		local a = math.random() * math.pi * 2
		local d = math.random(160, 300)
		local tw = Theme.tween(s, 0.9, { Position = UDim2.new(0.5, math.cos(a) * d, 0, 230 + math.sin(a) * d), BackgroundTransparency = 1, Rotation = math.random(180, 540) })
		tw.Completed:Connect(function()
			s:Destroy()
		end)
	end
end

local function clearStage()
	for _, c in ui.stage:GetChildren() do
		if c:IsA("ViewportFrame") then
			Viewport.clear(c)
			c:Destroy()
		end
	end
	for _, c in ui.grid:GetChildren() do
		if not c:IsA("UIGridLayout") then
			c:Destroy()
		end
	end
end

local function present(item: any)
	if not ui then build() end
	current = item
	clearStage()
	local color = item.color or C.yellow
	ui.headline.Text = item.headline or "NICE!"
	ui.headline.TextColor3 = color
	ui.name.Text = item.name or ""
	ui.name.TextColor3 = Color3.new(1, 1, 1)
	ui.detail.Text = item.detail or ""
	ui.detail.TextColor3 = item.detailColor or C.cash
	ui.stage.Visible = item.grid == nil
	ui.grid.Visible = item.grid ~= nil
	ui.stage.BackgroundColor3 = Theme.shade(color, -0.55)
	for _, ray in ui.rays:GetChildren() do
		ray.BackgroundColor3 = color
	end
	if item.render then
		pcall(item.render, ui.stage, ui.grid)
	end
	ui.second.Visible = item.secondText ~= nil
	if item.secondText then
		Theme.setText(ui.second, item.secondText)
	end
	ui.root.Visible = true
	ui.root.BackgroundTransparency = 1
	Theme.tween(ui.root, 0.2, { BackgroundTransparency = 0.35 })
	ui.pop.Scale = 0.2
	Theme.tween(ui.pop, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	burst(color, item.burst or 14)
	if spinConn then spinConn:Disconnect() end
	spinConn = RunService.RenderStepped:Connect(function(dt)
		ui.rays.Rotation = (ui.rays.Rotation + dt * 25) % 360
	end)
	-- Keyboard/gamepad: Enter or A dismisses.
end

local function nextItem()
	if busy or #queue == 0 then return end
	busy = true
	present(table.remove(queue, 1))
end

function Reveal.dismiss()
	if not ui or not busy then return end
	if spinConn then
		spinConn:Disconnect()
		spinConn = nil
	end
	local tw = Theme.tween(ui.pop, 0.15, { Scale = 0.05 })
	tw.Completed:Wait()
	ui.root.Visible = false
	clearStage()
	busy = false
	local was = current
	current = nil
	Reveal.closed:Fire(was)
	task.defer(nextItem)
end

function Reveal.isOpen(): boolean
	return busy
end

function Reveal.enqueue(item: any)
	if #queue >= 6 then table.remove(queue, 1) end
	table.insert(queue, item)
	nextItem()
end

function Reveal.weapon(w: any, opts: any?)
	opts = opts or {}
	local color = Theme.rarityColor(w.r)
	local extraText = ""
	if opts.extras and #opts.extras > 0 then
		extraText = string.format("  +%d more", #opts.extras)
	end
	Reveal.enqueue({
		headline = HEADLINES[w.r] or "NICE!",
		color = color,
		name = Data.weaponName(w),
		detail = (if opts.sold then "Sold for " else "") .. Theme.money(w.v) .. extraText,
		burst = 10 + (w.r or 1) * 6,
		render = function(stage)
			Viewport.weapon(stage, w, true, { Size = UDim2.new(1, -20, 1, -20), Position = UDim2.fromOffset(10, 10) })
		end,
		secondText = if opts.onDisplay then "DISPLAY" else nil,
		onSecond = opts.onDisplay,
	})
end

function Reveal.pets(list: { any }, title: string?)
	if #list == 0 then return end
	local Companions = Data.config("Companions")
	if #list == 1 then
		local pet = list[1]
		local def = Data.companion(pet.kind or pet.k)
		local color = Data.petRarityColor(def.rarity)
		local lv = pet.lv or 1
		Reveal.enqueue({
			headline = title or (string.upper(def.rarity) .. "!"),
			color = color,
			name = def.name .. (if lv > 1 then "  " .. string.rep("★", lv) else ""),
			detail = Data.bonusText(def.bonus and (function()
				local mult = Companions and Companions.levelMultiplier and Companions.levelMultiplier(lv) or 1
				local out = {}
				for k, v in def.bonus do out[k] = v * mult end
				return out
			end)()),
			detailColor = C.yellow,
			burst = 24,
			render = function(stage)
				Viewport.pet(stage, def.id or pet.kind, true, { Size = UDim2.new(1, -20, 1, -20), Position = UDim2.fromOffset(10, 10) })
			end,
		})
		return
	end
	Reveal.enqueue({
		headline = title or "NEW PETS!",
		color = C.pink,
		name = string.format("%d pets!", #list),
		detail = "",
		grid = true,
		burst = 30,
		render = function(_, grid)
			for i, pet in list do
				local def = Data.companion(pet.kind or pet.k)
				local color = Data.petRarityColor(def.rarity)
				local cell = Theme.card({ LayoutOrder = i, BackgroundColor3 = Theme.shade(color, -0.45), Stroke = { Color = color, Thickness = 3 }, Parent = grid })
				Viewport.pet(cell, def.id or pet.kind, true, { Size = UDim2.new(1, 0, 1, -30) })
				Theme.text({ Text = def.name, Size = UDim2.new(1, -6, 0, 28), Position = UDim2.new(0, 3, 1, -30), TextScaled = true, TextColor3 = color, Parent = cell })
			end
		end,
	})
end

function Reveal.message(title: string, subtitle: string?, color: Color3?, icon: string?, detail: string?)
	Reveal.enqueue({
		headline = title,
		color = color or C.yellow,
		name = subtitle or "",
		detail = detail or "",
		burst = 20,
		render = function(stage)
			Theme.text({ Text = icon or "⭐", Size = UDim2.new(1, 0, 1, 0), TextSize = 150, TextStroke = false, Parent = stage })
		end,
	})
end

return Reveal
