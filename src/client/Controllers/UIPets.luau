--!nonstrict
--[[
	Pets (docs/21 §12): the pet inventory with merging, and the egg stand hatch panel.

	Pets: cards with stars for merge level, EQUIP BEST and MERGE ALL up top, tap a pet for its
	3D close-up, bonus, EQUIP and MERGE (three of the same pet at the same level make one pet a
	level higher). Hatch: the egg's price, every pet it can give with exact odds, and big HATCH
	buttons. Results appear in the centered reveal with one big AWESOME! button.
]]
local State = require(script.Parent.Parent.State)
local Net = require(script.Parent.Parent.Net)
local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Panels = require(UI.Panels)
local Data = require(UI.Data)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local Reveal = require(UI.Reveal)
local Viewport = require(UI.Viewport)
local Format = require(UI.Format)

local M = { Priority = 10 }
local C = Theme.Colors

local pets: any = {}
local hatch: any = {}
local eggId = "hearth"

local function companions()
	return Data.config("Companions")
end

local function levelMult(lv: number): number
	local cfg = companions()
	return cfg and cfg.levelMultiplier and cfg.levelMultiplier(lv) or 1
end

local function scaledBonus(kind: string, lv: number): any
	local def = Data.companion(kind)
	local out = {}
	for k, v in def.bonus or {} do
		out[k] = v * levelMult(lv)
	end
	return out
end

local function copies(p: any, pet: any): number
	local n = 0
	for _, other in p.pets or {} do
		if other.kind == pet.kind and (other.lv or 1) == (pet.lv or 1) then
			n += 1
		end
	end
	return n
end

local function isEquipped(p: any, id: string): boolean
	return p.equipped ~= nil and table.find(p.equipped, id) ~= nil
end

-- Pet inventory ------------------------------------------------------------------------------

local function closeDetail()
	if pets.detail then
		pets.detail.Visible = false
		if pets.viewport then Viewport.clear(pets.viewport) end
	end
end

local function openDetail(pet: any)
	local p = State.profile
	if not p then return end
	pets.current = pet
	local def = Data.companion(pet.kind)
	local color = Data.petRarityColor(def.rarity)
	pets.detail.Visible = true
	Theme.pop(pets.card, 0.7)
	pets.card.BackgroundColor3 = Theme.shade(color, -0.55)
	pets.dName.Text = def.name
	pets.dName.TextColor3 = color
	local lv = pet.lv or 1
	pets.dStars.Text = string.rep("★", lv) .. string.rep("☆", 5 - lv)
	pets.dBonus.Text = Data.bonusText(scaledBonus(pet.kind, lv))
	Viewport.pet(pets.card, pet.kind, true, { Size = UDim2.fromOffset(200, 200), Position = UDim2.new(0.5, 0, 0, 92), AnchorPoint = Vector2.new(0.5, 0) }, pets.viewport)
	local equipped = isEquipped(p, pet.id)
	Theme.setText(pets.dEquip, if equipped then "UNEQUIP" else "EQUIP")
	Theme.setColor(pets.dEquip, if equipped then C.orange else C.green)
	local n = copies(p, pet)
	local canMerge = not def.premium and lv < 5 and n >= 3
	Theme.setText(pets.dMerge, if def.premium then "NO MERGE" elseif lv >= 5 then "MAX LEVEL" else string.format("MERGE %d/3", math.min(n, 3)))
	Theme.setEnabled(pets.dMerge, canMerge)
	pets.dHint.Text = if def.premium then "Premium pets keep their bonus" elseif lv >= 5 then "This pet is fully powered up!" else string.format("Merge 3 to get %s (x%.1f bonus)", string.rep("★", lv + 1), levelMult(lv + 1))
end

