--!nonstrict
-- Inventory (kept weapons grid + details) and Showcase (pick a weapon for a pedestal slot) panels.
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local Format = require(script.Parent.Parent.UI.Format)
local Data = require(script.Parent.Parent.UI.Data)
local Panels = require(script.Parent.Parent.UI.Panels)
local Toast = require(script.Parent.Parent.UI.Toast)
local Viewport = require(script.Parent.Parent.UI.Viewport)

local M = { Priority = 30 }
local C = Theme.Colors

local invWindow, grid, countLabel, sortBtn
local detail = {}
local tiles = {} -- [weaponId] = { frame, vf, weapon }
local sortMode = "value"
local selectedId = nil
local setSig = ""
local checkQueued = false

local function weaponsById(p)
	local map = {}
	for _, w in p.weapons or {} do
		map[w.id] = w
	end
	return map
end

local function sorted(p)
	local list = table.clone(p.weapons or {})
	table.sort(list, function(a, b)
		if sortMode == "rarity" then
			if a.r ~= b.r then return a.r > b.r end
		end
		if a.v ~= b.v then return a.v > b.v end
		return a.id < b.id
	end)
	return list
end

-- Lazy viewport: only tiles inside (or near) the scroll viewport hold a ViewportFrame.
local function checkVisible()
	checkQueued = false
	if not invWindow or not invWindow.Visible then return end
	local top = grid.AbsolutePosition.Y - grid.AbsoluteSize.Y * 0.5
	local bottom = grid.AbsolutePosition.Y + grid.AbsoluteSize.Y * 1.5
	for _, t in tiles do
		local y = t.frame.AbsolutePosition.Y
		local visible = y + t.frame.AbsoluteSize.Y > top and y < bottom
		if visible and not t.vf then
			t.vf = Viewport.weapon(t.view, t.weapon, false)
			t.vf.ZIndex = 2
			t.icon.Visible = false
		elseif not visible and t.vf then
			t.vf:Destroy()
			t.vf = nil
			t.icon.Visible = true
		end
	end
end

local function queueCheck()
	if checkQueued then return end
	checkQueued = true
	task.delay(0.1, checkVisible)
end

local function refreshDetail(p)
	local w = selectedId and weaponsById(p)[selectedId]
	if not w then
		selectedId = nil
		detail.frame.Visible = false
		return
	end
	detail.frame.Visible = true
	local color = Theme.rarityColor(w.r)
	detail.name.Text = Data.weaponName(w)
	detail.rarity.Text = Theme.RarityNames[w.r]
	detail.rarity.TextColor3 = color
	detail.value.Text = "🪙 " .. Format.abbr(w.v)
	detail.sell.Text = "Sell  🪙 " .. Format.abbr(w.v)
	detail.stroke.Color = color
	if detail.shownId ~= w.id then
		detail.shownId = w.id
		Viewport.weapon(detail.view, w, true, nil, detail.vf)
	end
end

local function rebuild(p)
	local list = sorted(p)
	local ids = {}
	for _, w in list do
		table.insert(ids, w.id)
	end
	local sig = sortMode .. "|" .. table.concat(ids, ",")
	countLabel.Text = string.format("%d kept weapons", #list)
	if sig ~= setSig then
		setSig = sig
		local keep = {}
		for order, w in list do
			keep[w.id] = true
			local t = tiles[w.id]
			if not t then
				local color = Theme.rarityColor(w.r)
				local f = Theme.make("TextButton", {
					Text = "",
					BackgroundColor3 = C.panel,
					AutoButtonColor = false,
					Corner = 10,
					Stroke = { Color = color, Thickness = 2 },
					Parent = grid,
				})
				local view = Theme.make("Frame", { Size = UDim2.new(1, -10, 1, -50), Position = UDim2.new(0, 5, 0, 5), BackgroundColor3 = Color3.fromRGB(24, 19, 17), Corner = 8, Parent = f })
				local icon = Theme.make("TextLabel", { Text = Data.ClassIcons[w.c] or "⚔", Size = UDim2.new(1, 0, 1, 0), TextSize = 36, TextColor3 = Data.mat(w.m).color, Parent = view })
				Theme.label({ Text = Data.weaponName(w), Size = UDim2.new(1, -6, 0, 24), Position = UDim2.new(0, 3, 1, -44), TextSize = 9, TextColor3 = color, Parent = f })
				Theme.label({ Text = "🪙 " .. Format.abbr(w.v), Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -20), TextSize = 12, TextColor3 = C.coin, Parent = f })
				f.Activated:Connect(function()
					selectedId = w.id
					if State.profile then refreshDetail(State.profile) end
				end)
				t = { frame = f, view = view, icon = icon, weapon = w, vf = nil }
				tiles[w.id] = t
			end
			t.frame.LayoutOrder = order
		end
		for id, t in tiles do
			if not keep[id] then
				t.frame:Destroy()
				tiles[id] = nil
			end
		end
		queueCheck()
	end
	refreshDetail(p)
