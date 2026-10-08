--!nonstrict
--[[
	Forge station panel (docs/21 §3): opened by walking up to a forge in your workshop.

	One simple vertical flow:
	  1 MATERIAL   (unlocked metals with ingot counts)
	  2 WEAPON     (dagger -> greatsword, ingot cost by size, value range)
	  ODDS         (shown automatically for the chosen mode)
	  3 AUTO FORGE (off / free 1.5x / premium 4x)
	  4 AUTO SELL  (only while an auto mode is chosen)
	  BEGIN        (big button; nothing starts until it is pressed)
	Changing material, weapon or auto-sell immediately reconfigures the forge on the server,
	which stops any running auto loop cleanly (never "forge busy"). A running auto forge shows a
	labeled countdown and a big STOP button. A second tab holds the forge's machine upgrades.
]]
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Panels = require(UI.Panels)
local Data = require(UI.Data)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local Reveal = require(UI.Reveal)
local ForgeGame = require(UI.ForgeGame)
local ForgeSignals = require(UI.ForgeSignals)

local M = { Priority = 10 }
local C = Theme.Colors

local station = 1
local modeChoice: { [number]: string } = {} -- per station: "off" | "free" | "premium"
local phaseInfo: { [number]: any } = {}
local ui: any = {}
local refreshers: { (any) -> () } = {}
local tab = "forge"

local KEEP_OPTIONS = {
	{ keep = 7, text = "SELL ALL" },
	{ keep = 3, text = "KEEP RARE+" },
	{ keep = 4, text = "KEEP EPIC+" },
	{ keep = 5, text = "KEEP LEGEND+" },
}

local function profile()
	return State.profile
end

local function recipeOf(p: any)
	return p and p.stations and p.stations[station] or { m = 1, c = 4, keep = 4 }
end

local function configure(m: number?, c: number?, keep: number?)
	local p = profile()
	if not p then return end
	local r = recipeOf(p)
	local ok, res = Kit.call("ForgeConfigure", station, m or r.m, c or r.c, keep or r.keep)
	if ok and res and res.stoppedAuto then
		Toast.show("Auto Forge stopped. Press BEGIN to restart", "info")
	end
end

local function luckFor(mode: string): number
	if mode == "free" then return 1.5 end
	if mode == "premium" then return 4 end
	return 2.5
end

-- Builders --------------------------------------------------------------------------------

