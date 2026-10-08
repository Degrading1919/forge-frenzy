--!nonstrict
-- Evolution panel: requirements/progress, keep/reset previews, confirm + protected evolve, celebration.
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Parent.UI.Theme)
local Format = require(script.Parent.Parent.UI.Format)
local Panels = require(script.Parent.Parent.UI.Panels)
local Toast = require(script.Parent.Parent.UI.Toast)

local M = { Priority = 30 }
local C = Theme.Colors

local window, ui = nil, {}
local status = nil
local fetching = false
local lastFetch = 0

local function pctText(b)
	if type(b) ~= "table" then return "-" end
	return string.format("+%d%% production, +%d%% prep", math.round((b.production or 0) * 100), math.round((b.prep or 0) * 100))
end

local function fillList(frame, items, color, bullet)
	for _, c in frame:GetChildren() do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	for i, s in items or {} do
		Theme.label({
			Text = bullet .. " " .. tostring(s),
			Size = UDim2.new(1, -4, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			TextSize = Theme.ts(12),
			LayoutOrder = i,
			Parent = frame,
		})
	end
end

local function render()
	local p = State.profile
	if not status or not p or not window or not window.Visible then return end
	local st = status
	ui.rank.Text = string.format("Rank %d   -   %s", st.rank or p.evolutionRank or 0, pctText(st.bonuses))
	ui.next.Text = "Next rank: " .. pctText(st.nextBonuses)
	local req, prog = st.requirements or {}, st.progress or {}
	Theme.setBar(ui.forged, (req.forged or 0) > 0 and (prog.forged or 0) / req.forged or 1, string.format("Weapons forged since evolve: %s / %s", Format.abbr(prog.forged or 0), Format.abbr(req.forged or 0)))
	Theme.setBar(ui.tier, (req.tier or 0) > 0 and (prog.tier or 0) / req.tier or 1, string.format("Fresh material tier: %d / %d", prog.tier or 0, req.tier or 0))
	local preview = st.preview or {}
	local normal = preview.normal or preview
	local prot = preview.protected
	fillList(ui.keeps, normal.keeps, C.good, "+")
	fillList(ui.resets, normal.resets, C.bad, "-")
	local charges = st.protectedCharges or 0
	local eligible = st.eligible == true
	Theme.setEnabled(ui.evolve, eligible)
	ui.evolve.Text = eligible and "EVOLVE" or "Not ready yet"
	if charges > 0 or (p.entitlements and p.entitlements.ProtectedEvolution) then
		ui.prot.Text = string.format("Protected Evolve (%d)", charges)
		Theme.setEnabled(ui.prot, eligible and charges > 0)
	else
		ui.prot.Text = "Protected Evolve 🔒"
		Theme.setEnabled(ui.prot, true)
	end
	ui.protHint.Text = prot and "Protected keeps: " .. table.concat(prot.keeps or {}, ", ") or ""
end

local function fetch()
	if fetching then return end
	fetching = true
	lastFetch = os.clock()
	local ok, res = Net.call("EvolutionStatus")
	fetching = false
	if ok and type(res) == "table" then
		status = res
		render()
	elseif not ok then
		Toast.show(res, "bad")
	end
end

local function confirm(protected: boolean)
	ui.confirmText.Text = protected
			and "Protected Evolve keeps your coins, materials and machines (uses 1 charge). Continue?"
			or "Evolving resets coins, ore, ingots and machine levels. Collection, pets and purchases are kept. Continue?"
	ui.confirm.Visible = true
	ui.confirmYes.Text = protected and "Protected Evolve" or "Evolve"
	ui.confirmProtected = protected
end

local function celebrate(rank)
	local root = Panels.layer("Toast")
	local f = Theme.make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.coin, BackgroundTransparency = 0.3, ZIndex = 40, Parent = root })
	local t = Theme.make("TextLabel", { Text = "EVOLVED!\nRank " .. tostring(rank), Size = UDim2.new(1, 0, 1, 0), TextSize = 64, TextColor3 = C.bg, ZIndex = 41, Parent = f })
	Theme.make("UIScale", { Scale = 0.3, Parent = t })
	Theme.tween(t.UIScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	for i = 1, 24 do
		local p = Theme.make("TextLabel", {
			Text = (i % 2 == 0) and "✨" or "⭐",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 40, 0, 40),
			TextSize = 32,
			ZIndex = 42,
			Parent = f,
		})
		local a = math.random() * math.pi * 2
		local d = 0.2 + math.random() * 0.45
		Theme.tween(p, 1.4, { Position = UDim2.new(0.5 + math.cos(a) * d, 0, 0.5 + math.sin(a) * d, 0), TextTransparency = 1 })
	end
	task.delay(2.2, function()
		Theme.tween(f, 0.5, { BackgroundTransparency = 1 })
		Theme.tween(t, 0.5, { TextTransparency = 1 })
		task.delay(0.6, function()
			f:Destroy()
		end)
	end)
