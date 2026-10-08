--!nonstrict
--[[
	Weapons UI (docs/21 §9, §11): the backpack, the podium picker and the central sell booth.

	Backpack: every kept weapon as a big card; tap for a 3D close-up and DISPLAY / TAKE DOWN.
	Podium picker: the same grid opened from one of your podiums; tapping a weapon puts it there.
	Sell booth: pick what to keep, then one giant SELL button with the exact cash you get.
	Selling only works at the booth in the hub (the server checks you are there).
]]
local State = require(script.Parent.Parent.State)
local Net = require(script.Parent.Parent.Net)
local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Panels = require(UI.Panels)
local Data = require(UI.Data)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local Viewport = require(UI.Viewport)
local Sfx = require(script.Parent.WorldUtil.Sfx)

local M = { Priority = 10 }
local C = Theme.Colors

local pack: any = {}
local sell: any = {}
local pickSlot: number? = nil
local sellKeep: number? = 4 -- default: keep Epic and better

local function isDisplayed(p: any, id: string): boolean
	return p.showcase ~= nil and table.find(p.showcase, id) ~= nil
end

local function weaponById(p: any, id: string): any
	for _, w in p.weapons or {} do
		if w.id == id then
			return w
		end
	end
	return nil
end

-- Detail overlay -----------------------------------------------------------------------------

local function closeDetail()
	if pack.detail then
		pack.detail.Visible = false
		if pack.viewport then
			Viewport.clear(pack.viewport)
		end
	end
end

local function openDetail(w: any)
	local p = State.profile
	if not p then return end
	pack.detailWeapon = w
	pack.detail.Visible = true
	Theme.pop(pack.detailCard, 0.7)
	local color = Theme.rarityColor(w.r)
	pack.detailCard.BackgroundColor3 = Theme.shade(color, -0.55)
	pack.dName.Text = Data.weaponName(w)
	pack.dName.TextColor3 = color
	pack.dRarity.Text = string.upper(Theme.RarityNames[w.r] or "") .. (if w.sf then ("  ·  stolen from " .. w.sf) else "")
	pack.dRarity.TextColor3 = color
	pack.dValue.Text = Theme.money(w.v)
	local perSec = w.v * 0.0002
	pack.dIncome.Text = string.format("On display: +%s/sec", Theme.money(perSec))
	Viewport.weapon(pack.detailCard, w, true, { Size = UDim2.fromOffset(220, 220), Position = UDim2.new(0.5, 0, 0, 64), AnchorPoint = Vector2.new(0.5, 0) }, pack.viewport)
	local shown = isDisplayed(p, w.id)
	Theme.setText(pack.dDisplay, if shown then "TAKE DOWN" else "DISPLAY")
	Theme.setColor(pack.dDisplay, if shown then C.orange else C.purple)
end

-- Backpack -----------------------------------------------------------------------------------

