--!nonstrict
--[[
	Evolution, Shop and Settings panels.

	Evolution (docs/21 §15): big "3 -> 4", two short requirement bars, the permanent reward in
	huge text, short KEEP / RESET columns and one EVOLVE button. Protected evolution only shows
	when the player owns a charge. Weapons and displays are kept on purpose (displays keep
	earning, capped by your current tier).
	Shop: passes/products. Real purchases stay disabled; Studio shows TEST GRANT buttons.
	Settings: music, sounds, effects.
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

local M = { Priority = 10 }
local C = Theme.Colors

local evo: any = {}
local shop: any = {}
local settings: any = {}

-- Evolution ----------------------------------------------------------------------------------

local function buildEvolution()
	local window, body, footer = Panels.create("Evolution", "Evolve", {
		width = 500,
		height = 620,
		footer = 96,
		color = Color3.fromRGB(150, 80, 240),
		subtitle = "Start over stronger, forever",
		onOpen = function()
			M.refreshEvolution()
		end,
	})
	evo.window = window
	evo.rank = Theme.text({ LayoutOrder = 0, Text = "0 → 1", Size = UDim2.new(1, 0, 0, 70), TextSize = 64, TextColor3 = C.yellow, Parent = body })
	evo.reward = Theme.card({ LayoutOrder = 1, Size = UDim2.new(1, -6, 0, 76), BackgroundColor3 = Theme.shade(C.green, -0.4), Parent = body })
	evo.rewardText = Theme.text({ Text = "", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextScaled = true, Parent = evo.reward })
	evo.tierBar = Theme.bar({ LayoutOrder = 2, Size = UDim2.new(1, -6, 0, 46), FillColor = C.yellow, Parent = body })
	evo.forgeBar = Theme.bar({ LayoutOrder = 3, Size = UDim2.new(1, -6, 0, 46), FillColor = C.orange, Parent = body })
	local cols = Theme.make("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 210), BackgroundTransparency = 1, Parent = body })
	local keep = Theme.card({ Size = UDim2.new(0.5, -6, 1, 0), BackgroundColor3 = Theme.shade(C.green, -0.45), Parent = cols })
	Theme.text({ Text = "KEEP", Size = UDim2.new(1, 0, 0, 34), TextSize = 30, TextColor3 = C.green, Parent = keep })
	evo.keepList = Theme.text({ Text = "", Position = UDim2.fromOffset(8, 36), Size = UDim2.new(1, -16, 1, -40), TextSize = 21, TextYAlignment = Enum.TextYAlignment.Top, Parent = keep })
	local reset = Theme.card({ Size = UDim2.new(0.5, -6, 1, 0), Position = UDim2.new(0.5, 6, 0, 0), BackgroundColor3 = Theme.shade(C.red, -0.45), Parent = cols })
	Theme.text({ Text = "RESET", Size = UDim2.new(1, 0, 0, 34), TextSize = 30, TextColor3 = C.red, Parent = reset })
	evo.resetList = Theme.text({ Text = "", Position = UDim2.fromOffset(8, 36), Size = UDim2.new(1, -16, 1, -40), TextSize = 21, TextYAlignment = Enum.TextYAlignment.Top, Parent = reset })
	evo.protected = Theme.button({ LayoutOrder = 5, Text = "PROTECTED EVOLVE", Color = C.blue, Size = UDim2.new(1, -6, 0, 56), TextSize = 24, Visible = false, OnClick = function()
		M.evolve(true)
	end, Parent = body })
	evo.button = Theme.button({ Text = "EVOLVE!", Color = C.purple, Size = UDim2.new(1, 0, 1, -6), TextSize = 44, OnClick = function()
		M.evolve(false)
	end, Parent = footer })
end

function M.evolve(protected: boolean)
	if not evo.confirming then
		evo.confirming = true
		Theme.setText(evo.button, "TAP AGAIN TO EVOLVE")
		task.delay(3, function()
			evo.confirming = false
			M.refreshEvolution()
		end)
		if not protected then return end
	end
	evo.confirming = false
	local ok, rank = Kit.call("Evolve", protected)
	if ok then
		Panels.close()
	end
	local _ = rank
end

function M.refreshEvolution()
	local p = State.profile
	if not p or not evo.window then return end
	local status = p.evolution
	if not status then return end
	local rank = status.rank or 0
	evo.rank.Text = string.format("%d → %d", rank, rank + 1)
	local cfg = Data.config("Evolution")
	local now = cfg and cfg.cashMultiplier and cfg.cashMultiplier(rank) or (1 + 0.5 * rank)
	local nextMult = cfg and cfg.cashMultiplier and cfg.cashMultiplier(rank + 1) or (1 + 0.5 * (rank + 1))
	evo.rewardText.Text = string.format("CASH x%.1f → x%.1f FOREVER", now, nextMult)
	local need, have = status.requirements, status.progress
	local tierName = Data.mat(need.tier).name
	Theme.setBar(evo.tierBar, if have.tier >= need.tier then 1 else (have.tier - 1) / math.max(1, need.tier - 1), string.format("%s Unlock %s", if have.tier >= need.tier then "✔" else "⛏️", tierName))
	Theme.setBar(evo.forgeBar, math.min(1, have.forged / need.forged), string.format("%s Forge %d weapons (%d/%d)", if have.forged >= need.forged then "✔" else "🔨", need.forged, math.min(have.forged, need.forged), need.forged))
	local keeps = cfg and cfg.Keeps or {}
	evo.keepList.Text = "• " .. table.concat(keeps, "\n• ")
	local resets = {}
	for _, entry in (cfg and cfg.Resets or {}) do
		if entry.field ~= "selectedMaterial" and entry.field ~= "bank" and entry.field ~= "lines" and entry.field ~= "stations" then
			table.insert(resets, entry.label)
		end
	end
	evo.resetList.Text = "• " .. table.concat(resets, "\n• ")
	evo.protected.Visible = (p.evolveCharges or 0) > 0
	Theme.setText(evo.protected, string.format("PROTECTED EVOLVE (%d left)", p.evolveCharges or 0))
	Theme.setEnabled(evo.protected, status.eligible == true)
	if not evo.confirming then
		Theme.setText(evo.button, if status.eligible then "EVOLVE!" else "NOT READY YET")
	end
	Theme.setEnabled(evo.button, status.eligible == true)
end

-- Shop ---------------------------------------------------------------------------------------

local ICONS = { PremiumAutoForge = "⚙️", MultiForge = "⚒️", MultiHatch = "🥚", GoldenForgeDragon = "🐉", TitanExcavator = "⛏️", DragonFurnace = "🔥", CollectionMagnet = "🧲", VIPWorkshop = "👑", ProtectedEvolution = "🛡️", StarterPack = "🎁" }

local function buildShop()
	local window, body = Panels.create("Shop", "Shop", {
		width = 520,
		height = 640,
		color = Color3.fromRGB(255, 170, 30),
		subtitle = "Boosts are optional: everything can be earned free",
		onOpen = function()
			shop.sig = nil
			M.refreshShop()
		end,
	})
	shop.window = window
	shop.notice = Theme.text({ LayoutOrder = 0, Text = "", Size = UDim2.new(1, 0, 0, 54), TextSize = 21, TextColor3 = C.ink, BackgroundColor3 = C.yellow, BackgroundTransparency = 0, Corner = 12, Stroke = { Color = C.ink, Thickness = 3 }, TextStroke = false, Parent = body })
	shop.list = Theme.make("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = body })
	Theme.list(shop.list, 10, nil, Enum.HorizontalAlignment.Center)
end

function M.refreshShop()
	local p = State.profile
	if not p or not shop.window then return end
	local products = Data.products()
	local live = p.productsLive == true
	local allowed = p.paidRandomAllowed == true
	local parts = { tostring(live), tostring(allowed), tostring(p.isStudio), #products }
	for _, entry in products do
		table.insert(parts, entry.key .. (if p.entitlements and p.entitlements[entry.key] then "1" else "0"))
	end
	local sig = table.concat(parts, ",")
	if sig == shop.sig then return end
	shop.sig = sig
	shop.notice.Text = if live then "" elseif p.isStudio then "Studio test shop: TEST GRANT is free, no Robux." else "The shop is closed for now."
	for _, c in shop.list:GetChildren() do
		if c:IsA("Frame") then c:Destroy() end
	end
	for i, entry in products do
		local def = entry.def
		local owned = p.entitlements and p.entitlements[entry.key] == true
		local blocked = def.paidRandom == true and not allowed
		local card = Theme.card({ LayoutOrder = i, Size = UDim2.new(1, -6, 0, 132), BackgroundColor3 = if owned then Theme.shade(C.green, -0.45) else C.panelDark, Parent = shop.list })
		Theme.text({ Text = ICONS[entry.key] or "⭐", Size = UDim2.fromOffset(70, 70), Position = UDim2.fromOffset(8, 10), TextSize = 50, TextStroke = false, Parent = card })
		Theme.text({ Text = def.name or entry.key, Position = UDim2.fromOffset(86, 6), Size = UDim2.new(1, -96, 0, 32), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, Parent = card })
		Theme.text({ Text = def.description or "", Position = UDim2.fromOffset(86, 38), Size = UDim2.new(1, -96, 0, 44), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 17, TextColor3 = C.dim, Parent = card })
		local action
		if blocked then
			action = Theme.text({ Text = "Not available for your account", Position = UDim2.new(0, 86, 1, -42), Size = UDim2.new(1, -96, 0, 34), TextSize = 18, TextColor3 = C.red, Parent = card })
		elseif owned and def.kind == "pass" then
			action = Theme.chip("OWNED ✔", C.green, { Position = UDim2.new(1, -10, 1, -10), AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(140, 40), TextSize = 22, Parent = card })
		elseif live then
			action = Theme.button({ Text = "R$ " .. tostring(def.illustrativeRobux or "?"), Color = C.green, Size = UDim2.fromOffset(160, 48), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -8), TextSize = 24, OnClick = function()
				Kit.call("Purchase", entry.key)
			end, Parent = card })
		elseif p.isStudio then
			action = Theme.button({ Text = "TEST GRANT", Color = C.blue, Size = UDim2.fromOffset(170, 48), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -8), TextSize = 22, OnClick = function()
				local ok = Kit.call("DevGrant", entry.key)
				if ok then
					Toast.show("Granted " .. (def.name or entry.key) .. " (test only)", "good")
				end
			end, Parent = card })
		else
			action = Theme.chip("SOON", C.grey, { Position = UDim2.new(1, -10, 1, -10), AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(120, 40), TextSize = 22, Parent = card })
		end
		local _ = action
	end
end

-- Settings -----------------------------------------------------------------------------------

local function buildSettings()
	local window, body = Panels.create("Settings", "Settings", {
		width = 460,
		height = 460,
		color = Color3.fromRGB(90, 100, 140),
		onOpen = function()
			M.refreshSettings()
		end,
	})
	settings.window = window
	settings.toggles = {}
	for i, item in { { "music", "🎵 Music" }, { "sfx", "🔊 Sounds" }, { "vfx", "✨ Effects" } } do
		local row = Theme.card({ LayoutOrder = i, Size = UDim2.new(1, -6, 0, 76), Parent = body })
		Theme.text({ Text = item[2], Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -180, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 30, Parent = row })
		local b = Theme.button({ Text = "ON", Color = C.green, Size = UDim2.fromOffset(130, 58), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), TextSize = 28, OnClick = function()
			local p = State.profile
			local on = not (p and p.settings and p.settings[item[1]] == false)
			Kit.call("SetSetting", item[1], not on)
		end, Parent = row })
		settings.toggles[item[1]] = b
	end
	settings.save = Theme.text({ LayoutOrder = 10, Text = "", Size = UDim2.new(1, 0, 0, 50), TextSize = 19, TextColor3 = C.dim, Parent = body })
end

function M.refreshSettings()
	local p = State.profile
	if not p or not settings.window then return end
	for key, b in settings.toggles do
		local on = not (p.settings and p.settings[key] == false)
		Theme.setText(b, if on then "ON" else "OFF")
		Theme.setColor(b, if on then C.green else C.red)
	end
	local status = p.saveStatus or {}
	settings.save.Text = string.format("Save: %s (%s)", tostring(status.mode or "?"), tostring(status.saveState or "?"))
end

function M.init()
	buildEvolution()
	buildShop()
	buildSettings()
	Net.on("Evolved", function(info)
		local rank = type(info) == "table" and info.rank or 1
		local cfg = Data.config("Evolution")
		local mult = cfg and cfg.cashMultiplier and cfg.cashMultiplier(rank) or 1
		Reveal.message("EVOLVED!", "Evolution " .. tostring(rank), C.purple, "🌟", string.format("All weapons now x%.1f cash!", mult))
	end)
end

function M.start()
	State.observe(function()
		if Panels.isOpen("Evolution") then M.refreshEvolution() end
		if Panels.isOpen("Shop") then M.refreshShop() end
		if Panels.isOpen("Settings") then M.refreshSettings() end
	end)
end

return M
