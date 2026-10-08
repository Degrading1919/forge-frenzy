--!nonstrict
-- Dramatic weapon reveal card with SELL / KEEP / Forge Again.
local TweenService = game:GetService("TweenService")
local Net = require(script.Parent.Parent.Net)
local Theme = require(script.Parent.Theme)
local Data = require(script.Parent.Data)
local Format = require(script.Parent.Format)
local Panels = require(script.Parent.Panels)
local Toast = require(script.Parent.Toast)
local Viewport = require(script.Parent.Viewport)

local ForgeReveal = {}

local C = Theme.Colors
local ui = {}
local current = nil -- { weapon, luck, strikes, isNew, again }
local busy = false
local valueNum = Instance.new("NumberValue")
local glowTween: Tween? = nil
local showId = 0

local function build()
	local root = Theme.make("Frame", {
		Name = "ForgeReveal",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(10, 6, 5),
		BackgroundTransparency = 0.2,
		ClipsDescendants = true,
		Parent = Panels.layer("Panels"),
	})
	ui.root = root

	ui.flash = Theme.make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = root,
	})
	ui.big = Theme.make("TextLabel", {
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0.9, 0, 0, 120),
		TextSize = 72,
		TextTransparency = 1,
		TextWrapped = false,
		ZIndex = 22,
		Parent = root,
	})
	ui.bigScale = Instance.new("UIScale")
	ui.bigScale.Parent = ui.big

	local card = Theme.make("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0.5, 0, 0.92, 0),
		BackgroundColor3 = C.bg,
		Corner = 18,
		Stroke = { Color = C.brass, Thickness = 5 },
		Parent = root,
	})
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(440, 600)
	lim.Parent = card
	ui.card = card
	ui.cardScale = Instance.new("UIScale")
	ui.cardScale.Parent = card
	ui.stroke = card:FindFirstChildOfClass("UIStroke")
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 140, 135))
	grad.Parent = card

	ui.rarity = Theme.make("TextLabel", {
		Text = "COMMON",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, 8),
		TextSize = Theme.ts(34),
		Parent = card,
	})
	ui.name = Theme.label({
		Text = "",
		Size = UDim2.new(1, -24, 0, 50),
		Position = UDim2.new(0, 12, 0, 48),
		TextSize = Theme.ts(18),
		Parent = card,
	})
	ui.view = Theme.make("Frame", {
		Size = UDim2.new(1, -40, 0.38, 0),
		Position = UDim2.new(0, 20, 0, 100),
		BackgroundColor3 = Color3.fromRGB(20, 15, 13),
		Corner = 12,
		Parent = card,
	})
	ui.vf = Theme.make("ViewportFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = ui.view,
	})
	ui.vf.Ambient = Color3.fromRGB(150, 140, 130)
	ui.vf.LightColor = Color3.fromRGB(255, 240, 220)
	ui.new = Theme.make("TextLabel", {
		Text = "NEW!",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.new(0, 70, 0, 28),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.bad,
		TextSize = 18,
		Rotation = 10,
		Corner = 8,
		Visible = false,
		ZIndex = 5,
		Parent = ui.view,
	})
	ui.value = Theme.make("TextLabel", {
		Text = "0",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0.38, 106),
		TextSize = Theme.ts(32),
		TextColor3 = C.coin,
		Parent = card,
	})
	ui.info = Theme.label({
		Text = "",
		Size = UDim2.new(1, -24, 0, 36),
		Position = UDim2.new(0, 12, 0.38, 146),
		TextSize = Theme.ts(13),
		TextColor3 = C.dim,
		Parent = card,
	})
	local row = Theme.make("Frame", {
		Size = UDim2.new(1, -24, 0, 50),
		Position = UDim2.new(0, 12, 1, -118),
		BackgroundTransparency = 1,
		Parent = card,
	})
	Theme.list(row, 8, Enum.FillDirection.Horizontal)
	ui.sell = Theme.button({
		Text = "SELL",
		Color = C.good,
		Size = UDim2.new(0.5, -4, 1, 0),
		LayoutOrder = 1,
		OnClick = function()
			ForgeReveal.resolve("sell", false)
		end,
		Parent = row,
	})
	ui.keep = Theme.button({
		Text = "KEEP",
		Color = Color3.fromRGB(70, 130, 220),
		Size = UDim2.new(0.5, -4, 1, 0),
		LayoutOrder = 2,
		OnClick = function()
			ForgeReveal.resolve("keep", false)
		end,
		Parent = row,
	})
	ui.again = Theme.button({
		Text = "Forge Again",
		Color = C.orange,
		Size = UDim2.new(1, -24, 0, 50),
		Position = UDim2.new(0, 12, 1, -60),
		OnClick = function()
			ForgeReveal.again()
		end,
		Parent = card,
	})
	Panels.register("ForgeReveal", root, nil, { locked = true, fullscreen = true, noBackdrop = true })
end

local function burst(color: Color3, n: number)
	for i = 1, n do
		local ang = math.random() * math.pi * 2
		local dist = 0.25 + math.random() * 0.4
		local p = Theme.make("TextLabel", {
			Text = (i % 2 == 0) and "✦" or "✧",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.45, 0),
			Size = UDim2.new(0, 28, 0, 28),
			TextColor3 = color,
			TextSize = math.random(20, 40),
			ZIndex = 19,
			Parent = ui.root,
		})
		local tw = Theme.tween(p, 0.9 + math.random() * 0.6, {
			Position = UDim2.new(0.5 + math.cos(ang) * dist, 0, 0.45 + math.sin(ang) * dist, 0),
			TextTransparency = 1,
			Rotation = math.random(-180, 180),
		})
		tw.Completed:Connect(function()
			p:Destroy()
		end)
	end
