--!nonstrict
-- Shop panel driven by Shared.Config.Products. Purchases only when productsLive; Studio gets DevGrant.
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
	local products, cfgLive = Data.products()
	local live = p.productsLive == true or cfgLive and p.productsLive == nil
	local allowed = p.paidRandomAllowed ~= false
	local parts = { tostring(live), tostring(allowed), tostring(p.isStudio), #products }
	for _, e in products do
		table.insert(parts, e.key .. (p.entitlements and p.entitlements[e.key] and "1" or "0"))
	end
	local s = table.concat(parts, ",")
	if s == sig then return end
	sig = s

	notice.Text = allowed and "" or "Some paid items are unavailable for your account or region."
	notice.Visible = not allowed
	for _, r in rows do
		r:Destroy()
	end
	table.clear(rows)
	if #products == 0 then
		table.insert(rows, Theme.label({ Text = "The shop is empty right now.", Size = UDim2.new(1, 0, 0, 50), TextColor3 = C.dim, Parent = list }))
	end
	for i, e in products do
		local def = e.def
		local owned = p.entitlements and p.entitlements[e.key] == true
		local blocked = def.paidRandom == true and not allowed
		local f = Theme.make("Frame", { Size = UDim2.new(1, -8, 0, 112), BackgroundColor3 = C.panel, Corner = 10, Stroke = { Color = owned and C.good or C.brass, Thickness = 2 }, LayoutOrder = i, Parent = list })
		Theme.label({ Text = def.name or e.key, Size = UDim2.new(1, -190, 0, 24), Position = UDim2.new(0, 12, 0, 6), TextXAlignment = Enum.TextXAlignment.Left, TextSize = Theme.ts(17), Font = Theme.Font, TextColor3 = owned and C.good or C.text, TextWrapped = false, Parent = f })
		Theme.label({ Text = def.description or "", Size = UDim2.new(1, -190, 0, 40), Position = UDim2.new(0, 12, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.dim, TextSize = Theme.ts(11), Parent = f })
		if def.illustrativeRobux then
			Theme.label({ Text = string.format("R$ %d (illustrative)", def.illustrativeRobux), Size = UDim2.new(1, -190, 0, 18), Position = UDim2.new(0, 12, 1, -22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.coin, TextSize = Theme.ts(12), Parent = f })
		end
		local right = Theme.make("Frame", { Size = UDim2.new(0, 170, 1, -8), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 4), BackgroundTransparency = 1, Parent = f })
		Theme.list(right, 4)
		if blocked then
			Theme.label({ Text = "Unavailable", Size = UDim2.new(1, 0, 0, 44), TextColor3 = C.bad, TextSize = Theme.ts(14), LayoutOrder = 1, Parent = right })
		elseif owned and def.kind == "pass" then
			Theme.label({ Text = "✔ Owned", Size = UDim2.new(1, 0, 0, 44), TextColor3 = C.good, TextSize = Theme.ts(16), LayoutOrder = 1, Parent = right })
		else
			Theme.button({
				Text = live and "Buy" or "Store opens soon",
				Color = live and C.good or C.steel,
				Size = UDim2.new(1, 0, 0, 44),
				TextSize = Theme.ts(15),
				LayoutOrder = 1,
				OnClick = function()
					if not live then
						Toast.show("The store opens soon!", "info")
						return
					end
					local ok, res = Net.call("Purchase", e.key)
					if not ok then Toast.show(res, "bad") end
				end,
				Parent = right,
			})
		end
		if p.isStudio and not live and not blocked and not (owned and def.kind == "pass") then
			Theme.button({
				Text = "Grant test entitlement",
				Color = Color3.fromRGB(70, 110, 160),
				Size = UDim2.new(1, 0, 0, 24),
				TextSize = 10,
				LayoutOrder = 2,
				OnClick = function()
					local ok, res = Net.call("DevGrant", e.key)
					if not ok then Toast.show(res, "bad") else Toast.show("Granted " .. e.key, "good") end
				end,
				Parent = right,
			})
		end
		if def.paidRandom and not blocked then
			Theme.button({
				Text = "View odds",
				Color = Color3.fromRGB(70, 110, 160),
				Size = UDim2.new(1, 0, 0, 22),
				TextSize = 11,
				LayoutOrder = 3,
				OnClick = function()
					Panels.open("Odds")
				end,
				Parent = right,
			})
		end
		table.insert(rows, f)
	end
end

function M.init()
	local content
	window, content = Panels.create("Shop", "Shop", { onOpen = function() sig = "" refresh() end })
	notice = Theme.label({ Text = "", Size = UDim2.new(1, 0, 0, 24), TextColor3 = C.bad, TextSize = Theme.ts(12), Visible = false, Parent = content })
	list = Theme.scroll({ Size = UDim2.new(1, 0, 1, -30), Position = UDim2.new(0, 0, 0, 28), Parent = content })
	Theme.list(list, 8)
	State.observe(refresh)
end

return M