local function buildBackpack()
	local window, body = Panels.create("Backpack", "Backpack", {
		width = 520,
		height = 640,
		color = Color3.fromRGB(230, 120, 40),
		subtitle = "Display weapons on podiums to earn cash!",
		onOpen = function(arg)
			pickSlot = if type(arg) == "number" then arg else nil
			closeDetail()
			M.refreshBackpack(true)
		end,
		onClose = function()
			pickSlot = nil
			closeDetail()
		end,
	})
	pack.window = window
	pack.takeDown = Theme.button({ LayoutOrder = 0, Text = "TAKE DOWN THIS WEAPON", Color = C.orange, Size = UDim2.new(1, -10, 0, 56), TextSize = 24, Visible = false, OnClick = function()
		if pickSlot then
			Kit.call("SetShowcase", pickSlot, nil)
			Panels.close()
		end
	end, Parent = body })
	pack.empty = Theme.text({ LayoutOrder = 1, Text = "No weapons yet! Forge some at your anvil.", Size = UDim2.new(1, 0, 0, 80), TextSize = 26, Visible = false, Parent = body })
	local grid = Theme.make("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = body })
	Theme.grid(grid, Vector2.new(112, 134), 8)
	pack.grid = grid
	-- Detail overlay sits on top of the sheet.
	local detail = Theme.make("TextButton", { Name = "Detail", Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Visible = false, ZIndex = 20, Corner = 22, Parent = window })
	detail.Activated:Connect(closeDetail)
	pack.detail = detail
	local card = Theme.card({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(420, 470), ZIndex = 21, Active = true, Parent = detail })
	pack.detailCard = card
	pack.dName = Theme.text({ Text = "", Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(10, 8), TextScaled = true, ZIndex = 22, Parent = card })
	pack.dRarity = Theme.text({ Text = "", Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 42), TextSize = 20, ZIndex = 22, Parent = card })
	pack.viewport = Viewport.weapon(card, { m = 1, c = 1, r = 1, d = "sword_broad" }, false, { Size = UDim2.fromOffset(220, 220), Position = UDim2.new(0.5, 0, 0, 64), AnchorPoint = Vector2.new(0.5, 0) })
	pack.viewport.ZIndex = 22
	pack.dValue = Theme.text({ Text = "", Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 288), TextSize = 38, TextColor3 = C.cash, ZIndex = 22, Parent = card })
	pack.dIncome = Theme.text({ Text = "", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 328), TextSize = 21, TextColor3 = C.yellow, ZIndex = 22, Parent = card })
	pack.dDisplay = Theme.button({ Text = "DISPLAY", Color = C.purple, Size = UDim2.fromOffset(250, 64), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 364), TextSize = 30, ZIndex = 22, OnClick = function()
		local w = pack.detailWeapon
		if not w then return end
		local ok, res = Kit.call("ToggleShowcase", w.id)
		if ok then
			local nowShown = type(res) == "table" and table.find(res, w.id) ~= nil
			Toast.show(if nowShown then "On display! Walk to your podiums to see it" else "Taken down", "good")
			if nowShown then
				Net.call("TutorialStep", 7)
			end
			closeDetail()
		end
	end, Parent = card })
	Theme.text({ Text = "Sell weapons at the SELL booth in town", Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 436), TextSize = 18, TextColor3 = C.dim, ZIndex = 22, Parent = card })
	for _, d in card:GetDescendants() do
		if d:IsA("GuiObject") then d.ZIndex = math.max(d.ZIndex, 22) end
	end
end

