--!nonstrict
-- Pets panel (owned companions, equip/unequip, egg shop links) and Hatch panel + hatch reveal.
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

-- Pets panel ---------------------------------------------------------------------
local petsWin, petsList, slotsLabel, bonusLabel
local petRows = {}
local petsSig = ""
local eggRowBuilt = false

local function isEquipped(p, id: string): boolean
	return table.find(p.equipped or {}, id) ~= nil
end

local function refreshPets()
	local p = State.profile
	if not p or not petsWin or not petsWin.Visible then return end
	local ids = { #(p.equipped or {}), p.petSlots or 0 }
	for _, pet in p.pets or {} do
		table.insert(ids, pet.id .. (isEquipped(p, pet.id) and "*" or ""))
	end
	local sig = table.concat(ids, ",")
	if sig == petsSig then return end
	petsSig = sig

	slotsLabel.Text = string.format("Equipped %d / %d", #(p.equipped or {}), p.petSlots or 0)
	local totals = { extract = 0, smelt = 0, prep = 0, storage = 0 }
	local cfg = Data.config("Companions")
	local cap = cfg and cfg.FamilyCap or 2
	for _, pet in p.pets or {} do
		if isEquipped(p, pet.id) then
			for k, v in Data.companion(pet.kind).bonus or {} do
				totals[k] = (totals[k] or 0) + v
			end
		end
	end
	for k, v in totals do
		totals[k] = math.min(v, cap)
	end
	bonusLabel.Text = "Active bonuses: " .. Data.bonusText(totals)

	for _, r in petRows do
		r:Destroy()
	end
	table.clear(petRows)
	if #(p.pets or {}) == 0 then
		table.insert(petRows, Theme.label({ Text = "No companions yet. Hatch an egg!", Size = UDim2.new(1, 0, 0, 50), TextColor3 = C.dim, LayoutOrder = 1, Parent = petsList }))
	end
	for i, pet in p.pets or {} do
		local def = Data.companion(pet.kind)
		local color = Data.petRarityColor(def.rarity)
		local eq = isEquipped(p, pet.id)
		local f = Theme.make("Frame", { Size = UDim2.new(1, -8, 0, 60), BackgroundColor3 = eq and C.panel2 or C.panel, Corner = 8, Stroke = { Color = color, Thickness = eq and 3 or 1.5 }, LayoutOrder = 10 + i, Parent = petsList })
		Theme.make("Frame", { Size = UDim2.new(0, 36, 0, 36), Position = UDim2.new(0, 10, 0.5, -18), BackgroundColor3 = def.color or color, Corner = 18, Stroke = { Color = color, Thickness = 2 }, Parent = f })
		Theme.label({ Text = def.name .. "  (" .. tostring(def.rarity) .. ")", Size = UDim2.new(1, -190, 0, 24), Position = UDim2.new(0, 56, 0, 8), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color, TextSize = Theme.ts(15), TextWrapped = false, Parent = f })
		Theme.label({ Text = Data.bonusText(def.bonus), Size = UDim2.new(1, -190, 0, 20), Position = UDim2.new(0, 56, 0, 32), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.dim, TextSize = Theme.ts(12), TextWrapped = false, Parent = f })
		Theme.button({
			Text = eq and "Unequip" or "Equip",
			Color = eq and C.steel or C.good,
			Size = UDim2.new(0, 110, 0, 44),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			TextSize = Theme.ts(16),
			OnClick = function()
				local ok, res = Net.call(eq and "UnequipPet" or "EquipPet", pet.id)
				if not ok then Toast.show(res, "bad") end
			end,
			Parent = f,
		})
		table.insert(petRows, f)
	end
end

local function buildPets()
	local content
	petsWin, content = Panels.create("Pets", "Companions", { onOpen = function() petsSig = "" refreshPets() end })
	slotsLabel = Theme.label({ Text = "", Size = UDim2.new(0.4, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.coin, TextSize = Theme.ts(16), Parent = content })
	bonusLabel = Theme.label({ Text = "", Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.dim, TextSize = Theme.ts(13), Parent = content })
	local eggs = Theme.make("Frame", { Size = UDim2.new(1, 0, 0, 50), Position = UDim2.new(0, 0, 0, 52), BackgroundTransparency = 1, Parent = content })
	Theme.list(eggs, 6, Enum.FillDirection.Horizontal)
	for i, egg in Data.eggs() do
		Theme.button({
			Text = "🥚 " .. egg.name .. "\n🪙 " .. Format.abbr(egg.coinCost),
			Color = egg.color or C.orange,
			Size = UDim2.new(0, 120, 1, 0),
			TextSize = Theme.ts(12),
			LayoutOrder = i,
			OnClick = function()
				Panels.open("Hatch", egg.id)
			end,
			Parent = eggs,
		})
	end
	petsList = Theme.scroll({ Size = UDim2.new(1, 0, 1, -108), Position = UDim2.new(0, 0, 0, 108), Parent = content })
	Theme.list(petsList, 6)
end

-- Hatch panel --------------------------------------------------------------------
local hatchWin, hatchContent
local hatchEggId
local hatchUI = {}
local hatching = false
local revealedFlag = false

local function refreshHatch()
	local p = State.profile
	local egg = Data.egg(hatchEggId)
	if not egg or not hatchWin or not hatchWin.Visible then return end
	local coins = p and p.coins or 0
	local multi = p and p.entitlements and p.entitlements.MultiHatch
	hatchUI.name.Text = egg.name
	hatchUI.name.TextColor3 = egg.color or C.orange
	hatchUI.info.Text = string.format("Cost: 🪙 %s per egg   -   Requires material tier %d", Format.abbr(egg.coinCost), egg.unlockTier or 1)
	for count, b in hatchUI.buttons do
		local locked = count > 1 and not multi
		b.Text = locked and string.format("Hatch x%d 🔒", count) or string.format("Hatch x%d\n🪙 %s", count, Format.abbr(egg.coinCost * count))
		Theme.setEnabled(b, locked or (coins >= egg.coinCost * count and not hatching))
	end
end

local function buildHatch()
	local scroll
	hatchWin, hatchContent = Panels.create("Hatch", "Hatchery", { onOpen = function(id)
		hatchEggId = id or (Data.eggs()[1] and Data.eggs()[1].id)
		hatchUI.rebuildOdds()
		refreshHatch()
	end })
	hatchUI.name = Theme.make("TextLabel", { Text = "", Size = UDim2.new(1, 0, 0, 34), TextSize = Theme.ts(26), Parent = hatchContent })
	hatchUI.info = Theme.label({ Text = "", Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 34), TextColor3 = C.dim, TextSize = Theme.ts(13), Parent = hatchContent })
	local row = Theme.make("Frame", { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 1, -56), BackgroundTransparency = 1, Parent = hatchContent })
	Theme.list(row, 8, Enum.FillDirection.Horizontal)
	hatchUI.buttons = {}
	for i, count in { 1, 3, 5 } do
		hatchUI.buttons[count] = Theme.button({
			Text = "",
			Color = count == 1 and C.orange or Color3.fromRGB(150, 90, 220),
			Size = UDim2.new(1 / 3, -6, 1, 0),
			TextSize = Theme.ts(15),
			LayoutOrder = i,
			OnClick = function()
				M.hatch(count)
			end,
			Parent = row,
		})
	end
	Theme.label({ Text = "ODDS", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 62), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.brass, TextSize = 14, Parent = hatchContent })
	scroll = Theme.scroll({ Size = UDim2.new(1, 0, 1, -146), Position = UDim2.new(0, 0, 0, 84), Parent = hatchContent })
	Theme.list(scroll, 4)
	local oddsRows = {}
	function hatchUI.rebuildOdds()
		for _, r in oddsRows do
			r:Destroy()
		end
		table.clear(oddsRows)
		for i, o in Data.eggOdds(hatchEggId) do
			local color = Data.petRarityColor(o.rarity)
			local f = Theme.make("Frame", { Size = UDim2.new(1, -8, 0, 30), BackgroundColor3 = C.panel, Corner = 6, LayoutOrder = i, Parent = scroll })
			Theme.label({ Text = string.format("%s  (%s)", o.name, tostring(o.rarity)), Size = UDim2.new(0.7, 0, 1, 0), Position = UDim2.new(0, 8, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color, TextSize = Theme.ts(13), TextWrapped = false, Parent = f })
			Theme.label({ Text = string.format("%.3f%%", o.percent), Size = UDim2.new(0.3, -8, 1, 0), Position = UDim2.new(0.7, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = Theme.ts(13), Parent = f })
			table.insert(oddsRows, f)
		end
	end
end

-- Hatch reveal ---------------------------------------------------------------------
local rev = {}

local function buildReveal()
	local root = Theme.make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(10, 6, 5), BackgroundTransparency = 0.15, ClipsDescendants = true, Parent = Panels.layer("Panels") })
	rev.root = root
	rev.egg = Theme.make("TextLabel", { Text = "🥚", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 160, 0, 160), TextSize = 120, Parent = root })
	rev.cards = Theme.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.46, 0), Size = UDim2.new(0.94, 0, 0.7, 0), BackgroundTransparency = 1, Visible = false, Parent = root })
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0, Theme.compact() and 110 or 150, 0, Theme.compact() and 150 or 200)
	gl.CellPadding = UDim2.new(0, 10, 0, 10)
	gl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gl.VerticalAlignment = Enum.VerticalAlignment.Center
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = rev.cards
	rev.ok = Theme.button({ Text = "Awesome!", Color = C.orange, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.new(0, 200, 0, 52), Visible = false, OnClick = function() Panels.close(true) end, Parent = root })
	Panels.register("HatchReveal", root, nil, { locked = true, fullscreen = true, noBackdrop = true })
