--!nonstrict
-- Materials panel: 32 materials grouped by era, select / unlock-next, journal pips.
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local Format = require(script.Parent.Parent.UI.Format)
local Data = require(script.Parent.Parent.UI.Data)
local Panels = require(script.Parent.Parent.UI.Panels)
local Toast = require(script.Parent.Parent.UI.Toast)

local M = { Priority = 30 }
local C = Theme.Colors

local window, unlockBtn, unlockLabel
local rows = {}

local function call(action, ...)
	local ok, res = Net.call(action, ...)
	if not ok then Toast.show(res, "bad") end
	return ok, res
end

local function refresh()
	local p = State.profile
	if not p or not window or not window.Visible then return end
	local tier = p.unlockedTier or 1
	local nextCost = p.costs and p.costs.unlockNext
	local nextIdx = tier + 1
	if nextCost == false or nextIdx > 32 then
		unlockBtn.Text = "All materials unlocked"
		Theme.setEnabled(unlockBtn, false)
	else
		unlockBtn.Text = string.format("Unlock next: %s for 🪙 %s", Data.mat(nextIdx).name, Format.abbr(nextCost or Data.mat(nextIdx).unlockCost))
		Theme.setEnabled(unlockBtn, (p.coins or 0) >= (nextCost or math.huge))
	end
	for i, r in rows do
		local unlocked = i <= tier
		local selected = i == p.selectedMaterial
		r.frame.BackgroundTransparency = unlocked and 0 or 0.45
		r.name.TextTransparency = unlocked and 0 or 0.4
		r.lock.Visible = not unlocked
		r.btn.Visible = unlocked
		if unlocked then
			r.btn.Text = selected and "Selected" or "Select"
			Theme.setColor(r.btn, selected and C.good or C.orange)
			Theme.setEnabled(r.btn, not selected)
		end
		r.stroke.Color = selected and C.good or C.brass
		local mask = p.journal and p.journal[i] or 0
		for rarity = 1, 6 do
			r.pips[rarity].BackgroundColor3 = Data.hasBit(mask, rarity) and Theme.rarityColor(rarity) or Color3.fromRGB(35, 30, 28)
		end
	end
end

local function build()
	local content
	window, content = Panels.create("Materials", "Materials", { onOpen = refresh })
	unlockBtn = Theme.button({
		Name = "UnlockNext",
		Text = "",
		Color = C.good,
		Size = UDim2.new(1, 0, 0, 48),
		TextSize = Theme.ts(20),
		OnClick = function()
			local ok = call("UnlockMaterial")
			if ok then Toast.show("Material unlocked!", "good") end
		end,
		Parent = content,
	})
	local list = Theme.scroll({ Size = UDim2.new(1, 0, 1, -56), Position = UDim2.new(0, 0, 0, 54), Parent = content })
	Theme.list(list, 5)
	local lastEra
	for i = 1, 32 do
		local mat = Data.mat(i)
		local era = Data.eraName(mat.era, i)
		if era ~= lastEra then
			lastEra = era
			Theme.label({
				Text = string.upper(era),
				Size = UDim2.new(1, -8, 0, 26),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = C.brass,
				TextSize = Theme.ts(15),
				LayoutOrder = i * 2 - 1,
				Parent = list,
			})
		end
		local f = Theme.make("Frame", {
			Name = "Material_" .. i,
			Size = UDim2.new(1, -8, 0, 58),
			BackgroundColor3 = C.panel,
			Corner = 8,
			Stroke = { Color = C.brass, Thickness = 1.5 },
			LayoutOrder = i * 2,
			Parent = list,
		})
		Theme.make("Frame", { Size = UDim2.new(0, 10, 1, -12), Position = UDim2.new(0, 6, 0, 6), BackgroundColor3 = mat.color, Corner = 4, Parent = f })
		local name = Theme.label({
			Text = mat.name,
			Size = UDim2.new(0.4, -20, 0, 24),
			Position = UDim2.new(0, 22, 0, 5),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = mat.color,
			TextSize = Theme.ts(17),
			Font = Theme.Font,
			TextWrapped = false,
			Parent = f,
		})
		local valueLabel = Theme.label({
			Text = Format.abbr(mat.priceMin) .. " - " .. Format.abbr(mat.priceMax) .. " coins",
			Size = UDim2.new(0.4, -20, 0, 18),
			Position = UDim2.new(0, 22, 0, 31),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.dim,
			TextSize = Theme.ts(12),
			TextWrapped = false,
			Parent = f,
		})
		-- journal pips
		local pipRow = Theme.make("Frame", { Size = UDim2.new(0.28, 0, 0, 14), Position = UDim2.new(0.4, 0, 0.5, -7), BackgroundTransparency = 1, Parent = f })
		Theme.list(pipRow, 3, Enum.FillDirection.Horizontal)
		local pips = {}
		for r = 1, 6 do
			pips[r] = Theme.make("Frame", { Size = UDim2.new(0, 14, 0, 14), BackgroundColor3 = Color3.fromRGB(35, 30, 28), Corner = 7, Stroke = { Color = Theme.rarityColor(r), Thickness = 1 }, LayoutOrder = r, Parent = pipRow })
		end
		local btn = Theme.button({
			Text = "Select",
			Color = C.orange,
			Size = UDim2.new(0, 96, 0, 44),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			TextSize = Theme.ts(16),
			OnClick = function()
				call("SelectMaterial", i)
			end,
			Parent = f,
		})
		local lock = Theme.label({
			Text = "🔒 " .. Format.abbr(mat.unlockCost),
			Size = UDim2.new(0, 96, 1, 0),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			TextColor3 = C.dim,
			TextSize = Theme.ts(14),
			Parent = f,
		})
		rows[i] = { frame = f, name = name, pips = pips, btn = btn, lock = lock, stroke = f:FindFirstChildOfClass("UIStroke") }
		local function resize()
			local narrow = f.AbsoluteSize.X < 540
			f.Size = UDim2.new(1, -8, 0, narrow and 82 or 58)
			name.Size = narrow and UDim2.new(1, -138, 0, 24) or UDim2.new(0.4, -20, 0, 24)
			valueLabel.Size = narrow and UDim2.new(1, -138, 0, 18) or UDim2.new(0.4, -20, 0, 18)
			pipRow.Size = UDim2.new(0, 102, 0, 14)
			pipRow.Position = narrow and UDim2.new(0, 22, 0, 58) or UDim2.new(0.4, 0, 0.5, -7)
		end
		f:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
		Panels.onViewportChanged(resize)
		resize()
	end
end

function M.init()
	build()
	State.observe(refresh)
end

return M
