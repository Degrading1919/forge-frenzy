--!nonstrict
-- Always-on HUD: coins, selected material + storage, rail of panel buttons, FORGE button, auto chip.
local Net = require(script.Parent.Parent.Net)
local player = game:GetService("Players").LocalPlayer
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local Format = require(script.Parent.Parent.UI.Format)
local Data = require(script.Parent.Parent.UI.Data)
local Panels = require(script.Parent.Parent.UI.Panels)
local Toast = require(script.Parent.Parent.UI.Toast)

local M = { Priority = 50 }

local C = Theme.Colors

local RAIL = {
	{ "⚒", "Forge", "Forge" },
	{ "⛏", "Materials", "Materials" },
	{ "🏭", "Workshop", "Workshop" },
	{ "🎒", "Inventory", "Inventory" },
	{ "🥚", "Pets", "Pets" },
	{ "✨", "Evolve", "Evolution" },
	{ "🛒", "Shop", "Shop" },
	{ "⚙", "Settings", "Settings" },
}

local refs = {}
local coinValue = Instance.new("NumberValue")
local coinTween

local function refreshSave()
	if not refs.save then return end
	local p = State.profile
	if not p then refs.save.Text = "Loading profile…" return end
	local save = p.saveStatus or {}
	local state = player:GetAttribute("FFSaveState") or save.saveState or "Loading"
	local delayed = state == "SaveDelayed" or state == "Unavailable" or save.mode == "Unavailable"
	if p.isStudio then
		refs.save.Text = save.persistent == true and "Studio: isolated save" or "Studio: session only"
		if delayed then refs.save.Text ..= " (delayed)" end
	else
		refs.save.Text = delayed and "Saving delayed — stay connected" or (state == "Saved" and "Progress saved" or (state == "Loaded" and "Progress loaded" or "Saving progress…"))
	end
	refs.save.TextColor3 = delayed and C.bad or C.dim
end

