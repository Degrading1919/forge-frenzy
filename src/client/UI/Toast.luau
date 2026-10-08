--!nonstrict
-- Toasts (short centered messages), auto-forge tickers (bottom-left stack), big announcement
-- banners and floating "+$123" cash pops.
local Theme = require(script.Parent.Theme)
local Panels = require(script.Parent.Panels)

local Toast = {}

local toastHolder: Frame? = nil
local tickerHolder: Frame? = nil
local banner: Frame? = nil
local bannerQueue = {}
local bannerBusy = false

local KIND_COLORS = {
	info = Theme.Colors.blue,
	good = Theme.Colors.green,
	bad = Theme.Colors.red,
}

local function ensure()
	if toastHolder then return end
	local layer = Panels.layer("Toast")
	toastHolder = Theme.make("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(460, 260),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	Theme.autoScale(toastHolder)
	-- Below the HUD's cash pill, tutorial and alert (they occupy ~250 design px).
	local function place()
		toastHolder.Position = UDim2.new(0.5, 0, 0, 252 * Theme.scale() + 8)
	end
	place()
	Theme.onScaleChanged(place)
	local l = Theme.list(toastHolder, 6, nil, Enum.HorizontalAlignment.Center)
	l.VerticalAlignment = Enum.VerticalAlignment.Top

	tickerHolder = Theme.make("Frame", {
		Name = "Tickers",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -150),
		Size = UDim2.fromOffset(260, 260),
		BackgroundTransparency = 1,
		Parent = Panels.layer("Tickers"),
	})
	Theme.autoScale(tickerHolder, 0.9)
	local tl = Theme.list(tickerHolder, 5)
	tl.VerticalAlignment = Enum.VerticalAlignment.Bottom

	banner = Theme.make("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		Size = UDim2.fromOffset(620, 96),
		BackgroundColor3 = Theme.Colors.panelDark,
		Visible = false,
		Corner = 20,
		Stroke = { Color = Theme.Colors.ink, Thickness = 4 },
		Parent = layer,
	})
	Theme.autoScale(banner)
	Theme.text({
		Name = "Text",
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		TextSize = 34,
		TextScaled = true,
		Parent = banner,
	})
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = banner
end

function Toast.show(text: any, kind: string?)
	ensure()
	local color = KIND_COLORS[kind or "info"] or KIND_COLORS.info
	local f = Theme.text({
		Text = tostring(text),
		Size = UDim2.new(1, 0, 0, 46),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		TextSize = 24,
		Corner = 14,
		Stroke = { Color = Theme.Colors.ink, Thickness = 3 },
		Padding = 8,
		Parent = toastHolder,
	})
	Theme.pop(f, 0.6)
	task.delay(3, function()
		if f.Parent then
			local tw = Theme.tween(f, 0.35, { TextTransparency = 1, BackgroundTransparency = 1 })
			local stroke = f:FindFirstChildOfClass("UIStroke")
			if stroke then Theme.tween(stroke, 0.35, { Transparency = 1 }) end
			local ts = f:FindFirstChild("TextStroke")
			if ts then Theme.tween(ts, 0.35, { Transparency = 1 }) end
			tw.Completed:Connect(function()
				f:Destroy()
			end)
		end
	end)
	local kids = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("TextLabel") then table.insert(kids, c) end
	end
	if #kids > 4 then kids[1]:Destroy() end
end

-- Small stacked result ticker (auto-forge results).
function Toast.ticker(text: string, color: Color3?)
	ensure()
	local f = Theme.text({
		Text = text,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = color or Theme.Colors.panelDark,
		BackgroundTransparency = 0.05,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Corner = 10,
		Stroke = { Color = Theme.Colors.ink, Thickness = 2.5 },
		Padding = 6,
		Parent = tickerHolder,
	})
	Theme.pop(f, 0.7)
	task.delay(4, function()
		if f.Parent then
			local tw = Theme.tween(f, 0.35, { TextTransparency = 1, BackgroundTransparency = 1 })
			tw.Completed:Connect(function()
				f:Destroy()
			end)
		end
	end)
	local kids = {}
	for _, c in tickerHolder:GetChildren() do
		if c:IsA("TextLabel") then table.insert(kids, c) end
	end
	if #kids > 5 then kids[1]:Destroy() end
end

local function runBanner()
	if bannerBusy then return end
	bannerBusy = true
	task.spawn(function()
		while #bannerQueue > 0 do
			local item = table.remove(bannerQueue, 1)
			local color = Theme.rarityColor(item.rarity)
			banner.Text.Text = item.text
			banner.BackgroundColor3 = color:Lerp(Theme.Colors.panelDark, 0.45)
			local pop = banner.Pop
			pop.Scale = 0.3
			banner.Visible = true
			Theme.tween(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			task.wait(3.2)
			Theme.tween(pop, 0.2, { Scale = 0.01 })
			task.wait(0.22)
			banner.Visible = false
		end
		bannerBusy = false
	end)
end

function Toast.announce(text: string, rarity: number?)
	ensure()
	if #bannerQueue >= 3 then table.remove(bannerQueue, 1) end
	table.insert(bannerQueue, { text = text, rarity = rarity or 5 })
	runBanner()
end

-- Floating "+$123" that rises from a screen position (defaults to the cash pill).
function Toast.cashPop(amount: number, at: Vector2?)
	ensure()
	local layer = Panels.layer("Toast")
	local v = Theme.viewport()
	local start = at or Vector2.new(v.X / 2, 70 * Theme.scale())
	local label = Theme.text({
		Text = "+" .. Theme.money(amount),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(start.X, start.Y + 40),
		Size = UDim2.fromOffset(260, 50),
		TextSize = 40,
		TextColor3 = Theme.Colors.cash,
		Parent = layer,
	})
	Theme.autoScale(label)
	Theme.pop(label, 0.5)
	local tw = Theme.tween(label, 1.1, { Position = UDim2.fromOffset(start.X, start.Y + 4), TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tw.Completed:Connect(function()
		label:Destroy()
	end)
end

return Toast