end

local function showHatched(pets)
	if type(pets) ~= "table" or #pets == 0 then return end
	revealedFlag = true
	for _, c in rev.cards:GetChildren() do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	rev.cards.Visible = false
	rev.ok.Visible = false
	rev.egg.Visible = true
	rev.egg.Text = "🥚"
	rev.egg.Rotation = 0
	rev.egg.Size = UDim2.new(0, 160, 0, 160)
	Panels.open("HatchReveal")
	task.spawn(function()
		for i = 1, 8 do
			Theme.tween(rev.egg, 0.09, { Rotation = (i % 2 == 0 and 1 or -1) * (6 + i * 3) })
			task.wait(0.1)
		end
		rev.egg.Text = "💥"
		Theme.tween(rev.egg, 0.25, { Size = UDim2.new(0, 260, 0, 260), TextTransparency = 1 })
		task.wait(0.25)
		rev.egg.Visible = false
		rev.egg.TextTransparency = 0
		rev.cards.Visible = true
		for i, pet in pets do
			local kind = pet.k or pet.kind
			local def = Data.companion(kind)
			local color = Data.petRarityColor(def.rarity)
			local card = Theme.make("Frame", { BackgroundColor3 = C.bg, Corner = 12, Stroke = { Color = color, Thickness = 3 }, LayoutOrder = i, Parent = rev.cards })
			local sc = Instance.new("UIScale")
			sc.Scale = 0
			sc.Parent = card
			local view = Theme.make("Frame", { Size = UDim2.new(1, -12, 0.55, 0), Position = UDim2.new(0, 6, 0, 6), BackgroundColor3 = Color3.fromRGB(24, 19, 17), Corner = 8, Parent = card })
			Viewport.pet(view, kind, true)
			Theme.label({ Text = def.name, Size = UDim2.new(1, -8, 0, 36), Position = UDim2.new(0, 4, 0.55, 10), TextColor3 = color, TextSize = Theme.ts(14), Parent = card })
			Theme.label({ Text = tostring(def.rarity) .. "\n" .. Data.bonusText(def.bonus), Size = UDim2.new(1, -8, 0, 40), Position = UDim2.new(0, 4, 1, -46), TextColor3 = C.dim, TextSize = Theme.ts(11), Parent = card })
			Theme.tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			task.wait(0.25)
		end
		rev.ok.Visible = true
	end)
end

function M.hatch(count: number)
	if hatching or not hatchEggId then return end
	local p = State.profile
	if count > 1 and not (p and p.entitlements and p.entitlements.MultiHatch) then
		Toast.show("Multi-Hatch is a Shop item", "info")
		Panels.open("Shop")
		return
	end
	hatching = true
	revealedFlag = false
	refreshHatch()
	local ok, res = Net.call("Hatch", hatchEggId, count)
	if not ok then
		Toast.show(res, "bad")
	else
		task.wait(0.4) -- the Hatched push normally arrives first
		if not revealedFlag and type(res) == "table" then
			showHatched(res.pets)
		end
	end
	hatching = false
	refreshHatch()
end

function M.init()
	buildPets()
	buildHatch()
	buildReveal()
	State.observe(function()
		refreshPets()
		refreshHatch()
	end)
	Net.on("Hatched", function(payload)
		if type(payload) == "table" then showHatched(payload.pets) end
	end)
end

return M
