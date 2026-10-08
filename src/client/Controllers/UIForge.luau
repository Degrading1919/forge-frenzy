--!nonstrict
-- Forge panel (class / material / mode picker) and orchestration of minigame + reveal + auto tickers.
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local Format = require(script.Parent.Parent.UI.Format)
local Data = require(script.Parent.Parent.UI.Data)
local Panels = require(script.Parent.Parent.UI.Panels)
local Toast = require(script.Parent.Parent.UI.Toast)
local ForgeSignals = require(script.Parent.Parent.UI.ForgeSignals)
local ForgeGame = require(script.Parent.Parent.UI.ForgeGame)
local ForgeReveal = require(script.Parent.Parent.UI.ForgeReveal)

local M = { Priority = 40 }
local C = Theme.Colors

local selClass, selMat, selMode = 1, nil, "manual"
local classTiles, modeButtons, matRows = {}, {}, {}
local startBtn, summary, window
local starting = false
local shadowJournal = {}
local firstProfile = true
local lastPicks = nil

local MODES = {
	{ "manual", "Manual", "Hammer for up to 5x luck" },
	{ "free", "Auto", "Free  -  1.5x luck" },
	{ "premium", "Premium Auto", "4x luck" },
}

local function profile()
	return State.profile
end

local function modeUnlocked(p, mode: string): boolean
	if mode ~= "premium" then return true end
	return p and p.entitlements and p.entitlements.PremiumAutoForge == true
end

local function refresh()
	local p = profile()
	if not p or not window or not window.Visible then return end
	selMat = selMat or p.selectedMaterial or 1
	local tier = p.unlockedTier or 1
	for i, row in matRows do
		local show = i <= tier
		row.frame.Visible = show
		if show then
			local ing = (p.ingots and p.ingots[i]) or 0
			local sel = i == selMat
			row.count.Text = "x" .. Format.abbr(ing)
			row.count.TextColor3 = ing > 0 and C.text or C.bad
			row.frame.BackgroundColor3 = sel and C.panel2 or C.panel
			row.stroke.Color = sel and C.orange or C.brass
			row.stroke.Thickness = sel and 3 or 1
			row.frame.BackgroundTransparency = ing > 0 and 0 or 0.4
		end
	end
	for i, tile in classTiles do
		local sel = i == selClass
		tile.stroke.Color = sel and C.orange or C.brass
		tile.stroke.Thickness = sel and 4 or 1
		tile.frame.BackgroundColor3 = sel and C.panel2 or C.panel
	end
	for _, mb in modeButtons do
		local sel = mb.mode == selMode
		local unlocked = modeUnlocked(p, mb.mode)
		Theme.setColor(mb.btn, sel and C.orange or C.panel2)
		mb.btn.Text = mb.title .. (unlocked and "" or "  🔒") .. "\n" .. mb.sub
	end
	local ing = (p.ingots and p.ingots[selMat]) or 0
	local mat = Data.mat(selMat)
	summary.Text = string.format("%s %s  -  %s ingots  -  %s", mat.name, Data.ClassNames[selClass], Format.abbr(ing), selMode == "manual" and "Manual" or (selMode == "free" and "Auto 1.5x" or "Premium 4x"))
	Theme.setEnabled(startBtn, ing > 0 and not starting)
end