local function petCard(parent: Instance, pet: any, order: number, p: any)
	local def = Data.companion(pet.kind)
	local color = Data.petRarityColor(def.rarity)
	local b = Instance.new("TextButton")
	b.Name = "Pet_" .. pet.id
	b.LayoutOrder = order
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Theme.shade(color, -0.5)
	Theme.make("UICorner", { CornerRadius = UDim.new(0, 14), Parent = b })
	Theme.make("UIStroke", { Color = if isEquipped(p, pet.id) then C.green else color, Thickness = if isEquipped(p, pet.id) then 5 else 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	Theme.text({ Text = def.name, Size = UDim2.new(1, -8, 0, 40), Position = UDim2.fromOffset(4, 30), TextScaled = true, Parent = b })
	Theme.text({ Text = string.rep("★", pet.lv or 1), Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, 4), TextSize = 22, TextColor3 = C.yellow, Parent = b })
	Theme.text({ Text = def.rarity, Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 74), TextSize = 18, TextColor3 = color, Parent = b })
	if isEquipped(p, pet.id) then
		Theme.chip("ON", C.green, { Size = UDim2.fromOffset(44, 24), Position = UDim2.new(1, -4, 1, -4), AnchorPoint = Vector2.new(1, 1), TextSize = 16, Parent = b })
	end
	if not def.premium and (pet.lv or 1) < 5 and copies(p, pet) >= 3 then
		Theme.chip("MERGE!", C.pink, { Size = UDim2.fromOffset(70, 24), Position = UDim2.new(0, 4, 1, -4), AnchorPoint = Vector2.new(0, 1), TextSize = 15, Parent = b })
	end
	b.Activated:Connect(function()
		openDetail(pet)
	end)
	b.Parent = parent
end

local function buildPets()
	local window, body = Panels.create("Pets", "Pets", {
		width = 520,
		height = 640,
		color = Color3.fromRGB(230, 90, 170),
		subtitle = "Pets make your workshop faster",
		onOpen = function()
			closeDetail()
			M.refreshPets(true)
		end,
		onClose = closeDetail,
	})
	pets.window = window
	local top = Theme.make("Frame", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1, Parent = body })
	Theme.list(top, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	Theme.button({ Text = "EQUIP BEST", Color = C.green, Size = UDim2.fromOffset(210, 58), TextSize = 26, LayoutOrder = 1, OnClick = function()
		Kit.call("EquipBestPets")
	end, Parent = top })
	pets.mergeAll = Theme.button({ Text = "MERGE ALL", Color = C.pink, Size = UDim2.fromOffset(210, 58), TextSize = 26, LayoutOrder = 2, OnClick = function()
		Kit.call("MergeAll")
	end, Parent = top })
	pets.bonus = Theme.text({ LayoutOrder = 1, Text = "", Size = UDim2.new(1, 0, 0, 52), TextSize = 22, TextColor3 = C.yellow, Parent = body })
	pets.empty = Theme.text({ LayoutOrder = 2, Text = "No pets yet! Buy eggs in town.", Size = UDim2.new(1, 0, 0, 60), TextSize = 26, Visible = false, Parent = body })
	local grid = Theme.make("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = body })
	Theme.grid(grid, Vector2.new(112, 104), 8)
	pets.grid = grid
	local detail = Theme.make("TextButton", { Name = "Detail", Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Visible = false, ZIndex = 20, Corner = 22, Parent = window })
	detail.Activated:Connect(closeDetail)
	pets.detail = detail
	local card = Theme.card({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(420, 500), ZIndex = 21, Active = true, Parent = detail })
	pets.card = card
	pets.dName = Theme.text({ Text = "", Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 8), TextScaled = true, Parent = card })
	pets.dStars = Theme.text({ Text = "", Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(10, 50), TextSize = 34, TextColor3 = C.yellow, Parent = card })
	pets.viewport = Viewport.pet(card, "soot_mole", false, { Size = UDim2.fromOffset(200, 200), Position = UDim2.new(0.5, 0, 0, 92), AnchorPoint = Vector2.new(0.5, 0) })
	pets.dBonus = Theme.text({ Text = "", Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 296), TextSize = 26, TextColor3 = C.cash, Parent = card })
	local buttons = Theme.make("Frame", { Size = UDim2.new(1, -20, 0, 66), Position = UDim2.fromOffset(10, 334), BackgroundTransparency = 1, Parent = card })
	Theme.list(buttons, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	pets.dEquip = Theme.button({ Text = "EQUIP", Color = C.green, Size = UDim2.fromOffset(180, 62), TextSize = 28, LayoutOrder = 1, OnClick = function()
		local p, pet = State.profile, pets.current
		if not p or not pet then return end
		if isEquipped(p, pet.id) then
			Kit.call("UnequipPet", pet.id)
		else
			Kit.call("EquipPet", pet.id)
		end
		closeDetail()
	end, Parent = buttons })
	pets.dMerge = Theme.button({ Text = "MERGE", Color = C.pink, Size = UDim2.fromOffset(180, 62), TextSize = 26, LayoutOrder = 2, OnClick = function()
		local pet = pets.current
		if pet then
			local ok = Kit.call("MergePet", pet.id)
			if ok then closeDetail() end
		end
	end, Parent = buttons })
	pets.dHint = Theme.text({ Text = "", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 408), TextSize = 19, TextColor3 = C.dim, Parent = card })
	Theme.button({ Text = "RELEASE", Color = C.red, Size = UDim2.fromOffset(150, 46), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 440), TextSize = 20, OnClick = function()
		local pet = pets.current
		if pet then
			local ok = Kit.call("ReleasePet", pet.id)
			if ok then
				Toast.show("Bye bye, pet!", "info")
				closeDetail()
			end
		end
	end, Parent = card })
	for _, d in card:GetDescendants() do
		if d:IsA("GuiObject") then d.ZIndex = math.max(d.ZIndex, 22) end
	end