local function build()
	local layer = Panels.layer("Hud")

	-- Coins (top center)
	local coins = Theme.make("Frame", {
		Name = "Coins",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.34, 0, 0, 56),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.1,
		Corner = 14,
		Stroke = { Color = C.brass, Thickness = 3 },
		Parent = layer,
	})
	refs.coinCard = coins
	local lim = Instance.new("UISizeConstraint")
	lim.MinSize = Vector2.new(170, 48)
	lim.MaxSize = Vector2.new(340, 64)
	lim.Parent = coins
	Theme.make("TextLabel", {
		Text = "🪙",
		Size = UDim2.new(0, 44, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		TextSize = 28,
		Parent = coins,
	})
	refs.coins = Theme.make("TextLabel", {
		Text = "0",
		Size = UDim2.new(1, -56, 1, 0),
		Position = UDim2.new(0, 50, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = Theme.ts(32),
		TextColor3 = C.coin,
		TextWrapped = false,
		Parent = coins,
	})
	refs.save = Theme.label({ Name = "SaveStatus", Text = "Loading profile…", Size = UDim2.new(0, 230, 0, 20), Position = UDim2.new(1, -238, 1, -24), TextSize = 12, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, Parent = layer })

	-- Auto chip
	refs.chip = Theme.make("Frame", {
		Name = "AutoChip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.new(0, 270, 0, 48),
		BackgroundColor3 = C.bg,
		Visible = false,
		Corner = 20,
		Stroke = { Color = C.orange, Thickness = 2 },
		Parent = layer,
	})
	refs.chipText = Theme.label({
		Text = "AUTO FORGING",
		Size = UDim2.new(1, -96, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = Theme.ts(15),
		TextColor3 = C.orange,
		Parent = refs.chip,
	})
	Theme.button({
		Name = "StopAutoForge",
		Text = "Stop",
		Color = C.bad,
		Size = UDim2.new(0, 80, 0, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		TextSize = Theme.ts(16),
		OnClick = function()
			local ok, res = Net.call("ForgeStopAuto")
			if not ok then Toast.show(res, "bad") end
		end,
		Parent = refs.chip,
	})

	-- Info card (top-left)
	local compact = Theme.compact()
	local card = Theme.make("Frame", {
		Name = "InfoCard",
		Position = UDim2.new(0, 8, 0, 60),
		Size = UDim2.new(0, compact and 170 or 240, 0, compact and 86 or 100),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.1,
		Corner = 12,
		Stroke = { Color = C.brass, Thickness = 2 },
		Parent = layer,
	})
	refs.card = card
	refs.matName = Theme.label({
		Text = "Copper",
		Size = UDim2.new(1, -60, 0, 24),
		Position = UDim2.new(0, 8, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = Theme.ts(20),
		Font = Theme.Font,
		TextWrapped = false,
		Parent = card,
	})
	refs.rank = Theme.label({
		Text = "R0",
		Size = UDim2.new(0, 48, 0, 22),
		Position = UDim2.new(1, -54, 0, 5),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.panel2,
		TextSize = Theme.ts(13),
		TextColor3 = C.coin,
		Corner = 11,
		Stroke = { Color = C.brass, Thickness = 1.5 },
		Parent = card,
	})
	refs.bar = Theme.bar({
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.new(0, 8, 0, 32),
		FillColor = C.orange,
		Parent = card,
	})
	refs.rates = Theme.label({
		Text = "",
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.new(0, 8, 0, 58),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = Theme.ts(12),
		TextColor3 = C.dim,
		Parent = card,
	})

	-- Rail (left)
	local rail = Theme.scroll({
		Name = "Rail",
		Position = UDim2.new(0, 8, 0, compact and 152 or 168),
		Size = UDim2.new(0, 60, 1, compact and -162 or -178),
		ScrollBarThickness = 0,
		Parent = layer,
	})
	refs.rail = rail
	Theme.list(rail, 6)
	for i, def in RAIL do
		local b = Theme.button({
			Name = "Nav" .. def[3],
			Text = def[1],
			Color = C.panel2,
			Size = UDim2.new(0, 74, 0, 62),
			LayoutOrder = i,
			TextSize = 24,
			Font = Theme.Font2,
			OnClick = function()
				Panels.toggle(def[3])
			end,
			Parent = rail,
		})
		Theme.make("TextLabel", {
			Text = def[2],
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.new(0, 0, 1, -19),
			TextSize = 12,
			Font = Theme.Font2,
			TextColor3 = C.dim,
			TextWrapped = false,
			Parent = b,
		})
	end

	-- Big FORGE button
	refs.forge = Theme.button({
		Name = "ForgeButton",
		Text = "⚒ FORGE",
		Color = C.orange,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0, compact and 170 or 220, 0, compact and 58 or 68),
		TextSize = Theme.ts(32),
		Stroke = { Color = C.brass, Thickness = 4 },
		OnClick = function()
			Panels.open("Forge")
		end,
		Parent = layer,
	})
	local function resize()
		local available = layer.AbsoluteSize
		if available.X <= 0 then available = Theme.viewport() - Vector2.new(0, 58) end
		local narrow = available.X < 700
		local short = available.Y < 440
		coins.Size = UDim2.fromOffset(narrow and 200 or 280, 52)
		refs.coins.TextSize = narrow and 28 or 32
		card.Position = UDim2.fromOffset(8, 70)
		card.Size = UDim2.fromOffset(narrow and 170 or 240, 94)
		refs.rates.TextSize = 12
		refs.matName.TextSize = narrow and 16 or 20
		rail.Position = UDim2.fromOffset(8, 174)
		rail.Size = UDim2.new(0, 80, 1, narrow and not short and -312 or -190)
		refs.forge.Size = UDim2.fromOffset(narrow and 180 or 220, short and 52 or 58)
		refs.forge.TextSize = 28
		if narrow and not short then
			refs.chip.AnchorPoint = Vector2.new(0.5, 1)
			refs.chip.Position = UDim2.new(0.5, 0, 1, -82)
			refs.save.Position = UDim2.new(1, -238, 1, -4)
			refs.save.AnchorPoint = Vector2.new(0, 1)
		else
			refs.chip.AnchorPoint = Vector2.new(1, 0)
			refs.chip.Position = UDim2.new(1, -8, 0, 70)
			refs.save.Position = UDim2.new(1, -238, 1, -24)
			refs.save.AnchorPoint = Vector2.new()
		end
	end
	layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	Panels.onViewportChanged(resize)
	resize()
end

local function onProfile(p)
	if not refs.coins then return end
	-- coins count-up
	local target = p.coins or 0
	if coinTween then coinTween:Cancel() end
	coinTween = Theme.tween(coinValue, 0.45, { Value = target })

	local mi = p.selectedMaterial or 1
	local mat = Data.mat(mi)
	refs.matName.Text = mat.name
	refs.matName.TextColor3 = mat.color
	refs.rank.Text = "Rank " .. tostring(p.evolutionRank or 0)
	local rates = p.rates or {}
	local cap = rates.capacity or 0
	local total = Data.sumIngots(p)
	local mine = (p.ingots and p.ingots[mi]) or 0
	Theme.setBar(refs.bar, cap > 0 and total / cap or 0, string.format("%s ingots  %s/%s", Format.abbr(mine), Format.abbr(total), Format.abbr(cap)))
	refs.bar.Fill.BackgroundColor3 = (cap > 0 and total >= cap) and C.bad or C.orange
	refs.rates.Text = string.format("⛏ %s ore/min   🔩 %s ingots/min", Format.rate(rates.orePerSec), Format.rate(rates.ingotPerSec))
	refreshSave()

	local mode = p.autoMode or "off"
	refs.chip.Visible = mode ~= "off" and not Panels.isOpen()
	if mode ~= "off" then
		refs.chipText.Text = mode == "premium" and "AUTO FORGE  4x luck" or "AUTO FORGE  1.5x luck"
	end
end

local function refreshVisibility()
	local open = Panels.isOpen()
	refs.forge.Visible = not open
	refs.card.Visible = not open
	refs.rail.Visible = not open
	refs.coinCard.Visible = not Panels.isOpen("ForgeGame") and not Panels.isOpen("ForgeReveal")
	refs.chip.Visible = not open and State.profile and State.profile.autoMode ~= "off" and State.profile.autoMode ~= nil
	refs.save.Visible = not open
end

function M.init()
	build()
	coinValue.Changed:Connect(function(v)
		refs.coins.Text = Format.abbr(math.floor(v + 0.5))
	end)
	Panels.Changed:Connect(refreshVisibility)
	refreshVisibility()
	State.observe(onProfile)
	player:GetAttributeChangedSignal("FFSaveState"):Connect(refreshSave)
	player:GetAttributeChangedSignal("FFLastSavedAt"):Connect(refreshSave)
end

return M