end

local function buildInventory()
	local content
	invWindow, content = Panels.create("Inventory", "Inventory", {
		onOpen = function()
			if State.profile then rebuild(State.profile) end
			queueCheck()
		end,
	})
	countLabel = Theme.label({ Text = "", Size = UDim2.new(0.5, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.dim, TextSize = Theme.ts(14), Parent = content })
	sortBtn = Theme.button({
		Text = "Sort: Value",
		Color = C.panel2,
		Size = UDim2.new(0, 130, 0, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.62, 0, 0, 0),
		TextSize = Theme.ts(14),
		OnClick = function()
			sortMode = sortMode == "value" and "rarity" or "value"
			sortBtn.Text = sortMode == "value" and "Sort: Value" or "Sort: Rarity"
			if State.profile then rebuild(State.profile) end
		end,
		Parent = content,
	})
	local wide = not Theme.compact()
	grid = Theme.scroll({ Size = UDim2.new(wide and 0.62 or 0.58, -6, 1, -44), Position = UDim2.new(0, 0, 0, 44), Parent = content })
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0, wide and 104 or 92, 0, wide and 124 or 112)
	gl.CellPadding = UDim2.new(0, 8, 0, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(queueCheck)

	local f = Theme.make("Frame", {
		Size = UDim2.new(wide and 0.38 or 0.42, -6, 1, 0),
		Position = UDim2.new(wide and 0.62 or 0.58, 6, 0, 0),
		BackgroundColor3 = C.panel,
		Corner = 12,
		Stroke = { Color = C.brass, Thickness = 2 },
		Visible = false,
		Parent = content,
	})
	detail.frame = f
	detail.stroke = f:FindFirstChildOfClass("UIStroke")
	detail.view = Theme.make("Frame", { Size = UDim2.new(1, -16, 0.36, 0), Position = UDim2.new(0, 8, 0, 8), BackgroundColor3 = Color3.fromRGB(24, 19, 17), Corner = 8, Parent = f })
	detail.vf = Theme.make("ViewportFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Parent = detail.view })
	detail.rarity = Theme.make("TextLabel", { Text = "", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0.36, 12), TextSize = Theme.ts(20), Parent = f })
	detail.name = Theme.label({ Text = "", Size = UDim2.new(1, -12, 0, 40), Position = UDim2.new(0, 6, 0.36, 36), TextSize = Theme.ts(13), Parent = f })
	detail.value = Theme.make("TextLabel", { Text = "", Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0.36, 78), TextSize = Theme.ts(22), TextColor3 = C.coin, Parent = f })
	detail.sell = Theme.button({
		Text = "Sell",
		Color = C.good,
		Size = UDim2.new(1, -16, 0, 44),
		Position = UDim2.new(0, 8, 1, -100),
		TextSize = Theme.ts(16),
		OnClick = function()
			if not selectedId then return end
			local ok, res = Net.call("SellWeapon", selectedId)
			if not ok then Toast.show(res, "bad") else Toast.show("Sold!", "good") end
		end,
		Parent = f,
	})
	Theme.button({
		Text = "Display",
		Color = Color3.fromRGB(70, 130, 220),
		Size = UDim2.new(1, -16, 0, 44),
		Position = UDim2.new(0, 8, 1, -50),
		TextSize = Theme.ts(16),
		OnClick = function()
			local p = State.profile
			if not p or not selectedId then return end
			local slot
			for i = 1, 6 do
				if (p.showcase and p.showcase[i] or "") == "" then slot = i break end
			end
			if not slot then
				Toast.show("All showcase slots are full - pick a pedestal to replace.", "bad")
				return
			end
			local ok, res = Net.call("SetShowcase", slot, selectedId)
			if not ok then Toast.show(res, "bad") else Toast.show("Displayed on pedestal " .. slot, "good") end
		end,
		Parent = f,
	})