end

local function setButtons(on: boolean)
	Theme.setEnabled(ui.sell, on)
	Theme.setEnabled(ui.keep, on)
	Theme.setEnabled(ui.again, on)
end

function ForgeReveal.init()
	build()
	valueNum.Changed:Connect(function(v)
		ui.value.Text = "🪙 " .. Format.abbr(math.floor(v + 0.5))
	end)
end

-- payload = { weapon, luck, strikes, auto }; ctx = { isNew: boolean, again: (() -> ())? }
function ForgeReveal.show(payload: any, ctx: any)
	local w = payload.weapon
	if not w then return end
	showId += 1
	local id = showId
	current = { weapon = w, luck = payload.luck, strikes = payload.strikes, isNew = ctx and ctx.isNew, again = ctx and ctx.again }
	busy = false
	local color = Theme.rarityColor(w.r)
	local rname = Theme.RarityNames[w.r] or "Common"
	local big = w.r >= 5

	ui.rarity.Text = string.upper(rname)
	ui.rarity.TextColor3 = color
	ui.name.Text = Data.weaponName(w)
	ui.stroke.Color = color
	ui.stroke.Thickness = 5
	ui.new.Visible = current.isNew == true
	ui.sell.Text = "SELL  🪙 " .. Format.abbr(w.v)
	ui.keep.Text = "KEEP"
	ui.again.Text = (w.r >= 3) and "Keep & Forge Again" or "Sell & Forge Again"
	ui.again.Visible = current.again ~= nil
	local luckText = payload.luck and string.format("Luck %.2fx", payload.luck) or "Luck -"
	local strikeText = payload.strikes and string.format("  -  %d strikes", payload.strikes) or ""
	ui.info.Text = luckText .. strikeText .. "  -  " .. (Data.mat(w.m).name) .. " band " .. Format.abbr(Data.mat(w.m).priceMin) .. "-" .. Format.abbr(Data.mat(w.m).priceMax)
	ui.value.Text = "🪙 0"
	valueNum.Value = 0
	setButtons(false)
	Viewport.weapon(ui.view, w, true, nil, ui.vf)
	local fit = math.min(1, Theme.viewport().Y / 580)
	local ySc = 0.92 / fit
	ui.cardScale.Scale = fit * (big and 1.05 or 1)
	ui.card.Visible = false
	ui.card.Size = UDim2.new(0, 0, ySc, 0)
	ui.flash.BackgroundTransparency = 1
	ui.big.TextTransparency = 1
	Panels.open("ForgeReveal")

	task.spawn(function()
		local stage = 0
		if w.r >= 4 then
			-- flash + title slam
			ui.flash.BackgroundColor3 = color
			ui.flash.BackgroundTransparency = 0.2
			Theme.tween(ui.flash, big and 1.2 or 0.6, { BackgroundTransparency = 1 })
			if big then
				ui.big.Text = string.upper(rname) .. "!"
				ui.big.TextColor3 = color
				ui.big.TextTransparency = 0
				ui.bigScale.Scale = 3
				Theme.tween(ui.bigScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
				burst(color, 20)
				task.wait(1.6)
				if id ~= showId then return end
				Theme.tween(ui.big, 0.3, { TextTransparency = 1 })
			else
				task.wait(0.35)
			end
		end
		if id ~= showId then return end
		ui.card.Visible = true
		local fullX = (Theme.compact() and 0.92 or 0.5) / fit
		Theme.tween(ui.card, 0.45, { Size = UDim2.new(fullX, 0, ySc, 0) }, Enum.EasingStyle.Back)
		task.wait(0.4)
		if id ~= showId then return end
		if big then burst(color, 28) elseif w.r >= 3 then burst(color, 10) end
		Theme.tween(valueNum, big and 1.8 or 0.8, { Value = w.v }, Enum.EasingStyle.Quart)
		if glowTween then glowTween:Cancel() end
		if w.r >= 3 then
			glowTween = TweenService:Create(ui.stroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 11 })
			glowTween:Play()
		end
		task.wait(big and 1.2 or 0.5)
		if id ~= showId then return end
		setButtons(true)
	end)
end

function ForgeReveal.resolve(action: string, quiet: boolean): boolean
	if busy or not current then return false end
	busy = true
	setButtons(false)
	local ok, res = Net.call("ForgeResolve", action)
	if not ok then
		Toast.show(res, "bad")
		busy = false
		setButtons(true)
		return false
	end
	if not quiet then
		if action == "sell" then
			local coins = type(res) == "table" and res.coins or current.weapon.v
			Toast.show("Sold for " .. Format.abbr(coins) .. " coins", "good")
		else
			Toast.show("Kept " .. Data.weaponName(current.weapon), "good")
		end
	end
	if glowTween then glowTween:Cancel() glowTween = nil end
	showId += 1
	Viewport.clear(ui.vf)
	Panels.close(true)
	return true
end

function ForgeReveal.again()
	if not current or busy then return end
	local cb = current.again
	local action = current.weapon.r >= 3 and "keep" or "sell"
	if ForgeReveal.resolve(action, false) and cb then
		cb()
	end
end

return ForgeReveal