function M.refreshBackpack(force: boolean?)
	local p = State.profile
	if not p or not pack.window then return end
	local weapons = p.weapons or {}
	Panels.setTitle(pack.window, if pickSlot then "Pick a weapon" else string.format("Backpack %d/%d", p.weaponCount or #weapons, p.maxWeapons or 250), if pickSlot then "It will earn cash on podium " .. pickSlot else "Display weapons on podiums to earn cash!")
	local occupied = pickSlot and p.showcase and (p.showcase[pickSlot] or "") ~= ""
	pack.takeDown.Visible = occupied == true
	local key = tostring(#weapons) .. ":" .. (weapons[1] and weapons[1].id or "") .. ":" .. (weapons[#weapons] and weapons[#weapons].id or "") .. ":" .. table.concat(p.showcase or {}, ",") .. tostring(pickSlot)
	if not force and pack.key == key then return end
	pack.key = key
	for _, c in pack.grid:GetChildren() do
		if c:IsA("GuiButton") then c:Destroy() end
	end
	pack.empty.Visible = #weapons == 0
	local carried = {}
	for _, id in p.carried or {} do carried[id] = true end
	for i, w in weapons do
		if i > 250 then break end
		local badge = if isDisplayed(p, w.id) then "SHOWN" else nil
		if carried[w.id] then badge = "STOLEN!" end
		Kit.weaponCard(pack.grid, w, i, function()
			if pickSlot then
				local ok = Kit.call("SetShowcase", pickSlot, w.id)
				if ok then
					Toast.show("On display! It earns cash every second", "good")
					Net.call("TutorialStep", 7)
					Panels.close()
				end
			else
				openDetail(w)
			end
		end, badge)
	end
end

-- Sell booth ---------------------------------------------------------------------------------

local KEEP_CHOICES = {
	{ keep = nil, text = "SELL ALL" },
	{ keep = 3, text = "KEEP RARE+" },
	{ keep = 4, text = "KEEP EPIC+" },
	{ keep = 5, text = "KEEP LEGEND+" },
}

local function sellPreview(p: any): (number, number)
	local count, total = 0, 0
	local carried = {}
	for _, id in p.carried or {} do carried[id] = true end
	for _, w in p.weapons or {} do
		if not isDisplayed(p, w.id) and not carried[w.id] and (sellKeep == nil or w.r < sellKeep) then
			count += 1
			total += w.v
		end
	end
	return count, total
end

local function buildSell()
	local window, body, footer = Panels.create("Sell", "Sell Booth", {
		width = 500,
		height = 560,
		footer = 100,
		color = Color3.fromRGB(40, 180, 80),
		subtitle = "Turn weapons into cash!",
		onOpen = function()
			M.refreshSell()
		end,
	})
	sell.window = window
	sell.summary = Theme.text({ LayoutOrder = 0, Text = "", Size = UDim2.new(1, 0, 0, 60), TextSize = 30, Parent = body })
	Panels.section(body, 1, nil, "WHAT TO KEEP?")
	local row = Theme.make("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 132), BackgroundTransparency = 1, Parent = body })
	Theme.grid(row, Vector2.new(210, 60), 10)
	sell.choices = {}
	for i, choice in KEEP_CHOICES do
		local b = Theme.button({ Text = choice.text, Color = C.teal, Size = UDim2.fromOffset(210, 60), TextSize = 24, LayoutOrder = i, OnClick = function()
			sellKeep = choice.keep
			M.refreshSell()
		end, Parent = row })
		sell.choices[i] = { button = b, keep = choice.keep }
	end
	sell.note = Theme.text({ LayoutOrder = 3, Text = "Weapons on display are never sold", Size = UDim2.new(1, 0, 0, 30), TextSize = 20, TextColor3 = C.dim, Parent = body })
	sell.breakdown = Theme.text({ LayoutOrder = 4, Text = "", Size = UDim2.new(1, 0, 0, 70), TextSize = 22, TextColor3 = C.yellow, Parent = body })
	sell.button = Theme.button({ Text = "SELL!", Color = C.green, Size = UDim2.new(1, 0, 1, -6), TextSize = 40, OnClick = function()
		local ok = Kit.call("SellAll", sellKeep)
		if ok then
			Net.call("TutorialStep", 3)
		end
	end, Parent = footer })
	Theme.pulse(sell.button, 0.04)
end

function M.refreshSell()
	local p = State.profile
	if not p or not sell.window then return end
	local count, total = sellPreview(p)
	sell.summary.Text = string.format("You carry %d weapons", p.weaponCount or #(p.weapons or {}))
	for _, choice in sell.choices do
		Theme.setColor(choice.button, if choice.keep == sellKeep then C.yellow else C.teal)
	end
	local byRarity = {}
	local carried = {}
	for _, id in p.carried or {} do carried[id] = true end
	for _, w in p.weapons or {} do
		if not isDisplayed(p, w.id) and not carried[w.id] and (sellKeep == nil or w.r < sellKeep) then
			byRarity[w.r] = (byRarity[w.r] or 0) + 1
		end
	end
	local parts = {}
	for r = 1, 6 do
		if byRarity[r] then
			table.insert(parts, string.format("%d %s", byRarity[r], Kit.RarityShort[r]))
		end
	end
	sell.breakdown.Text = if #parts > 0 then table.concat(parts, "  ·  ") else "Nothing to sell with this choice"
	Theme.setText(sell.button, if count > 0 then string.format("SELL %d FOR %s", count, Theme.money(total)) else "NOTHING TO SELL")
	Theme.setEnabled(sell.button, count > 0)
end

function M.init()
	buildBackpack()
	buildSell()
	Net.on("Sold", function(info)
		if type(info) == "table" and (info.coins or 0) > 0 then
			Toast.cashPop(info.coins)
			Sfx.play("coin")
			Toast.show(string.format("Sold %d weapons for %s!", info.count or 0, Theme.money(info.coins)), "good")
		end
	end)
end

function M.start()
	State.observe(function()
		if Panels.isOpen("Backpack") and not (pack.detail and pack.detail.Visible) then M.refreshBackpack() end
		if Panels.isOpen("Sell") then M.refreshSell() end
	end)
end

return M
