--!nonstrict
--[[
	HUD v2 (docs/21 §1-2): only what a player needs at a glance.

	* Top center: one big cash pill with the amount centered and a dollar sign, plus a small
	  "+$/s" chip for display income underneath.
	* Right side: four chunky buttons (BACKPACK with count, PETS, SHOP, settings gear).
	* Big center-top banners for "RUN HOME!" while carrying a stolen weapon and for your own
	  forge lock timer.
	There are no persistent Materials/Workshop/Forge buttons: stations are used in the world.
]]
local Players = game:GetService("Players")
local State = require(script.Parent.Parent.State)
local Net = require(script.Parent.Parent.Net)
local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Panels = require(UI.Panels)
local Toast = require(UI.Toast)

local M = { Priority = 50 }
local C = Theme.Colors

local ui: any = {}
local shownCoins = 0
local targetCoins = 0

local function sideButton(parent: Instance, order: number, icon: string, text: string, color: Color3, onClick: () -> ()): TextButton
	local b = Theme.button({ Text = "", Color = color, Size = UDim2.fromOffset(92, 92), LayoutOrder = order, Corner = 20, OnClick = onClick, Parent = parent })
	Theme.text({ Text = icon, Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 4), TextSize = 44, TextStroke = false, ZIndex = b.ZIndex + 2, Parent = b })
	Theme.text({ Text = text, Size = UDim2.new(1, -4, 0, 26), Position = UDim2.new(0, 2, 1, -34), TextScaled = true, ZIndex = b.ZIndex + 2, Parent = b })
	return b
end

local function build()
	local layer = Panels.layer("Hud")
	-- Cash pill.
	local top = Theme.make("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(320, 110),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	Theme.autoScale(top)
	local pill = Theme.make("Frame", {
		Name = "Cash",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(300, 66),
		BackgroundColor3 = C.green,
		Corner = 33,
		Stroke = { Color = C.ink, Thickness = 4 },
		Gradient = { Theme.shade(C.green, 0.3), Theme.shade(C.green, -0.2) },
		Parent = top,
	})
	ui.cash = Theme.text({ Name = "Amount", Text = "$0", Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), TextSize = 46, TextXAlignment = Enum.TextXAlignment.Center, Parent = pill })
	ui.pill = pill
	ui.pillScale = Instance.new("UIScale")
	ui.pillScale.Parent = pill
	ui.income = Theme.chip("+$0/s", Theme.shade(C.panel, -0.1), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 72), Size = UDim2.fromOffset(170, 30), TextSize = 19, Parent = top })

	-- Right column.
	local side = Theme.make("Frame", {
		Name = "Side",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.45, 0),
		Size = UDim2.fromOffset(100, 420),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	Theme.autoScale(side, 0.9)
	local list = Theme.list(side, 10)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	ui.backpack = sideButton(side, 1, "🎒", "BAG", C.orange, function() Panels.toggle("Backpack") end)
	ui.bagCount = Theme.chip("0", C.red, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 4, 0, 6), Size = UDim2.fromOffset(46, 28), TextSize = 18, ZIndex = 6, Parent = ui.backpack })
	sideButton(side, 2, "🐾", "PETS", C.pink, function() Panels.toggle("Pets") end)
	sideButton(side, 3, "🛒", "SHOP", C.yellow, function() Panels.toggle("Shop") end)
	sideButton(side, 4, "⚙️", "SET", C.grey, function() Panels.toggle("Settings") end)

	-- Center banner (carrying / locked).
	local banner = Theme.make("Frame", {
		Name = "Alert",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 182),
		Size = UDim2.fromOffset(440, 60),
		BackgroundColor3 = C.red,
		Corner = 18,
		Stroke = { Color = C.ink, Thickness = 4 },
		Visible = false,
		Parent = top,
	})
	ui.alert = banner
	ui.alertText = Theme.text({ Text = "", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextScaled = true, Parent = banner })
end

local function myLock(): (number, number)
	local plotIndex = Players.LocalPlayer:GetAttribute("PlotIndex")
	local world = workspace:FindFirstChild("World")
	local plot = world and world:FindFirstChild("Plots") and world.Plots:FindFirstChild("Plot" .. tostring(plotIndex))
	if not plot then return 0, 0 end
	return plot:GetAttribute("LockedUntil") or 0, plot:GetAttribute("NextLockAt") or 0
end

local lastCoins = nil
local function onProfile(p)
	targetCoins = p.coins or 0
	if lastCoins and targetCoins > lastCoins then
		ui.pillScale.Scale = 1.12
		Theme.tween(ui.pillScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	lastCoins = targetCoins
	local income = p.incomePerSec or 0
	ui.income.Text = string.format("+%s/s  ·  bank %s", Theme.money(income), Theme.money(p.bank or 0))
	ui.income.Visible = income > 0 or (p.bank or 0) > 0
	local count = p.weaponCount or 0
	ui.bagCount.Text = Theme.abbr(count)
	ui.bagCount.Visible = count > 0
	ui.bagCount.BackgroundColor3 = if count >= (p.maxWeapons or 250) then C.red else C.blue
end

function M.init()
	build()
end

function M.start()
	State.observe(onProfile)
	task.spawn(function()
		while true do
			task.wait(1 / 30)
			-- Count up smoothly toward the real cash (big numbers feel great when they roll).
			if shownCoins ~= targetCoins then
				local diff = targetCoins - shownCoins
				if math.abs(diff) < math.max(1, targetCoins * 0.0005) then
					shownCoins = targetCoins
				else
					shownCoins += diff * 0.2
				end
				ui.cash.Text = Theme.money(shownCoins)
			end
			-- Alerts.
			local p = State.profile
			local now = workspace:GetServerTimeNow()
			local carrying = p and p.carrying
			if carrying then
				ui.alert.Visible = true
				ui.alert.BackgroundColor3 = C.red
				ui.alertText.Text = string.format("RUN HOME WITH THE LOOT! %ds", math.max(0, math.ceil(carrying.deadline - now)))
			else
				local lockedUntil = myLock()
				if lockedUntil > now then
					ui.alert.Visible = true
					ui.alert.BackgroundColor3 = Theme.shade(C.red, -0.2)
					ui.alertText.Text = string.format("🔒 FORGE LOCKED  %ds", math.ceil(lockedUntil - now))
				else
					ui.alert.Visible = false
				end
			end
		end
	end)
	Net.on("Steal", function(info)
		if type(info) ~= "table" then return end
		local me = Players.LocalPlayer.UserId
		if info.victim == me and info.outcome == "Started" then
			Toast.show("A THIEF grabbed your weapon! Tag them!", "bad")
		end
	end)
end

return M
