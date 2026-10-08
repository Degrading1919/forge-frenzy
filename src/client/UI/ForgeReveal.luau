--!nonstrict
-- Dramatic weapon reveal card with SELL / KEEP / Forge Again.
local TweenService = game:GetService("TweenService")
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
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
	lim.MaxSize = Vector2.new(700, 600)
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
		Name = "Actions",
		Size = UDim2.new(1, -24, 0, 50),
		Position = UDim2.new(0, 12, 1, -118),
		BackgroundTransparency = 1,
		Parent = card,
	})
	ui.row = row
	Theme.list(row, 8, Enum.FillDirection.Horizontal)
	ui.sell = Theme.button({
		Name = "SellOrContinue",
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
		Name = "Keep",
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
		Name = "ForgeAgain",
		Text = "Forge Again",
		Color = C.orange,
		Size = UDim2.new(1, -24, 0, 50),
		Position = UDim2.new(0, 12, 1, -60),
		OnClick = function()
			ForgeReveal.again()
		end,
		Parent = card,
	})
	local function resize()
		local available = root.AbsoluteSize
		if available.X <= 0 then available = Theme.viewport() - Vector2.new(0, 58) end
		local wide = available.Y < 420 and available.X >= 500
		local width = math.min(wide and 700 or 440, available.X - 24)
		local height = math.min(600, available.Y - 24)
		card.Size = UDim2.fromOffset(width, height)
		ui.big.TextSize = math.min(72, math.floor(width / 7))
		ui.rarity.TextSize = wide and 26 or 30
		ui.name.TextSize = 17
		ui.value.TextSize = wide and 26 or 30
		ui.info.TextSize = 13
		if wide then
			ui.view.Position = UDim2.new(0, 12, 0, 48)
			ui.view.Size = UDim2.new(0.42, -12, 1, -60)
			ui.name.Position = UDim2.new(0.44, 0, 0, 42)
			ui.name.Size = UDim2.new(0.56, -12, 0, 44)
			ui.value.Position = UDim2.new(0.44, 0, 0, 88)
			ui.value.Size = UDim2.new(0.56, -12, 0, 32)
			ui.info.Position = UDim2.new(0.44, 0, 0, 122)
			ui.info.Size = UDim2.new(0.56, -12, 0, math.max(36, height - 234))
			row.Position = UDim2.new(0.44, 0, 1, -108)
			row.Size = UDim2.new(0.56, -12, 0, 46)
			ui.again.Position = UDim2.new(0.44, 0, 1, -56)
			ui.again.Size = UDim2.new(0.56, -12, 0, 46)
		else
			local previewHeight = math.clamp(height - 340, 72, 210)
			ui.name.Position = UDim2.fromOffset(12, 48)
			ui.name.Size = UDim2.new(1, -24, 0, 44)
			ui.view.Position = UDim2.fromOffset(20, 98)
			ui.view.Size = UDim2.new(1, -40, 0, previewHeight)
			ui.value.Position = UDim2.fromOffset(0, previewHeight + 104)
			ui.value.Size = UDim2.new(1, 0, 0, 38)
			ui.info.Position = UDim2.fromOffset(12, previewHeight + 146)
			ui.info.Size = UDim2.new(1, -24, 0, 52)
			row.Position = UDim2.new(0, 12, 1, -118)
			row.Size = UDim2.new(1, -24, 0, 50)
			ui.again.Position = UDim2.new(0, 12, 1, -60)
			ui.again.Size = UDim2.new(1, -24, 0, 50)
		end
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	Panels.onViewportChanged(resize)
	resize()
	Panels.register("ForgeReveal", root, nil, { locked = true, fullscreen = true, noBackdrop = true })
end

local function burst(color: Color3, n: number)
	if State.profile and State.profile.settings and State.profile.settings.vfx == false then return end
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
	current = { weapon = w, luck = payload.luck, strikes = payload.strikes, autoSold = payload.autoSold == true, isNew = ctx and ctx.isNew, again = ctx and ctx.again }
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
	ui.sell.Text = current.autoSold and "CONTINUE" or "SELL  🪙 " .. Format.abbr(w.v)
	ui.sell.Size = UDim2.new(current.autoSold and 1 or 0.5, current.autoSold and 0 or -4, 1, 0)
	ui.keep.Visible = not current.autoSold
	ui.keep.Text = "KEEP"
	ui.again.Text = current.autoSold and "Forge Again" or ((w.r >= 3) and "Keep & Forge Again" or "Sell & Forge Again")
	ui.again.Visible = current.again ~= nil
	local luckText = payload.luck and string.format("Luck %.2fx", payload.luck) or "Luck -"
	local strikeText = payload.strikes and string.format("  -  %d strikes", payload.strikes) or ""
	ui.info.Text = luckText .. strikeText .. "  -  " .. (Data.mat(w.m).name) .. " band " .. Format.abbr(Data.mat(w.m).priceMin) .. "-" .. Format.abbr(Data.mat(w.m).priceMax)
	if current.autoSold then ui.info.Text ..= "\nAuto-sold for " .. Format.abbr(w.v) .. " coins" end
	ui.value.Text = "🪙 0"
	valueNum.Value = 0
	setButtons(false)
	Viewport.weapon(ui.view, w, true, nil, ui.vf)
	ui.cardScale.Scale = 0.88
	ui.card.Visible = false
	ui.flash.BackgroundTransparency = 1
	ui.big.TextTransparency = 1
	Panels.open("ForgeReveal")

	task.spawn(function()
		local stage = 0
		local vfx = not (State.profile and State.profile.settings and State.profile.settings.vfx == false)
		if w.r >= 4 and vfx then
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
		Theme.tween(ui.cardScale, 0.3, { Scale = 1 })
		task.wait(0.4)
		if id ~= showId then return end
		if big then burst(color, 28) elseif w.r >= 3 then burst(color, 10) end
		Theme.tween(valueNum, big and 1.8 or 0.8, { Value = w.v }, Enum.EasingStyle.Quart)
		if glowTween then glowTween:Cancel() end
		if w.r >= 3 and vfx then
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
	local ok, res = true, { coins = current.weapon.v }
	if not current.autoSold then ok, res = Net.call("ForgeResolve", action) end
	if not ok then
		Toast.show(res, "bad")
		busy = false
		setButtons(true)
		return false
	end
	if not quiet then
		if current.autoSold then
			-- The server already sold this primary weapon using the player's filter.
		elseif action == "sell" then
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
	current = nil
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