local function startForge(picks)
	if starting then return end
	local p = profile()
	if not p then return end
	local cls, mat, mode = picks.cls, picks.mat, picks.mode
	if ((p.ingots and p.ingots[mat]) or 0) < 1 then
		Toast.show("No ingots of " .. Data.mat(mat).name .. " - let the smelter work!", "bad")
		return
	end
	if not modeUnlocked(p, mode) then
		Toast.show("Premium Auto Forge is locked", "info")
		Panels.open("Shop")
		return
	end
	starting = true
	local ok, res = Net.call("ForgeStart", cls, mat, mode)
	starting = false
	if not ok then
		Toast.show(res, "bad")
		refresh()
		return
	end
	lastPicks = picks
	res = type(res) == "table" and res or {}
	local info = {
		sessionId = res.sessionId, heatSec = res.heatSec or 2, windowSec = res.windowSec or 6, revealSec = res.revealSec or 1.5,
		mode = mode, classIndex = cls, materialIndex = mat,
	}
	ForgeSignals.Started:Fire(info)
	if mode == "manual" then
		ForgeGame.start(info)
	else
		Panels.close()
		Toast.show(mode == "premium" and "Premium auto forge started (4x luck)" or "Auto forge started (1.5x luck)", "good")
	end
end

local function isNewDiscovery(w): boolean
	return not Data.hasBit(shadowJournal[w.m], w.r)
end

local function showReveal(payload)
	local w = payload.weapon
	if not w then return end
	ForgeReveal.show(payload, {
		isNew = isNewDiscovery(w),
		again = function()
			if lastPicks then startForge(lastPicks) end
		end,
	})
end

