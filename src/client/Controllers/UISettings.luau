--!nonstrict
-- Settings panel: music / sfx / vfx toggles and auto-sell-below-rarity picker.
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local Panels = require(script.Parent.Parent.UI.Panels)
local Toast = require(script.Parent.Parent.UI.Toast)

local M = { Priority = 20 }
local C = Theme.Colors

local window
local toggles = {}
local pickers = {}

local TOGGLES = { { "music", "Music" }, { "sfx", "Sound effects" }, { "vfx", "Visual effects" } }
local SELL_LABELS = { "Off", "Below Uncommon", "Below Rare", "Below Epic", "Below Legendary", "Below Mythic" }

local function set(key, value)
	local ok, res = Net.call("SetSetting", key, value)
	if not ok then Toast.show(res, "bad") end
end

local function refresh()
	local p = State.profile
	if not p or not window or not window.Visible then return end
	local s = p.settings or {}
	for key, b in toggles do
		local on = s[key] ~= false
		b.Text = on and "ON" or "OFF"
		Theme.setColor(b, on and C.good or C.steel)
	end
	local cur = s.autoSellBelow or 1
	for i, b in pickers do
		Theme.setColor(b, i == cur and C.orange or C.panel2)
	end
end

function M.init()
	local content
	window, content = Panels.create("Settings", "Settings", { widthScale = 0.5, maxSize = Vector2.new(560, 600), onOpen = refresh })
	local list = Theme.scroll({ Size = UDim2.new(1, 0, 1, 0), Parent = content })
	Theme.list(list, 8)
	for i, t in TOGGLES do
		local row = Theme.make("Frame", { Size = UDim2.new(1, -8, 0, 54), BackgroundColor3 = C.panel, Corner = 10, LayoutOrder = i, Parent = list })
		Theme.label({ Text = t[2], Size = UDim2.new(1, -120, 1, 0), Position = UDim2.new(0, 12, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.ts(17), Parent = row })
		toggles[t[1]] = Theme.button({
			Text = "ON",
			Color = C.good,
			Size = UDim2.new(0, 90, 0, 44),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			TextSize = Theme.ts(18),
			OnClick = function()
				local s = State.profile and State.profile.settings or {}
				set(t[1], not (s[t[1]] ~= false))
			end,
			Parent = row,
		})
	end
	Theme.label({ Text = "AUTO-SELL WEAPONS", Size = UDim2.new(1, -8, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.brass, TextSize = Theme.ts(14), LayoutOrder = 10, Parent = list })
	Theme.label({ Text = "Weapons below the chosen rarity are sold automatically instead of waiting for you.", Size = UDim2.new(1, -8, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.dim, TextSize = Theme.ts(12), LayoutOrder = 11, Parent = list })
	for i, label in SELL_LABELS do
		pickers[i] = Theme.button({
			Text = label,
			Color = C.panel2,
			Size = UDim2.new(1, -8, 0, 46),
			TextSize = Theme.ts(16),
			LayoutOrder = 11 + i,
			OnClick = function()
				set("autoSellBelow", i)
			end,
			Parent = list,
		})
	end
	State.observe(refresh)
end

return M