local function materialTile(parent: Instance, m: number, order: number)
	local mat = Data.mat(m)
	local b = Instance.new("TextButton")
	b.Name = "Mat" .. m
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(112, 118)
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = Theme.shade(mat.color, -0.5)
	b.BorderSizePixel = 0
	Theme.make("UICorner", { CornerRadius = UDim.new(0, 16), Parent = b })
	local stroke = Theme.make("UIStroke", { Name = "Sel", Color = C.ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	Kit.ingotIcon(b, m, 60, { Position = UDim2.new(0.5, 0, 0, 12), AnchorPoint = Vector2.new(0.5, 0) })
	Theme.text({ Text = mat.name, Position = UDim2.fromOffset(4, 52), Size = UDim2.new(1, -8, 0, 28), TextScaled = true, Parent = b })
	local count = Theme.text({ Name = "Count", Text = "x0", Position = UDim2.fromOffset(4, 82), Size = UDim2.new(1, -8, 0, 28), TextSize = 24, TextColor3 = C.yellow, Parent = b })
	local check = Theme.text({ Name = "Check", Text = "✔", Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -2, 0, 2), AnchorPoint = Vector2.new(1, 0), TextSize = 26, TextColor3 = C.green, Visible = false, Parent = b })
	b.Parent = parent
	b.Activated:Connect(function()
		configure(m, nil, nil)
		Theme.pop(b, 0.9)
	end)
	return function(p)
		local selected = recipeOf(p).m == m
		local n = p.ingots and p.ingots[m] or 0
		count.Text = "x" .. Theme.abbr(n)
		count.TextColor3 = if n >= Kit.recipe(recipeOf(p).c) then C.yellow else C.red
		stroke.Color = if selected then C.yellow else C.ink
		stroke.Thickness = if selected then 6 else 3
		check.Visible = selected
	end
end

local function weaponTile(parent: Instance, c: number, order: number)
	local b = Instance.new("TextButton")
	b.Name = "Class" .. c
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(84, 150)
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = C.panelDark
	b.BorderSizePixel = 0
	Theme.make("UICorner", { CornerRadius = UDim.new(0, 16), Parent = b })
	local stroke = Theme.make("UIStroke", { Color = C.ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	Theme.text({ Text = Kit.ClassIcons[c], Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 4), TextSize = 42, TextStroke = false, Parent = b })
	Theme.text({ Text = Data.ClassNames[c], Size = UDim2.new(1, -4, 0, 24), Position = UDim2.fromOffset(2, 56), TextScaled = true, Parent = b })
	Theme.text({ Text = Kit.recipe(c) .. " ingot" .. (if Kit.recipe(c) > 1 then "s" else ""), Size = UDim2.new(1, -4, 0, 22), Position = UDim2.fromOffset(2, 82), TextSize = 19, TextColor3 = C.yellow, Parent = b })
	local value = Theme.text({ Text = "", Size = UDim2.new(1, -4, 0, 40), Position = UDim2.fromOffset(2, 104), TextSize = 17, TextColor3 = C.cash, Parent = b })
	b.Parent = parent
	b.Activated:Connect(function()
		configure(nil, c, nil)
		Theme.pop(b, 0.9)
	end)
	return function(p)
		local r = recipeOf(p)
		local selected = r.c == c
		stroke.Color = if selected then C.yellow else C.ink
		stroke.Thickness = if selected then 6 else 3
		b.BackgroundColor3 = if selected then Theme.shade(C.panel, 0.2) else C.panelDark
		local lo, hi = Kit.valueRange(r.m, c)
		value.Text = Theme.money(lo) .. "\nto " .. Theme.money(hi)
	end
end

local function build()
	local window, body, footer = Panels.create("Forge", "Forge 1", {
		width = 520,
		height = 660,
		footer = 96,
		color = Color3.fromRGB(240, 110, 40),
		subtitle = "Make weapons here!",
		onOpen = function(arg)
			station = if type(arg) == "number" then arg else 1
			tab = "forge"
			M.refresh()
		end,
	})
	ui.window = window
	-- Tabs.
	local tabs = Theme.make("Frame", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1, Parent = body })
	Theme.list(tabs, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	ui.tabForge = Theme.button({ Text = "FORGE", Color = C.yellow, Size = UDim2.fromOffset(200, 50), TextSize = 26, LayoutOrder = 1, OnClick = function() tab = "forge"; M.refresh() end, Parent = tabs })
	ui.tabUp = Theme.button({ Text = "UPGRADE", Color = C.blue, Size = UDim2.fromOffset(200, 50), TextSize = 26, LayoutOrder = 2, OnClick = function() tab = "upgrade"; M.refresh() end, Parent = tabs })

	-- FORGE tab.
	local forge = Theme.make("Frame", { Name = "ForgeTab", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = body })
	Theme.list(forge, 10, nil, Enum.HorizontalAlignment.Center)
	ui.forgeTab = forge
	Panels.section(forge, 1, "1", "CHOOSE MATERIAL")
	local mats = Theme.scroll({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 132), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 6, Parent = forge })
	Theme.list(mats, 8, Enum.FillDirection.Horizontal)
	ui.mats = mats
	ui.matRefresh = {}
	Panels.section(forge, 3, "2", "CHOOSE WEAPON")
	local classes = Theme.make("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 152), BackgroundTransparency = 1, Parent = forge })
	Theme.list(classes, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	for i, c in Kit.ClassOrder do
		table.insert(refreshers, weaponTile(classes, c, i))
	end
	-- Odds strip.
	local odds = Theme.card({ LayoutOrder = 5, Size = UDim2.new(1, -6, 0, 92), BackgroundColor3 = C.panelEdge, Parent = forge })
	ui.oddsTitle = Theme.text({ Text = "ODDS", Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 4), TextSize = 22, Parent = odds })
	local oddsRow = Theme.make("Frame", { Size = UDim2.new(1, -12, 0, 52), Position = UDim2.fromOffset(6, 34), BackgroundTransparency = 1, Parent = odds })
	Theme.list(oddsRow, 4, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	ui.odds = {}
	for r = 1, 6 do
		local cell = Theme.make("Frame", { LayoutOrder = r, Size = UDim2.fromOffset(76, 52), BackgroundColor3 = Theme.shade(Theme.rarityColor(r), -0.35), Corner = 10, Stroke = { Color = Theme.rarityColor(r), Thickness = 2 }, Parent = oddsRow })
		Theme.text({ Text = Kit.RarityShort[r], Size = UDim2.new(1, 0, 0, 22), TextSize = 16, TextColor3 = Theme.rarityColor(r), Parent = cell })
		ui.odds[r] = Theme.text({ Text = "", Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 28), TextSize = 20, Parent = cell })
	end
	-- Auto forge.
	Panels.section(forge, 6, "3", "AUTO FORGE")
	local autoRow = Theme.make("Frame", { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 68), BackgroundTransparency = 1, Parent = forge })
	Theme.list(autoRow, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	ui.modeOff = Theme.button({ Text = "OFF", Color = C.blue, Size = UDim2.fromOffset(130, 62), TextSize = 26, LayoutOrder = 1, OnClick = function() modeChoice[station] = "off"; M.refresh() end, Parent = autoRow })
	ui.modeFree = Theme.button({ Text = "AUTO 1.5x", Color = C.green, Size = UDim2.fromOffset(160, 62), TextSize = 24, LayoutOrder = 2, OnClick = function() modeChoice[station] = "free"; M.refresh() end, Parent = autoRow })
	ui.modePremium = Theme.button({ Text = "PREMIUM 4x", Color = C.purple, Size = UDim2.fromOffset(170, 62), TextSize = 22, LayoutOrder = 3, OnClick = function()
		local p = profile()
		if p and p.entitlements and p.entitlements.PremiumAutoForge then
			modeChoice[station] = "premium"
			M.refresh()
		else
			Toast.show("Premium Auto Forge is in the SHOP", "info")
		end
	end, Parent = autoRow })
	ui.autoLock = Theme.text({ LayoutOrder = 8, Text = "", Size = UDim2.new(1, 0, 0, 26), TextSize = 20, TextColor3 = C.yellow, Parent = forge })
	-- Auto sell.
	ui.sellSection = Panels.section(forge, 9, "4", "AUTO SELL")
	local sellRow = Theme.make("Frame", { LayoutOrder = 10, Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1, Parent = forge })
	Theme.list(sellRow, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	ui.sellRow = sellRow
	ui.keepButtons = {}
	for i, opt in KEEP_OPTIONS do
		ui.keepButtons[opt.keep] = Theme.button({ Text = opt.text, Color = C.teal, Size = UDim2.fromOffset(114, 54), TextSize = 17, LayoutOrder = i, OnClick = function()
			configure(nil, nil, opt.keep)
		end, Parent = sellRow })
	end
	ui.sellHint = Theme.text({ LayoutOrder = 11, Text = "", Size = UDim2.new(1, 0, 0, 24), TextSize = 19, TextColor3 = C.dim, Parent = forge })

	-- UPGRADE tab.
	local up = Theme.make("Frame", { Name = "UpgradeTab", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false, Parent = body })
	Theme.list(up, 10, nil, Enum.HorizontalAlignment.Center)
	ui.upTab = up
	Theme.text({ LayoutOrder = 0, Text = "Faster forges = more weapons!", Size = UDim2.new(1, 0, 0, 30), TextSize = 24, TextColor3 = C.yellow, Parent = up })
	table.insert(refreshers, Kit.upgradeRow(up, 1, "FurnaceHeat", "🔥", C.orange, function(level)
		local p = profile()
		local hammer = p and p.gear and p.gear.Hammer or 0
		return string.format("%.1fs heat", math.max(0.3, 2 - 0.1 * level - 0.05 * hammer))
	end))
	table.insert(refreshers, Kit.upgradeRow(up, 2, "AnvilFinish", "💧", C.blue, function(level)
		local p = profile()
		local hammer = p and p.gear and p.gear.Hammer or 0
		return string.format("%.1fs cooling", math.max(0.3, 1.5 - 0.1 * level - 0.05 * hammer))
	end))

	-- Footer: BEGIN, or the running status + STOP.
	ui.status = Theme.text({ Text = "", Size = UDim2.new(1, -200, 1, 0), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, Visible = false, Parent = footer })
	ui.begin = Theme.button({ Text = "BEGIN!", Color = C.green, Size = UDim2.new(1, 0, 1, -6), TextSize = 44, OnClick = function()
		M.begin()
	end, Parent = footer })
	ui.stop = Theme.button({ Text = "STOP", Color = C.red, Size = UDim2.new(0, 180, 1, -6), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), TextSize = 36, Visible = false, OnClick = function()
		Kit.call("ForgeStop", station)
		modeChoice[station] = "off"
	end, Parent = footer })
	ui.stopPulse = nil
end

local function statusText(st: any): string
	if not st then return "" end
	local info = phaseInfo[station] or st
	local remain = math.max(0, (info.endsAt or 0) - workspace:GetServerTimeNow())
	if st.waiting or info.phase == "waiting" then
		return "⏳ Waiting for ingots..."
	elseif info.phase == "heat" then
		return string.format("🔥 Heating  %.1fs", remain)
	elseif info.phase == "strike" then
		return string.format("🔨 Hammering  %.1fs", remain)
	elseif info.phase == "quench" then
		return string.format("💧 Cooling  %.1fs", remain)
	end
	return "AUTO ON"
end

function M.refresh()
	local p = profile()
	if not p or not ui.window then return end
	local stations = p.stations or {}
	if not stations[station] then station = 1 end
	Panels.setTitle(ui.window, "Forge " .. station, "Make weapons here!")
	ui.forgeTab.Visible = tab == "forge"
	ui.upTab.Visible = tab == "upgrade"
	Theme.setColor(ui.tabForge, if tab == "forge" then C.yellow else C.grey)
	Theme.setColor(ui.tabUp, if tab == "upgrade" then C.blue else C.grey)
	-- Material tiles: rebuild when the unlocked count changes.
	local unlocked = p.unlockedTier or 1
	if ui.matsFor ~= unlocked then
		ui.matsFor = unlocked
		for _, c in ui.mats:GetChildren() do
			if c:IsA("GuiButton") then c:Destroy() end
		end
		ui.matRefresh = {}
		for m = unlocked, 1, -1 do
			table.insert(ui.matRefresh, materialTile(ui.mats, m, unlocked - m))
		end
	end
	for _, fn in ui.matRefresh do fn(p) end
	for _, fn in refreshers do fn(p) end
	-- Mode.
	local st = p.forgeStatus and p.forgeStatus[station]
	local running = st ~= nil and st.auto
	local mode = modeChoice[station] or (if running then st.mode else "off")
	modeChoice[station] = mode
	local autoOk = p.autoUnlocked == true
	Theme.setColor(ui.modeOff, if mode == "off" then C.blue else C.grey)
	Theme.setColor(ui.modeFree, if mode == "free" then C.green else C.grey)
	Theme.setColor(ui.modePremium, if mode == "premium" then C.purple else C.grey)
	Theme.setEnabled(ui.modeFree, autoOk)
	Theme.setEnabled(ui.modePremium, autoOk)
	local owned = p.entitlements and p.entitlements.PremiumAutoForge
	Theme.setText(ui.modePremium, if owned then "PREMIUM 4x" else "🔒 4x")
	ui.autoLock.Text = if autoOk then "" else string.format("Forge %d weapons by hand to unlock Auto!", math.max(0, 3 - (p.weaponsForged or 0)))
	ui.autoLock.Visible = not autoOk
	-- Auto sell only when an auto mode is chosen.
	local showSell = mode ~= "off"
	ui.sellSection.Visible = showSell
	ui.sellRow.Visible = showSell
	ui.sellHint.Visible = showSell
	local keep = recipeOf(p).keep
	for k, b in ui.keepButtons do
		Theme.setColor(b, if k == keep then C.yellow else C.teal)
	end
	ui.sellHint.Text = if keep >= 7 then "Every weapon is sold for cash right away" else "Lower rarities are sold, the rest go in your backpack"
	-- Odds for the chosen mode.
	local luck = luckFor(mode)
	local chances = Data.rarityChances(luck)
	for r = 1, 6 do
		ui.odds[r].Text = string.format("%s", require(UI.Format).pct(chances[r]))
	end
	ui.oddsTitle.Text = if mode == "off" then "ODDS (tap fast: up to 5x luck!)" else string.format("ODDS at %.1fx luck", luck)
	-- Footer.
	ui.begin.Visible = not running
	ui.stop.Visible = running
	ui.status.Visible = running
	if running then
		ui.status.Text = statusText(st)
	end
	local r = recipeOf(p)
	local enough = (p.ingots and p.ingots[r.m] or 0) >= Kit.recipe(r.c)
	Theme.setText(ui.begin, if mode == "off" then "BEGIN!" else "START AUTO!")
	Theme.setEnabled(ui.begin, enough or mode ~= "off")
end

function M.begin()
	local p = profile()
	if not p then return end
	local mode = modeChoice[station] or "off"
	local r = recipeOf(p)
	if mode == "off" then
		local ok, res = Kit.call("ForgeBegin", station, "manual")
		if ok and res and res.sessionId then
			Panels.close(true)
			res.recipe = string.format("%s %s", Data.mat(r.m).name, Data.ClassNames[r.c])
			ForgeGame.start(res)
		end
	else
		local ok = Kit.call("ForgeBegin", station, mode)
		if ok then
			Panels.close(true)
			Toast.show("AUTO FORGE ON! Forge " .. station .. " is working", "good")
			Net.call("TutorialStep", 5)
		end
	end
end

-- Results ---------------------------------------------------------------------------------

local function freeSlot(p: any): number?
	for slot = 1, p.showcaseSlots or 2 do
		if (p.showcase and p.showcase[slot] or "") == "" then
			return slot
		end
	end
	return nil
end

local function onResult(payload: any)
	local results = payload.results or {}
	local first = results[1]
	if not first then return end
	if not payload.auto then
		-- Manual result: the minigame hands it to the reveal.
		if ForgeGame.isActive() and ForgeGame.station() == payload.station then
			ForgeGame.deliver(payload)
		else
			ForgeSignals.Result:Fire(payload)
		end
		return
	end
	for _, result in results do
		local w = result.weapon
		local name = Data.weaponName(w)
		if result.sold then
			Toast.ticker(string.format("+%s  %s", Theme.money(result.coins), Data.mat(w.m).name .. " " .. Data.ClassNames[w.c]), Theme.shade(C.green, -0.35))
		else
			Toast.ticker("KEPT " .. Kit.RarityShort[w.r] .. " " .. name, Theme.shade(Theme.rarityColor(w.r), -0.3))
			if w.r >= 5 then
				Reveal.weapon(w, {})
			end
		end
	end
end

function M.init()
	build()
	ForgeGame.init()
	ForgeGame.onReveal = function(payload)
		local results = payload.results or {}
		local first = results[1]
		if not first then return end
		ForgeSignals.Result:Fire(payload)
		local w = first.weapon
		local extras = {}
		for i = 2, #results do
			table.insert(extras, results[i].weapon)
		end
		local p = profile()
		local slot = p and freeSlot(p)
		Reveal.weapon(w, {
			extras = extras,
			onDisplay = if slot then function()
				Kit.call("SetShowcase", slot, w.id)
				Toast.show("On display! It earns cash every second", "good")
			end else nil,
		})
		Net.call("TutorialStep", 1)
	end
	Net.on("ForgeResult", onResult)
	Net.on("ForgePhase", function(info)
		if type(info) == "table" and info.station then
			phaseInfo[info.station] = info
			if info.phase == "cancelled" and ForgeGame.isActive() and ForgeGame.station() == info.station and info.reason ~= "Replaced" then
				ForgeGame.cancel()
			end
		end
	end)
end

function M.start()
	State.observe(function()
		if Panels.isOpen("Forge") then
			M.refresh()
		end
	end)
	-- Live countdown while the panel is open.
	task.spawn(function()
		while true do
			task.wait(0.1)
			if Panels.isOpen("Forge") and ui.status and ui.status.Visible then
				local p = profile()
				ui.status.Text = statusText(p and p.forgeStatus and p.forgeStatus[station])
			end
		end
	end)
end

return M