local function buildPanel()
	local content
	window, content = Panels.create("Forge", "Forge", { onOpen = function() refresh() end, maxSize = Vector2.new(940, 640) })

	-- Left column: weapon + mode
	local left = Theme.scroll({
		Size = UDim2.new(0.44, -6, 1, 0),
		Parent = content,
	})
	Theme.list(left, 6)
	Theme.label({ Text = "WEAPON", Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.brass, TextSize = 14, LayoutOrder = 1, Parent = left })
	local grid = Theme.make("Frame", { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2, Parent = left })
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.3, 0, 0, 62)
	gl.CellPadding = UDim2.new(0.04, 0, 0, 6)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	for i, name in Data.ClassNames do
		local f = Theme.make("TextButton", {
			Text = Data.ClassIcons[i] .. "\n" .. name,
			TextSize = Theme.ts(14),
			BackgroundTransparency = 0,
			BackgroundColor3 = C.panel,
			AutoButtonColor = false,
			Corner = 10,
			Stroke = { Color = C.brass, Thickness = 1 },
			LayoutOrder = i,
			Parent = grid,
		})
		f.Activated:Connect(function()
			selClass = i
			refresh()
		end)
		classTiles[i] = { frame = f, stroke = f:FindFirstChildOfClass("UIStroke") }
	end
	Theme.label({ Text = "MODE", Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.brass, TextSize = 14, LayoutOrder = 3, Parent = left })
	for i, m in MODES do
		local b = Theme.button({
			Text = m[2] .. "\n" .. m[3],
			Color = C.panel2,
			Size = UDim2.new(1, -8, 0, 48),
			TextSize = Theme.ts(14),
			LayoutOrder = 3 + i,
			OnClick = function()
				local p = profile()
				if m[1] == "premium" and not modeUnlocked(p, "premium") then
					Panels.open("Shop")
					return
				end
				selMode = m[1]
				refresh()
			end,
			Parent = left,
		})
		table.insert(modeButtons, { mode = m[1], btn = b, title = m[2], sub = m[3] })
	end
	Theme.button({
		Text = "View odds",
		Color = Color3.fromRGB(70, 110, 160),
		Size = UDim2.new(1, -8, 0, 44),
		TextSize = Theme.ts(16),
		LayoutOrder = 10,
		OnClick = function()
			Panels.open("Odds")
		end,
		Parent = left,
	})

	-- Right column: materials + start
	local right = Theme.make("Frame", { Size = UDim2.new(0.56, -6, 1, 0), Position = UDim2.new(0.44, 6, 0, 0), BackgroundTransparency = 1, Parent = content })
	Theme.label({ Text = "MATERIAL", Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.brass, TextSize = 14, Parent = right })
	local list = Theme.scroll({ Size = UDim2.new(1, 0, 1, -96), Position = UDim2.new(0, 0, 0, 22), Parent = right })
	Theme.list(list, 5)
	for i = 1, 32 do
		local mat = Data.mat(i)
		local f = Theme.make("TextButton", {
			Text = "",
			Size = UDim2.new(1, -8, 0, 52),
			BackgroundTransparency = 0,
			BackgroundColor3 = C.panel,
			AutoButtonColor = false,
			Corner = 8,
			Stroke = { Color = C.brass, Thickness = 1 },
			LayoutOrder = i,
			Visible = false,
			Parent = list,
		})
		Theme.make("Frame", { Size = UDim2.new(0, 10, 1, -12), Position = UDim2.new(0, 6, 0, 6), BackgroundColor3 = mat.color, Corner = 4, Parent = f, Name = "Swatch" })
		Theme.label({ Text = mat.name, Size = UDim2.new(1, -110, 0, 24), Position = UDim2.new(0, 24, 0, 5), TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.ts(16), TextColor3 = mat.color, TextWrapped = false, Font = Theme.Font, Parent = f, Name = "Name" })
		Theme.label({ Text = Format.abbr(mat.priceMin) .. " - " .. Format.abbr(mat.priceMax) .. " coins", Size = UDim2.new(1, -110, 0, 18), Position = UDim2.new(0, 24, 0, 29), TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.ts(12), TextColor3 = C.dim, TextWrapped = false, Parent = f, Name = "Price" })
		local count = Theme.label({ Text = "x0", Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(1, -86, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = Theme.ts(18), Parent = f })
		f.Activated:Connect(function()
			local p = profile()
			if p and ((p.ingots and p.ingots[i]) or 0) < 1 then
				Toast.show("No " .. Data.mat(i).name .. " ingots yet", "bad")
			end
			selMat = i
			refresh()
		end)
		matRows[i] = { frame = f, count = count, stroke = f:FindFirstChildOfClass("UIStroke") }
	end
	summary = Theme.label({ Text = "", Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(1, 0, 1, -72), AnchorPoint = Vector2.new(1, 0), TextSize = Theme.ts(13), TextColor3 = C.dim, Parent = right })
	startBtn = Theme.button({
		Text = "START FORGING",
		Color = C.orange,
		Size = UDim2.new(1, 0, 0, 52),
		Position = UDim2.new(0, 0, 1, -52),
		TextSize = Theme.ts(26),
		OnClick = function()
			startForge({ cls = selClass, mat = selMat or 1, mode = selMode })
		end,
		Parent = right,
	})
end

function M.init()
	buildPanel()
	ForgeGame.init()
	ForgeReveal.init()
	ForgeGame.onReveal = showReveal

	State.observe(function(p)
		-- track journal as it was before any unresolved pending weapon
		if not p.pending and p.journal then shadowJournal = table.clone(p.journal) end
		if firstProfile then
			firstProfile = false
			selMat = p.selectedMaterial or 1
			if p.pending and not ForgeGame.isActive() then
				task.delay(1, function()
					if not ForgeGame.isActive() and not Panels.isOpen("ForgeReveal") and State.profile and State.profile.pending then
						showReveal({ weapon = State.profile.pending })
					end
				end)
			end
		end
		refresh()
	end)

	Net.on("ForgeResult", function(payload)
		if type(payload) ~= "table" or not payload.weapon then return end
		ForgeSignals.Result:Fire(payload.weapon, payload.luck)
		local w = payload.weapon
		if payload.auto then
			Toast.ticker(string.format("%s  🪙 %s", Data.weaponName(w), Format.abbr(w.v)), Theme.rarityColor(w.r))
		elseif ForgeGame.isActive() then
			ForgeGame.deliver(payload)
		else
			showReveal(payload)
		end
	end)

	Net.on("ForgePhase", function(p)
		if type(p) == "table" and p.phase == "cancelled" then
			ForgeGame.cancel()
			Toast.show("Forge cancelled", "info")
		end
	end)
end

return M
