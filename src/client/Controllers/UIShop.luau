--!nonstrict
-- Products and safe Studio test grants. Real purchase availability is server-owned.
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local Data = require(script.Parent.Parent.UI.Data)
local Panels = require(script.Parent.Parent.UI.Panels)
local Toast = require(script.Parent.Parent.UI.Toast)

local M = { Priority = 30 }
local C = Theme.Colors
local window, list, notice
local rows = {}
local sig = ""

local function refresh()
	local p = State.profile
	if not p or not window or not window.Visible then return end
	local products = Data.products()
	local live = p.productsLive == true
	local allowed = p.paidRandomAllowed == true
	local narrow = list.AbsoluteSize.X < 500
	local parts = { tostring(live), tostring(allowed), tostring(p.isStudio), tostring(narrow), #products }
	for _, entry in products do
		table.insert(parts, entry.key .. (p.entitlements and p.entitlements[entry.key] and "1" or "0"))
	end
	local s = table.concat(parts, ",")
	if s == sig then return end
	sig = s
	notice.Text = not allowed and "Paid random items are unavailable for this account or region." or (live and "" or "Playtest store: Robux purchases are disabled.")
	for _, row in rows do row:Destroy() end
	table.clear(rows)
	for i, entry in products do
		local def = entry.def
		local owned = p.entitlements and p.entitlements[entry.key] == true
		local blocked = def.paidRandom == true and not allowed
		local f = Theme.make("Frame", { Name = "Product_" .. entry.key, Size = UDim2.new(1, -8, 0, narrow and 216 or 166), BackgroundColor3 = C.panel, Corner = 10, Stroke = { Color = owned and C.good or C.brass, Thickness = 2 }, LayoutOrder = i, Parent = list })
		Theme.label({ Text = def.name or entry.key, Size = UDim2.new(1, -24, 0, narrow and 40 or 28), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, Font = Theme.Font, TextColor3 = owned and C.good or C.text, Parent = f })
		Theme.label({ Text = def.description or "", Size = UDim2.new(1, -24, 0, narrow and 82 or 48), Position = UDim2.fromOffset(12, narrow and 48 or 36), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.dim, TextSize = 14, Parent = f })
		local price = def.illustrativeRobux and string.format("R$ %d (proposed price)", def.illustrativeRobux) or ""
		Theme.label({ Text = price, Size = UDim2.new(1, -24, 0, 20), Position = UDim2.new(0, 12, 1, -80), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.coin, TextSize = 13, Parent = f })
		local actions = Theme.make("Frame", { Name = "Actions", Size = UDim2.new(1, -24, 0, 48), Position = UDim2.new(0, 12, 1, -56), BackgroundTransparency = 1, Parent = f })
		Theme.list(actions, 6, Enum.FillDirection.Horizontal)
		local buttons = {}
		local function button(text, callback, color)
			local b = Theme.button({ Name = text:gsub("%W", ""), Text = text, Color = color or Color3.fromRGB(70, 110, 160), Size = UDim2.new(1, 0, 0, 44), TextSize = 14, OnClick = callback, Parent = actions })
			table.insert(buttons, b)
			return b
		end
		if blocked then
			Theme.label({ Text = "Unavailable for this account", Size = UDim2.new(1, 0, 0, 44), TextColor3 = C.bad, TextSize = 14, Parent = actions })
		elseif owned and def.kind == "pass" then
			button("Owned", function() end, C.good)
			Theme.setEnabled(buttons[1], false)
		else
			local buy = button(live and "Buy" or "Purchases off", function()
				if not live then return end
				local ok, res = Net.call("Purchase", entry.key)
				if not ok then Toast.show(res, "bad") end
			end, live and C.good or C.steel)
			Theme.setEnabled(buy, live)
			if p.isStudio and not live then
				button("Grant test", function()
					local ok, res = Net.call("DevGrant", entry.key)
					if not ok then Toast.show(res, "bad") else Toast.show("Granted " .. (def.name or entry.key) .. " for testing", "good") end
				end)
			end
		end
		if def.paidRandom and not blocked then
			button("View odds", function() Panels.open("Odds") end)
		end
		for _, b in buttons do b.Size = UDim2.new(1 / #buttons, -6 * (#buttons - 1) / #buttons, 0, 44) end
		table.insert(rows, f)
	end
	if #products == 0 then
		table.insert(rows, Theme.label({ Text = "The shop is empty right now.", Size = UDim2.new(1, 0, 0, 50), TextColor3 = C.dim, Parent = list }))
	end
end

function M.init()
	local content
	window, content = Panels.create("Shop", "Shop", { onOpen = function() sig = "" refresh() end })
	notice = Theme.label({ Text = "", Size = UDim2.new(1, 0, 0, 38), TextColor3 = C.dim, TextSize = 13, Parent = content })
	list = Theme.scroll({ Name = "Products", Size = UDim2.new(1, 0, 1, -44), Position = UDim2.fromOffset(0, 44), Parent = content })
	Theme.list(list, 8)
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
	State.observe(refresh)
end

return M
