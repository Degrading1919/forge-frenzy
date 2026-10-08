--!nonstrict
--[[
	Small station panels for the storage vault and the tool rack (docs/21 §1, §7).

	Vault: one bin per metal with "how full" bars, plus the storage upgrade (+10 Storage).
	Tools: the permanent gear (hammer, gloves, apron) with plain-language effects.
]]
local State = require(script.Parent.Parent.State)
local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Panels = require(UI.Panels)
local Data = require(UI.Data)
local Kit = require(UI.Kit)

local M = { Priority = 10 }
local C = Theme.Colors

local vault: any = {}
local tools: any = {}

local function buildVault()
	local window, body = Panels.create("Vault", "Storage Vault", {
		width = 500,
		height = 600,
		color = Color3.fromRGB(70, 120, 220),
		subtitle = "Your ingots wait here for the forges",
		onOpen = function()
			M.refreshVault()
		end,
	})
	vault.window = window
	vault.storage = Kit.upgradeRow(body, 1, "StorageCapacity", "📦", C.blue, function(level)
		local p = State.profile
		local apron = p and p.gear and p.gear.Apron or 0
		return string.format("%d each", 25 + 10 * level + 25 * apron)
	end)
	Panels.section(body, 2, nil, "BINS")
	vault.bins = Theme.make("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = body })
	Theme.list(vault.bins, 8, nil, Enum.HorizontalAlignment.Center)
	vault.rows = {}
end

function M.refreshVault()
	local p = State.profile
	if not p or not vault.window then return end
	vault.storage(p)
	local cap = p.rates and p.rates.capacity or 25
	for m = 1, p.unlockedTier or 1 do
		local row = vault.rows[m]
		if not row then
			local frame = Theme.card({ LayoutOrder = 100 - m, Size = UDim2.new(1, -6, 0, 58), BackgroundColor3 = Theme.shade(Data.mat(m).color, -0.55), Parent = vault.bins })
			Kit.ingotIcon(frame, m, 44, { Position = UDim2.fromOffset(10, 16) })
			Theme.text({ Text = Data.mat(m).name, Position = UDim2.fromOffset(64, 4), Size = UDim2.fromOffset(150, 50), TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, Parent = frame })
			local bar = Theme.bar({ Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.new(1, -230, 0, 34), FillColor = Data.mat(m).color, Parent = frame })
			row = { frame = frame, bar = bar }
			vault.rows[m] = row
		end
		local n = p.ingots and p.ingots[m] or 0
		Theme.setBar(row.bar, n / cap, string.format("%s / %s", Theme.abbr(n), Theme.abbr(cap)))
		row.frame.Visible = n > 0 or m == (p.unlockedTier or 1) or (p.lines and p.lines[1] and p.lines[1].m == m)
	end
end

local function buildTools()
	local window, body = Panels.create("Tools", "Tool Rack", {
		width = 500,
		height = 560,
		color = Color3.fromRGB(150, 90, 220),
		subtitle = "Tools are yours forever (even after evolving)",
		onOpen = function()
			M.refreshTools()
		end,
	})
	tools.window = window
	tools.rows = {
		Kit.upgradeRow(body, 1, "Hammer", "🔨", C.orange),
		Kit.upgradeRow(body, 2, "Gloves", "🧤", C.pink),
		Kit.upgradeRow(body, 3, "Apron", "🦺", C.teal),
	}
end

function M.refreshTools()
	local p = State.profile
	if not p or not tools.window then return end
	for _, fn in tools.rows do
		fn(p)
	end
end

function M.init()
	buildVault()
	buildTools()
end

function M.start()
	State.observe(function()
		if Panels.isOpen("Vault") then M.refreshVault() end
		if Panels.isOpen("Tools") then M.refreshTools() end
	end)
end

return M
