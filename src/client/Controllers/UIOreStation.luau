--!nonstrict
--[[
	Ore station panel (docs/21 §5, §7): opened at an ore line's drill or smelter.

	Every material is one big tile. Tap an owned material to mine it on this line. The next
	material shows its price and buys itself when tapped. Later materials show their price and
	what you need first. Below: the drill and smelter upgrades with "now -> next" numbers.
]]
local State = require(script.Parent.Parent.State)
local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Panels = require(UI.Panels)
local Data = require(UI.Data)
local Kit = require(UI.Kit)
local Reveal = require(UI.Reveal)
local Format = require(UI.Format)
local Net = require(script.Parent.Parent.Net)

local M = { Priority = 10 }
local C = Theme.Colors

local line = 1
local ui: any = {}
local tiles = {}
local refreshers = {}

local function tile(parent: Instance, m: number)
	local mat = Data.mat(m)
	local b = Instance.new("TextButton")
	b.Name = "Mat" .. m
	b.LayoutOrder = m
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Theme.shade(mat.color, -0.45)
	Theme.make("UICorner", { CornerRadius = UDim.new(0, 16), Parent = b })
	local stroke = Theme.make("UIStroke", { Color = C.ink, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	local icon = Kit.ingotIcon(b, m, 64, { Position = UDim2.new(0.5, 0, 0, 10), AnchorPoint = Vector2.new(0.5, 0) })
	local name = Theme.text({ Text = mat.name, Position = UDim2.fromOffset(4, 52), Size = UDim2.new(1, -8, 0, 28), TextScaled = true, Parent = b })
	local sub = Theme.text({ Text = "", Position = UDim2.fromOffset(4, 82), Size = UDim2.new(1, -8, 0, 30), TextSize = 22, Parent = b })
	local lock = Theme.text({ Text = "🔒", Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(4, 4), TextSize = 22, TextStroke = false, Parent = b })
	b.Parent = parent
	b.Activated:Connect(function()
		local p = State.profile
		if not p then return end
		if m <= (p.unlockedTier or 1) then
			local ok = Kit.call("LineMaterial", line, m)
			if ok then Theme.pop(b, 0.9) end
		elseif m == (p.unlockedTier or 1) + 1 then
			local ok = Kit.call("UnlockMaterial", m, line)
			if ok then
				Reveal.message("NEW METAL!", mat.name .. " unlocked!", mat.color, "⛏️", "Your ore line now mines it")
				Net.call("TutorialStep", 4)
			end
		else
			Theme.shake(b)
		end
	end)
	return function(p)
		local unlocked = p.unlockedTier or 1
		local mine = p.lines and p.lines[line] and p.lines[line].m or 1
		local owned = m <= unlocked
		local isNext = m == unlocked + 1
		lock.Visible = not owned
		icon.BackgroundTransparency = if owned or isNext then 0 else 0.5
		b.BackgroundColor3 = if owned then Theme.shade(mat.color, -0.45) else Theme.shade(mat.color, -0.75)
		if owned then
			sub.Text = if m == mine then "⛏️ MINING" else "Tap to mine"
			sub.TextColor3 = if m == mine then C.yellow else C.dim
			stroke.Color = if m == mine then C.yellow else C.ink
			stroke.Thickness = if m == mine then 6 else 3
		elseif isNext then
			sub.Text = Theme.money(mat.unlockCost)
			local afford = (p.coins or 0) >= mat.unlockCost
			sub.TextColor3 = if afford then C.cash else C.red
			stroke.Color = if afford then C.green else C.ink
			stroke.Thickness = if afford then 6 else 3
		else
			sub.Text = Theme.money(mat.unlockCost)
			sub.TextColor3 = C.grey
			stroke.Color = C.ink
			stroke.Thickness = 3
		end
		name.TextTransparency = if owned or isNext then 0 else 0.35
	end
end

local function build()
	local window, body = Panels.create("Ore", "Ore Line 1", {
		width = 520,
		height = 660,
		color = Color3.fromRGB(70, 150, 90),
		subtitle = "Pick the metal this line mines",
		onOpen = function(arg)
			line = if type(arg) == "number" then arg else 1
			M.refresh()
			-- Scroll so the next buyable material is in view.
			task.defer(function()
				local p = State.profile
				local target = p and tiles[math.min(32, (p.unlockedTier or 1) + 1)]
				if target and target.button then
					ui.grid.CanvasPosition = Vector2.new(0, math.max(0, target.button.AbsolutePosition.Y - ui.grid.AbsolutePosition.Y + ui.grid.CanvasPosition.Y - 140))
				end
			end)
		end,
	})
	ui.window = window
	ui.grid = body
	ui.next = Theme.card({ LayoutOrder = 0, Size = UDim2.new(1, -6, 0, 70), BackgroundColor3 = Theme.shade(C.green, -0.5), Parent = body })
	ui.nextText = Theme.text({ Text = "", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextSize = 24, TextScaled = true, Parent = ui.next })
	local gridFrame = Theme.make("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = body })
	Theme.grid(gridFrame, Vector2.new(146, 120), 8)
	for m = 1, 32 do
		local refresh = tile(gridFrame, m)
		tiles[m] = { refresh = refresh, button = gridFrame:FindFirstChild("Mat" .. m) }
	end
	Panels.section(body, 2, nil, "UPGRADE THIS LINE")
	local function rate(track: string)
		return function(level: number)
			local p = State.profile
			local rates = p and p.rates
			local base = 1 / 3
			local mult = 1
			if rates then
				local currentLevel = p.levels and p.levels[track] or 0
				local current = if track == "ExtractorOutput" then rates.orePerSec else rates.ingotPerSec
				mult = current / (base * (1 + 0.15 * currentLevel))
			end
			return Format.rate(base * (1 + 0.15 * level) * mult)
		end
	end
	table.insert(refreshers, Kit.upgradeRow(body, 3, "ExtractorOutput", "⛏️", C.orange, rate("ExtractorOutput")))
	table.insert(refreshers, Kit.upgradeRow(body, 4, "SmelterSpeed", "🔥", C.red, rate("SmelterSpeed")))
	Theme.text({ LayoutOrder = 5, Text = "Upgrades help every ore line", Size = UDim2.new(1, 0, 0, 26), TextSize = 19, TextColor3 = C.dim, Parent = body })
end

function M.refresh()
	local p = State.profile
	if not p or not ui.window then return end
	if not (p.lines and p.lines[line]) then line = 1 end
	Panels.setTitle(ui.window, "Ore Line " .. line, nil)
	for _, t in tiles do
		t.refresh(p)
	end
	for _, fn in refreshers do
		fn(p)
	end
	local nextIndex = (p.unlockedTier or 1) + 1
	if nextIndex <= 32 then
		local mat = Data.mat(nextIndex)
		local afford = (p.coins or 0) >= mat.unlockCost
		ui.nextText.Text = if afford then ("Tap " .. mat.name .. " to buy it for " .. Theme.money(mat.unlockCost) .. "!") else ("Next: " .. mat.name .. " for " .. Theme.money(mat.unlockCost))
		ui.next.BackgroundColor3 = if afford then Theme.shade(C.green, -0.3) else Theme.shade(C.panel, -0.3)
	else
		ui.nextText.Text = "You own every metal!"
	end
end

function M.init()
	build()
end

function M.start()
	State.observe(function()
		if Panels.isOpen("Ore") then
			M.refresh()
		end
	end)
end

return M