end

-- Showcase -----------------------------------------------------------------

local scWindow, scList, scTitle, scSlot, scClear
local scRows = {}
local scSig = ""

local function refreshShowcase()
	local p = State.profile
	if not p or not scWindow or not scWindow.Visible then return end
	local slot = scSlot or 1
	local cur = p.showcase and p.showcase[slot] or ""
	local list = sorted(p)
	local ids = { slot, cur }
	for _, w in list do
		table.insert(ids, w.id)
	end
	local sig = table.concat(ids, ",")
	if sig == scSig then return end
	scSig = sig
	scTitle.Text = string.format("Pedestal %d  -  %s", slot, cur ~= "" and (weaponsById(p)[cur] and Data.weaponName(weaponsById(p)[cur]) or "weapon") or "empty")
	Theme.setEnabled(scClear, cur ~= "")
	for _, r in scRows do
		r:Destroy()
	end
	table.clear(scRows)
	if #list == 0 then
		table.insert(scRows, Theme.label({ Text = "No kept weapons yet. Forge something and press KEEP!", Size = UDim2.new(1, 0, 0, 60), TextColor3 = C.dim, Parent = scList }))
	end
	for i, w in list do
		local color = Theme.rarityColor(w.r)
		local f = Theme.make("Frame", { Size = UDim2.new(1, -8, 0, 54), BackgroundColor3 = C.panel, Corner = 8, Stroke = { Color = color, Thickness = 2 }, LayoutOrder = i, Parent = scList })
		Theme.label({ Text = Data.weaponName(w), Size = UDim2.new(1, -150, 0, 24), Position = UDim2.new(0, 10, 0, 5), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color, TextSize = Theme.ts(14), TextWrapped = false, Parent = f })
		Theme.label({ Text = "🪙 " .. Format.abbr(w.v), Size = UDim2.new(1, -150, 0, 18), Position = UDim2.new(0, 10, 0, 29), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.coin, TextSize = Theme.ts(12), Parent = f })
		Theme.button({
			Text = cur == w.id and "Placed" or "Place",
			Color = C.orange,
			Size = UDim2.new(0, 110, 0, 44),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			TextSize = Theme.ts(16),
			OnClick = function()
				local ok, res = Net.call("SetShowcase", slot, w.id)
				if not ok then Toast.show(res, "bad") else Panels.close() end
			end,
			Parent = f,
		})
		table.insert(scRows, f)
	end
end

local function buildShowcase()
	local content
	scWindow, content = Panels.create("Showcase", "Showcase", {
		onOpen = function(slot)
			scSlot = tonumber(slot) or 1
			scSig = ""
			refreshShowcase()
		end,
	})
	scTitle = Theme.label({ Text = "", Size = UDim2.new(1, -150, 0, 44), TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.ts(16), TextColor3 = C.coin, Parent = content })
	scClear = Theme.button({
		Text = "Clear slot",
		Color = C.bad,
		Size = UDim2.new(0, 140, 0, 44),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		TextSize = Theme.ts(16),
		OnClick = function()
			local ok, res = Net.call("SetShowcase", scSlot or 1, nil)
			if not ok then Toast.show(res, "bad") else Panels.close() end
		end,
		Parent = content,
	})
	scList = Theme.scroll({ Size = UDim2.new(1, 0, 1, -52), Position = UDim2.new(0, 0, 0, 52), Parent = content })
	Theme.list(scList, 6)
end

function M.init()
	buildInventory()
	buildShowcase()
	State.observe(function(p)
		if invWindow.Visible then rebuild(p) end
		refreshShowcase()
	end)
end

return M
