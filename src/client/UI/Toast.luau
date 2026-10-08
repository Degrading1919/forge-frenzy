--!nonstrict
-- Toasts (top stack), result tickers (side stack) and big rarity announcement banners.
local Theme = require(script.Parent.Theme)
local Panels = require(script.Parent.Panels)

local Toast = {}

local toastHolder: Frame? = nil
local tickerHolder: Frame? = nil
local banner: Frame? = nil
local bannerQueue = {}
local bannerBusy = false

local KIND_COLORS = {
	info = Theme.Colors.brass,
	good = Theme.Colors.good,
	bad = Theme.Colors.bad,
}

local function ensure()
	if toastHolder then return end
	local C = Theme.Colors
	local layer = Panels.layer("Toast")
	toastHolder = Theme.make("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.new(0.6, 0, 0.4, 0),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	local l = Theme.list(toastHolder, 6, nil, Enum.HorizontalAlignment.Center)
	l.VerticalAlignment = Enum.VerticalAlignment.Top
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(520, 9999)
	cap.Parent = toastHolder

	tickerHolder = Theme.make("Frame", {
		Name = "Tickers",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -90),
		Size = UDim2.new(0, 230, 0.5, 0),
		BackgroundTransparency = 1,
		Parent = Panels.layer("Tickers"),
	})
	local tl = Theme.list(tickerHolder, 4)
	tl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Right

	banner = Theme.make("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.22, 0),
		Size = UDim2.new(0.8, 0, 0, 90),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.15,
		Visible = false,
		Corner = 14,
		Stroke = { Color = C.brass, Thickness = 3 },
		Parent = layer,
	})
	local bc = Instance.new("UISizeConstraint")
	bc.MaxSize = Vector2.new(760, 120)
	bc.Parent = banner
	Theme.make("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.new(0, 10, 0, 0),
		TextSize = Theme.ts(30),
		Parent = banner,
	})
	local g = Instance.new("UIScale")
	g.Name = "Pop"
	g.Parent = banner
end

function Toast.show(text: any, kind: string?)
	ensure()
	local color = KIND_COLORS[kind or "info"] or KIND_COLORS.info
	local f = Theme.make("TextLabel", {
		Text = tostring(text),
		Size = UDim2.new(1, 0, 0, 40),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.12,
		BackgroundColor3 = Theme.Colors.bg,
		TextSize = Theme.ts(18),
		Font = Theme.Font2,
		Corner = 10,
		Stroke = { Color = color, Thickness = 2 },
		Padding = 8,
		Parent = toastHolder,
	})
	f.TextTransparency = 1
	f.BackgroundTransparency = 1
	Theme.tween(f, 0.2, { TextTransparency = 0, BackgroundTransparency = 0.12 })
	task.delay(3.2, function()
		if f.Parent then
			local tw = Theme.tween(f, 0.4, { TextTransparency = 1, BackgroundTransparency = 1 })
			tw.Completed:Connect(function()
				f:Destroy()
			end)
		end
	end)
	-- cap stack
	local kids = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("TextLabel") then table.insert(kids, c) end
	end
	if #kids > 5 then kids[1]:Destroy() end
end

-- Small stacked result ticker (auto-forge results).
function Toast.ticker(text: string, color: Color3?)
	ensure()
	local f = Theme.make("TextLabel", {
		Text = text,
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.2,
		TextSize = Theme.ts(14),
		Font = Theme.Font2,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = color or Theme.Colors.text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Corner = 8,
		Stroke = { Color = color or Theme.Colors.brass, Thickness = 1.5 },
		Padding = 5,
		Parent = tickerHolder,
	})
	task.delay(5, function()
		if f.Parent then
			local tw = Theme.tween(f, 0.4, { TextTransparency = 1, BackgroundTransparency = 1 })
			tw.Completed:Connect(function()
				f:Destroy()
			end)
		end
	end)
	local kids = {}
	for _, c in tickerHolder:GetChildren() do
		if c:IsA("TextLabel") then table.insert(kids, c) end
	end
	if #kids > 6 then kids[1]:Destroy() end
end

local function runBanner()
	if bannerBusy then return end
	bannerBusy = true
	task.spawn(function()
		while #bannerQueue > 0 do
			local item = table.remove(bannerQueue, 1)
			local color = Theme.rarityColor(item.rarity)
			banner.Text.Text = item.text
			banner.Text.TextColor3 = color
			banner.UIStroke.Color = color
			local pop = banner.Pop
			pop.Scale = 0.4
			banner.Visible = true
			Theme.tween(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			task.wait(3.6)
			Theme.tween(pop, 0.25, { Scale = 0.01 })
			task.wait(0.28)
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

return Toast
