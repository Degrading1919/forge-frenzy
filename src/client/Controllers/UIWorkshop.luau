--!nonstrict
-- Workshop panel: machine + gear upgrade cards.
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local Format = require(script.Parent.Parent.UI.Format)
local Panels = require(script.Parent.Parent.UI.Panels)
local Toast = require(script.Parent.Parent.UI.Toast)

local M = { Priority = 30 }
local C = Theme.Colors

local TRACKS = {
	{ "ExtractorOutput", "Extractor Speed", "⛏", "More ore per second", "levels" },
	{ "SmelterSpeed", "Smelter Speed", "🔥", "Faster ingot refining", "levels" },
	{ "StorageCapacity", "Storage", "📦", "Bigger ingot buffer", "levels" },
	{ "FurnaceHeat", "Furnace Heat", "♨", "Shorter heat-up before strikes", "levels" },
	{ "AnvilFinish", "Anvil Finish", "⚒", "Smoother forging downtime", "levels" },
	{ "Hammer", "Hammer", "🔨", "Gear: cuts cycle downtime", "gear" },
	{ "Gloves", "Gloves", "🧤", "Gear: material efficiency", "gear" },
	{ "Apron", "Apron", "🥼", "Gear: storage and utility", "gear" },
}

local window, ratesLabel
local cards = {}

local function refresh()
	local p = State.profile
	if not p or not window or not window.Visible then return end
	local r = p.rates or {}
	ratesLabel.Text = string.format(
		"Ore %s/min   Ingots %s/min   Capacity %s   Heat %.1fs   Window %.1fs",
		Format.rate(r.orePerSec), Format.rate(r.ingotPerSec), Format.abbr(r.capacity), r.heatSec or 0, r.windowSec or 0
	)
	for _, t in TRACKS do
		local card = cards[t[1]]
		local level = (p[t[5]] and p[t[5]][t[1]]) or 0
		local cost = p.costs and p.costs.upgrades and p.costs.upgrades[t[1]]
		card.level.Text = "Level " .. tostring(level)
		if cost == false then
			card.btn.Text = "MAX"
			Theme.setEnabled(card.btn, false)
		else
			cost = cost or 0
			card.btn.Text = "🪙 " .. Format.abbr(cost)
			Theme.setEnabled(card.btn, (p.coins or 0) >= cost)
		end
	end
end

local function build()
	local content
	window, content = Panels.create("Workshop", "Workshop", { onOpen = refresh })
	ratesLabel = Theme.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 40),
		TextColor3 = C.dim,
		TextSize = Theme.ts(13),
		Parent = content,
	})
	local list = Theme.scroll({ Size = UDim2.new(1, 0, 1, -46), Position = UDim2.new(0, 0, 0, 44), Parent = content })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = Theme.compact() and UDim2.new(1, -10, 0, 74) or UDim2.new(0.5, -10, 0, 78)
	grid.CellPadding = UDim2.new(0, 8, 0, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	for i, t in TRACKS do
		local f = Theme.make("Frame", {
			BackgroundColor3 = C.panel,
			Corner = 10,
			Stroke = { Color = t[5] == "gear" and C.coin or C.brass, Thickness = 1.5 },
			LayoutOrder = i,
			Parent = list,
		})
		Theme.make("TextLabel", { Text = t[3], Size = UDim2.new(0, 42, 0, 46), Position = UDim2.new(0, 4, 0, 0), TextSize = 30, Parent = f })
		Theme.label({ Text = t[2], Size = UDim2.new(1, -60, 0, 22), Position = UDim2.new(0, 52, 0, 6), TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.ts(16), Font = Theme.Font, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Parent = f })
		local level = Theme.label({ Text = "Level 0", Size = UDim2.new(1, -60, 0, 18), Position = UDim2.new(0, 52, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.ts(13), TextColor3 = C.coin, Parent = f })
		Theme.label({ Text = t[4], Size = UDim2.new(1, -142, 0, 44), Position = UDim2.new(0, 8, 0, 52), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, TextSize = Theme.ts(11), TextColor3 = C.dim, Parent = f })
		local btn = Theme.button({
			Name = t[1],
			Text = "",
			Color = C.good,
			Size = UDim2.new(0, 120, 0, 46),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -8, 1, -6),
			TextSize = Theme.ts(16),
			OnClick = function()
				local ok, res = Net.call("BuyUpgrade", t[1])
				if not ok then Toast.show(res, "bad") end
			end,
			Parent = f,
		})
		cards[t[1]] = { level = level, btn = btn }
	end
	local function resize()
		grid.CellSize = UDim2.new(list.AbsoluteSize.X < 720 and 1 or 0.5, -10, 0, 106)
	end
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	Panels.onViewportChanged(resize)
	resize()
end

function M.init()
	build()
	State.observe(refresh)
end

return M
