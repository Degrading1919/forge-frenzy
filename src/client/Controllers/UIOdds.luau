--!nonstrict
-- Odds disclosure panel: rarity chances for Manual (luck slider), Free auto 1.5x, Premium auto 4x,
-- plus craftsmanship and trait odds.
local UserInputService = game:GetService("UserInputService")
local Theme = require(script.Parent.Parent.UI.Theme)
local Format = require(script.Parent.Parent.UI.Format)
local Data = require(script.Parent.Parent.UI.Data)
local Panels = require(script.Parent.Parent.UI.Panels)

local M = { Priority = 20 }
local C = Theme.Colors

local luck = 2.5
local cells = {} -- [rarity] = { manual, free, premium }
local totals = {}
local sliderFill, sliderKnob, luckLabel, sliderBar
local dragging = false

local function setCell(label, v)
	label.Text = Format.pct(v, 3)
end

local function updateManual()
	local ch = Data.rarityChances(luck)
	local sum = 0
	for r = 1, 6 do
		setCell(cells[r].manual, ch[r])
		sum += ch[r]
	end
	totals.manual.Text = string.format("%.6f%%", sum * 100)
	luckLabel.Text = string.format("Manual luck: %.2fx", luck)
	local f = (luck - 1) / 4
	sliderFill.Size = UDim2.new(f, 0, 1, 0)
	sliderKnob.Position = UDim2.new(f, 0, 0.5, 0)
end

local function setLuckFromX(x: number)
	local pos, size = sliderBar.AbsolutePosition.X, sliderBar.AbsoluteSize.X
	local f = math.clamp((x - pos) / math.max(size, 1), 0, 1)
	luck = math.floor((1 + f * 4) * 100 + 0.5) / 100
	updateManual()
end

local function build()
	local window, content = Panels.create("Odds", "Forge Odds", {})
	Theme.label({ Text = "Rarity chance per forge. Luck changes rarity odds only.", Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.dim, TextSize = Theme.ts(12), Parent = content })
	luckLabel = Theme.label({ Text = "", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.coin, TextSize = Theme.ts(16), Parent = content })
	local function step(d)
		luck = math.clamp(math.floor((luck + d) * 100 + 0.5) / 100, 1, 5)
		updateManual()
	end
	Theme.button({ Text = "-", Color = C.panel2, Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(0, 0, 0, 48), TextSize = 26, OnClick = function() step(-0.25) end, Parent = content })
	Theme.button({ Text = "+", Color = C.panel2, Size = UDim2.new(0, 44, 0, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 48), TextSize = 26, OnClick = function() step(0.25) end, Parent = content })
	sliderBar = Theme.make("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.new(1, -112, 0, 18), Position = UDim2.new(0, 56, 0, 61), BackgroundColor3 = Color3.fromRGB(20, 16, 14), Corner = 9, Stroke = { Color = C.brass, Thickness = 1.5 }, Parent = content })
	sliderFill = Theme.make("Frame", { Size = UDim2.new(0.375, 0, 1, 0), BackgroundColor3 = C.orange, Corner = 9, Parent = sliderBar })
	sliderKnob = Theme.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0.375, 0, 0.5, 0), BackgroundColor3 = C.coin, Corner = 13, ZIndex = 3, Parent = sliderBar })
	sliderBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setLuckFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setLuckFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	local scroll = Theme.scroll({ Size = UDim2.new(1, 0, 1, -100), Position = UDim2.new(0, 0, 0, 98), Parent = content })
	Theme.list(scroll, 3)
	local order = 0
	local function row(texts, colors, header, height)
		order += 1
		local f = Theme.make("Frame", { Size = UDim2.new(1, -8, 0, height or 28), BackgroundColor3 = header and C.panel2 or C.panel, Corner = 6, LayoutOrder = order, Parent = scroll })
		local labels = {}
		local n = #texts
		for i, t in texts do
			labels[i] = Theme.label({
				Text = t,
				Size = UDim2.new(i == 1 and 0.28 or (0.72 / (n - 1)), 0, 1, 0),
				Position = UDim2.new(i == 1 and 0 or 0.28 + (i - 2) * 0.72 / (n - 1), 0, 0, 0),
				TextColor3 = colors and colors[i] or C.text,
				TextSize = Theme.ts(header and 12 or 13),
				Parent = f,
			})
		end
		return labels
	end
	row({ "Rarity", "Manual", "Free auto 1.5x", "Premium auto 4x" }, nil, true, 34)
	local free, prem = Data.rarityChances(1.5), Data.rarityChances(4)
	local freeSum, premSum = 0, 0
	for r = 1, 6 do
		local col = Theme.rarityColor(r)
		local l = row({ Theme.RarityNames[r], "", Format.pct(free[r], 3), Format.pct(prem[r], 3) }, { col, C.text, C.text, C.text })
		cells[r] = { manual = l[2] }
		freeSum += free[r]
		premSum += prem[r]
	end
	local t = row({ "Exact total", "", string.format("%.6f%%", freeSum * 100), string.format("%.6f%%", premSum * 100) }, { C.dim, C.dim, C.dim, C.dim })
	totals.manual = t[2]
	order += 1
	Theme.label({ Text = "CRAFTSMANSHIP (independent of luck)", Size = UDim2.new(1, -8, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.brass, TextSize = Theme.ts(13), LayoutOrder = order, Parent = scroll })
	local names, vals = { "Quality" }, { "Chance" }
	local cr = {}
	for i, n in Data.CraftNames do
		cr[i] = string.format("%s %s", n, Format.pct(Data.CraftOdds[i], 3))
	end
	row({ "Crude", "Standard", "Fine", "Masterwork", "Perfect" }, nil, true)
	local vals2 = {}
	for i = 1, 5 do vals2[i] = Format.pct(Data.CraftOdds[i], 3) end
	row(vals2, nil, false)
	order += 1
	Theme.label({ Text = "TRAIT CHANCE BY RARITY", Size = UDim2.new(1, -8, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.brass, TextSize = Theme.ts(13), LayoutOrder = order, Parent = scroll })
	row(Theme.RarityNames, Theme.RarityColors, true)
	local vals3 = {}
	for i = 1, 6 do vals3[i] = Format.pct(Data.TraitOdds[i], 3) end
	row(vals3, nil, false)
	order += 1
	Theme.label({
		Text = "Percentages are computed exactly from the forge formula and rounded only for display, so rows may differ from 100% by rounding. Final item odds also depend on craftsmanship, traits and design rolls. Your actual luck is decided by the server.",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.dim,
		TextSize = Theme.ts(11),
		LayoutOrder = order,
		Parent = scroll,
	})
	updateManual()
end

function M.init()
	build()
end

return M