end

function M.refreshPets(force: boolean?)
	local p = State.profile
	if not p or not pets.window then return end
	local list = table.clone(p.pets or {})
	table.sort(list, function(a, b)
		local ea, eb = isEquipped(p, a.id), isEquipped(p, b.id)
		if ea ~= eb then return ea end
		local ra = Data.rarityIndex(Data.companion(a.kind).rarity) + (a.lv or 1) * 0.5
		local rb = Data.rarityIndex(Data.companion(b.kind).rarity) + (b.lv or 1) * 0.5
		if ra ~= rb then return ra > rb end
		return a.id < b.id
	end)
	Panels.setTitle(pets.window, string.format("Pets %d/100", #list), string.format("%d of %d equipped", #(p.equipped or {}), p.petSlots or 2))
	-- Total bonus from equipped pets.
	local total = {}
	for _, id in p.equipped or {} do
		for _, pet in list do
			if pet.id == id then
				for k, v in scaledBonus(pet.kind, pet.lv or 1) do
					total[k] = (total[k] or 0) + v
				end
			end
		end
	end
	pets.bonus.Text = "Your pets: " .. Data.bonusText(total)
	local mergeable = false
	for _, pet in list do
		if not Data.companion(pet.kind).premium and (pet.lv or 1) < 5 and copies(p, pet) >= 3 then
			mergeable = true
			break
		end
	end
	Theme.setEnabled(pets.mergeAll, mergeable)
	local key = #list .. ":" .. table.concat(p.equipped or {}, ",")
	for _, pet in list do
		key ..= pet.id .. (pet.lv or 1)
	end
	if not force and key == pets.key then return end
	pets.key = key
	for _, c in pets.grid:GetChildren() do
		if c:IsA("GuiButton") then c:Destroy() end
	end
	pets.empty.Visible = #list == 0
	for i, pet in list do
		petCard(pets.grid, pet, i, p)
	end
end

-- Hatch panel --------------------------------------------------------------------------------

local function buildHatch()
	local window, body, footer = Panels.create("Hatch", "Egg", {
		width = 500,
		height = 600,
		footer = 92,
		color = Color3.fromRGB(255, 120, 200),
		subtitle = "",
		onOpen = function(arg)
			if type(arg) == "string" then eggId = arg end
			M.refreshHatch(true)
		end,
	})
	hatch.window = window
	hatch.price = Theme.text({ LayoutOrder = 0, Text = "", Size = UDim2.new(1, 0, 0, 50), TextSize = 40, TextColor3 = C.cash, Parent = body })
	hatch.lock = Theme.text({ LayoutOrder = 1, Text = "", Size = UDim2.new(1, 0, 0, 30), TextSize = 22, TextColor3 = C.yellow, Parent = body })
	hatch.list = Theme.make("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = body })
	Theme.list(hatch.list, 6, nil, Enum.HorizontalAlignment.Center)
	Theme.list(footer, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	hatch.one = Theme.button({ Text = "HATCH!", Color = C.green, Size = UDim2.fromOffset(220, 84), TextSize = 34, LayoutOrder = 1, OnClick = function()
		Kit.call("Hatch", eggId, 1)
	end, Parent = footer })
	hatch.three = Theme.button({ Text = "x3", Color = C.purple, Size = UDim2.fromOffset(100, 84), TextSize = 30, LayoutOrder = 2, OnClick = function()
		Kit.call("Hatch", eggId, 3)
	end, Parent = footer })
	hatch.five = Theme.button({ Text = "x5", Color = C.purple, Size = UDim2.fromOffset(100, 84), TextSize = 30, LayoutOrder = 3, OnClick = function()
		Kit.call("Hatch", eggId, 5)
	end, Parent = footer })
end

function M.refreshHatch(force: boolean?)
	local p = State.profile
	local egg = Data.egg(eggId)
	if not p or not egg or not hatch.window then return end
	Panels.setTitle(hatch.window, egg.name, "Pets help your ore lines and forges")
	hatch.price.Text = Theme.money(egg.coinCost) .. " each"
	local tier = math.max(p.unlockedTier or 1, p.highestTierEver or 1)
	local locked = tier < (egg.unlockTier or 1)
	hatch.lock.Text = if locked then ("Unlock " .. Data.mat(egg.unlockTier).name .. " to open this egg") else ""
	hatch.lock.Visible = locked
	Theme.setEnabled(hatch.one, not locked and (p.coins or 0) >= egg.coinCost)
	local multi = p.entitlements and p.entitlements.MultiHatch and p.paidRandomAllowed
	hatch.three.Visible = multi == true
	hatch.five.Visible = multi == true
	if multi then
		Theme.setEnabled(hatch.three, not locked and (p.coins or 0) >= egg.coinCost * 3)
		Theme.setEnabled(hatch.five, not locked and (p.coins or 0) >= egg.coinCost * 5)
	end
	if force or hatch.builtFor ~= eggId then
		hatch.builtFor = eggId
		for _, c in hatch.list:GetChildren() do
			if c:IsA("Frame") then c:Destroy() end
		end
		for i, row in Data.eggOdds(eggId) do
			local def = Data.companion(row.kind)
			local color = Data.petRarityColor(def.rarity)
			local card = Theme.card({ LayoutOrder = i, Size = UDim2.new(1, -6, 0, 70), BackgroundColor3 = Theme.shade(color, -0.55), Stroke = { Color = color, Thickness = 3 }, Parent = hatch.list })
			Viewport.pet(card, row.kind, false, { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(4, 3) })
			Theme.text({ Text = def.name, Position = UDim2.fromOffset(74, 4), Size = UDim2.new(1, -170, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, Parent = card })
			Theme.text({ Text = Data.bonusText(def.bonus), Position = UDim2.fromOffset(74, 36), Size = UDim2.new(1, -170, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.yellow, Parent = card })
			Theme.text({ Text = Format.pct(row.percent / 100), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(90, 40), TextSize = 28, TextColor3 = color, Parent = card })
		end
	end
end

function M.init()
	buildPets()
	buildHatch()
	Net.on("Hatched", function(info)
		if type(info) == "table" and info.pets then
			local list = {}
			for _, pet in info.pets do
				table.insert(list, { kind = pet.k or pet.kind, lv = pet.lv or 1 })
			end
			Reveal.pets(list)
			Net.call("EquipBestPets")
		end
	end)
	Net.on("Merged", function(info)
		if type(info) == "table" and info.pets and #info.pets > 0 then
			local best = info.pets[#info.pets]
			Reveal.pets({ { kind = best.k or best.kind, lv = best.lv or 2 } }, "MERGED!")
		end
	end)
end

function M.start()
	State.observe(function()
		if Panels.isOpen("Pets") and not (pets.detail and pets.detail.Visible) then M.refreshPets() end
		if Panels.isOpen("Hatch") then M.refreshHatch() end
	end)
end

return M