end

local function build()
	local content
	window, content = Panels.create("Evolution", "Blacksmith Evolution", { onOpen = fetch })
	ui.rank = Theme.make("TextLabel", { Text = "", Size = UDim2.new(1, 0, 0, 30), TextSize = Theme.ts(20), TextColor3 = C.coin, Parent = content })
	ui.next = Theme.label({ Text = "", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 30), TextColor3 = C.dim, TextSize = Theme.ts(13), Parent = content })
	ui.forged = Theme.bar({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 56), FillColor = C.orange, Parent = content })
	ui.tier = Theme.bar({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 88), FillColor = C.good, Parent = content })
	local cols = Theme.make("Frame", { Size = UDim2.new(1, 0, 1, -230), Position = UDim2.new(0, 0, 0, 120), BackgroundTransparency = 1, Parent = content })
	for idx, def in { { "keeps", "KEPT", C.good }, { "resets", "RESET", C.bad } } do
		local col = Theme.make("Frame", { Size = UDim2.new(0.5, -4, 1, 0), Position = UDim2.new((idx - 1) * 0.5, idx == 2 and 4 or 0, 0, 0), BackgroundColor3 = C.panel, Corner = 8, Stroke = { Color = def[3], Thickness = 1.5 }, Parent = cols })
		Theme.label({ Text = def[2], Size = UDim2.new(1, 0, 0, 22), TextColor3 = def[3], TextSize = Theme.ts(14), Parent = col })
		local l = Theme.scroll({ Size = UDim2.new(1, -8, 1, -26), Position = UDim2.new(0, 6, 0, 24), Parent = col })
		Theme.list(l, 3)
		ui[def[1]] = l
	end
	ui.protHint = Theme.label({ Text = "", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -106), TextColor3 = C.dim, TextSize = Theme.ts(11), Parent = content })
	ui.evolve = Theme.button({
		Text = "EVOLVE",
		Color = C.orange,
		Size = UDim2.new(0.5, -4, 0, 56),
		Position = UDim2.new(0, 0, 1, -56),
		TextSize = Theme.ts(22),
		OnClick = function()
			confirm(false)
		end,
		Parent = content,
	})
	ui.prot = Theme.button({
		Text = "Protected Evolve",
		Color = Color3.fromRGB(150, 90, 220),
		Size = UDim2.new(0.5, -4, 0, 56),
		Position = UDim2.new(0.5, 4, 1, -56),
		TextSize = Theme.ts(18),
		OnClick = function()
			local p = State.profile
			if (status and (status.protectedCharges or 0) > 0) then
				confirm(true)
			else
				Toast.show("Protected Evolution is a Shop item", "info")
				Panels.open("Shop")
			end
		end,
		Parent = content,
	})
	-- confirm dialog
	ui.confirm = Theme.make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Visible = false, ZIndex = 10, Parent = content })
	local box = Theme.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0.9, 0, 0, 170), BackgroundColor3 = C.bg, Corner = 12, Stroke = { Color = C.orange, Thickness = 3 }, ZIndex = 11, Parent = ui.confirm })
	ui.confirmText = Theme.label({ Text = "", Size = UDim2.new(1, -20, 0, 80), Position = UDim2.new(0, 10, 0, 8), TextSize = Theme.ts(15), ZIndex = 12, Parent = box })
	ui.confirmYes = Theme.button({
		Text = "Evolve",
		Color = C.orange,
		Size = UDim2.new(0.5, -14, 0, 50),
		Position = UDim2.new(0, 10, 1, -60),
		ZIndex = 12,
		OnClick = function()
			ui.confirm.Visible = false
			local ok, res = Net.call("Evolve", ui.confirmProtected == true)
			if not ok then Toast.show(res, "bad") end
			fetch()
		end,
		Parent = box,
	})
	Theme.button({
		Text = "Cancel",
		Color = C.steel,
		Size = UDim2.new(0.5, -14, 0, 50),
		Position = UDim2.new(0.5, 4, 1, -60),
		ZIndex = 12,
		OnClick = function()
			ui.confirm.Visible = false
		end,
		Parent = box,
	})
end

function M.init()
	build()
	State.observe(function()
		if window.Visible then
			if os.clock() - lastFetch > 2 then task.spawn(fetch) else render() end
		end
	end)
	Net.on("Evolved", function(p)
		celebrate(type(p) == "table" and p.rank or "?")
		Toast.announce("EVOLVED! Rank " .. tostring(type(p) == "table" and p.rank or "?"), 6)
		if window.Visible then task.spawn(fetch) end
	end)
end

return M
