--!nonstrict
-- Always-on HUD: coins, selected material + storage, rail of panel buttons, FORGE button, auto chip.
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local Format = require(script.Parent.Parent.UI.Format)
local Data = require(script.Parent.Parent.UI.Data)
local Panels = require(script.Parent.Parent.UI.Panels)
local Toast = require(script.Parent.Parent.UI.Toast)

local M = { Priority = 50 }

local C = Theme.Colors

local RAIL = {
	{ "⚒", "Forge", "Forge" },
	{ "⛏", "Materials", "Materials" },
	{ "🏭", "Workshop", "Workshop" },
	{ "🎒", "Inventory", "Inventory" },
	{ "🥚", "Pets", "Pets" },
	{ "✨", "Evolve", "Evolution" },
	{ "🛒", "Shop", "Shop" },
	{ "⚙", "Settings", "Settings" },
}

local refs = {}
local coinValue = Instance.new("NumberValue")
local coinTween

local function build()
	local layer = Panels.layer("Hud")

	-- Coins (top center)
	local coins = Theme.make("Frame", {
		Name = "Coins",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.34, 0, 0, 56),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.1,
		Corner = 14,
		Stroke = { Color = C.brass, Thickness = 3 },
		Parent = layer,
	})
	local lim = Instance.new("UISizeConstraint")
	lim.MinSize = Vector2.new(170, 48)
	lim.MaxSize = Vector2.new(340, 64)
	lim.Parent = coins
	Theme.make("TextLabel", {
		Text = "🪙",
		Size = UDim2.new(0, 44, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		TextSize = 28,
		Parent = coins,
	})
	refs.coins = Theme.make("TextLabel", {
		Text = "0",
		Size = UDim2.new(1, -56, 1, 0),
		Position = UDim2.new(0, 50, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = Theme.ts(32),
		TextColor3 = C.coin,
		TextWrapped = false,
		Parent = coins,
	})

	-- Auto chip
	refs.chip = Theme.make("Frame", {
		Name = "AutoChip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.new(0, 270, 0, 40),
		BackgroundColor3 = C.bg,
		Visible = false,
		Corner = 20,
		Stroke = { Color = C.orange, Thickness = 2 },
		Parent = layer,
	})
	refs.chipText = Theme.label({
		Text = "AUTO FORGING",
		Size = UDim2.new(1, -96, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = Theme.ts(15),
		TextColor3 = C.orange,
		Parent = refs.chip,
	})
	Theme.button({
		Text = "Stop",
		Color = C.bad,
		Size = UDim2.new(0, 80, 0, 32),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		TextSize = Theme.ts(16),
		OnClick = function()
			local ok, res = Net.call("ForgeStopAuto")
			if not ok then Toast.show(res, "bad") end
		end,
		Parent = refs.chip,
	})

	-- Info card (top-left)
	local compact = Theme.compact()
	local card = Theme.make("Frame", {
		Name = "InfoCard",
		Position = UDim2.new(0, 8, 0, 60),
		Size = UDim2.new(0, compact and 170 or 240, 0, compact and 86 or 100),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.1,
		Corner = 12,
		Stroke = { Color = C.brass, Thickness = 2 },
		Parent = layer,
	})
	refs.card = card
	refs.matName = Theme.label({
		Text = "Copper",
		Size = UDim2.new(1, -60, 0, 24),
		Position = UDim2.new(0, 8, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = Theme.ts(20),
		Font = Theme.Font,
		TextWrapped = false,
		Parent = card,
	})
	refs.rank = Theme.label({
		Text = "R0",
		Size = UDim2.new(0, 48, 0, 22),
		Position = UDim2.new(1, -54, 0, 5),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.panel2,
		TextSize = Theme.ts(13),
		TextColor3 = C.coin,
		Corner = 11,
		Stroke = { Color = C.brass, Thickness = 1.5 },
		Parent = card,
	})
	refs.bar = Theme.bar({
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.new(0, 8, 0, 32),
		FillColor = C.orange,
		Parent = card,
	})
	refs.rates = Theme.label({
		Text = "",
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.new(0, 8, 0, 58),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = Theme.ts(12),
		TextColor3 = C.dim,
		Parent = card,
	})

	-- Rail (left)
	local rail = Theme.scroll({
		Name = "Rail",
		Position = UDim2.new(0, 8, 0, compact and 152 or 168),
		Size = UDim2.new(0, 60, 1, compact and -162 or -178),
		ScrollBarThickness = 0,
		Parent = layer,
	})
	refs.rail = rail
	Theme.list(rail, 6)
	for i, def in RAIL do
		local b = Theme.button({
			Text = def[1],
			Color = C.panel2,
			Size = UDim2.new(0, 54, 0, 54),
			LayoutOrder = i,
			TextSize = 26,
			Font = Theme.Font2,
			OnClick = function()
				Panels.toggle(def[3])
			end,
			Parent = rail,
		})
		Theme.make("TextLabel", {
			Text = def[2],
			Size = UDim2.new(1, 0, 0, 12),
			Position = UDim2.new(0, 0, 1, -13),
			TextSize = 9,
			Font = Theme.Font2,
			TextColor3 = C.dim,
			TextWrapped = false,
			Parent = b,
		})
	end

	-- Big FORGE button
	refs.forge = Theme.button({
		Name = "ForgeButton",
		Text = "⚒ FORGE",
		Color = C.orange,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0, compact and 170 or 220, 0, compact and 58 or 68),
		TextSize = Theme.ts(32),
		Stroke = { Color = C.brass, Thickness = 4 },
		OnClick = function()
			Panels.open("Forge")
		end,
		Parent = layer,
	})
end

local function onProfile(p)
	if not refs.coins then return end
	-- coins count-up
	local target = p.coins or 0
	if coinTween then coinTween:Cancel() end
	coinTween = Theme.tween(coinValue, 0.45, { Value = target })

	local mi = p.selectedMaterial or 1
	local mat = Data.mat(mi)
	refs.matName.Text = mat.name
	refs.matName.TextColor3 = mat.color
	refs.rank.Text = "Rank " .. tostring(p.evolutionRank or 0)
	local rates = p.rates or {}
	local cap = rates.capacity or 0
	local total = Data.sumIngots(p)
	local mine = (p.ingots and p.ingots[mi]) or 0
	Theme.setBar(refs.bar, cap > 0 and total / cap or 0, string.format("%s ingots  %s/%s", Format.abbr(mine), Format.abbr(total), Format.abbr(cap)))
	refs.bar.Fill.BackgroundColor3 = (cap > 0 and total >= cap) and C.bad or C.orange
	refs.rates.Text = string.format("⛏ %s ore/min   🔩 %s ingots/min", Format.rate(rates.orePerSec), Format.rate(rates.ingotPerSec))

	local mode = p.autoMode or "off"
	refs.chip.Visible = mode ~= "off"
	if mode ~= "off" then
		refs.chipText.Text = mode == "premium" and "AUTO FORGE  4x luck" or "AUTO FORGE  1.5x luck"
	end
end

local function refreshVisibility()
	local open = Panels.isOpen()
	refs.forge.Visible = not open
	refs.card.Visible = not open
	refs.rail.Visible = not open
end

function M.init()
	build()
	coinValue.Changed:Connect(function(v)
		refs.coins.Text = Format.abbr(math.floor(v + 0.5))
	end)
	Panels.Changed:Connect(refreshVisibility)
	refreshVisibility()
	State.observe(onProfile)
end

return M
