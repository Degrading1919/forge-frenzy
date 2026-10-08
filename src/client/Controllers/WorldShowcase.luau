--!nonstrict
--[[
	Renders every workshop's displayed weapons on its podiums (data: plot.ShowcaseData JSON
	{ slots = [8], unlocked, shield }) with a floating "+$X/sec" income label, and shows stolen
	weapons being carried above the thief's head with a big THIEF! marker (player attribute
	"Carrying" = "m,c,r,d").
]]
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Common = require(script.Parent.WorldUtil.Common)
local WeaponDisplay = require(script.Parent.WorldUtil.WeaponDisplay)

local WorldShowcase = { Priority = 0 }

local CULL = 120
local tracked = {} -- [plot] = { slots = { [i] = { sig, inst, fix, pos, gui } } }
local t = 0

local function clearSlot(s)
	if s.inst then
		s.inst:Destroy()
	end
	if s.gui then
		s.gui:Destroy()
	end
	s.inst, s.gui, s.fix, s.pos, s.sig = nil, nil, nil, nil, nil
end

local function textLabel(parent, y, h, text, color, size)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(0, y)
	l.Size = UDim2.new(1, 0, 0, h)
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(22, 18, 48)
	stroke.Parent = l
	l.Parent = parent
	return l
end

local function makeLabel(top, e)
	local gui = Instance.new("BillboardGui")
	gui.Name = "ShowcaseLabel"
	gui.Adornee = top
	gui.Size = UDim2.fromOffset(220, 74)
	gui.StudsOffset = Vector3.new(0, 6.6, 0)
	gui.MaxDistance = 45
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	textLabel(gui, 0, 24, WeaponDisplay.displayName(e), Common.rarityColor(e.r), 20)
	textLabel(gui, 24, 26, "$" .. Common.abbrev(e.v or 0), Color3.fromRGB(255, 220, 90), 24)
	textLabel(gui, 50, 24, "+$" .. Common.abbrev(e.inc or 0) .. "/sec", Color3.fromRGB(100, 240, 110), 22)
	gui.Parent = top
	return gui
end

local function render(plot, tr, raw)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw ~= "" and raw or "{}")
	if not ok or type(data) ~= "table" then
		data = {}
	end
	local list = data.slots or {}
	local showcase = plot:FindFirstChild("Showcase")
	for i = 1, 8 do
		local s = tr.slots[i]
		if not s then
			s = {}
			tr.slots[i] = s
		end
		local e = list[i]
		local sig = ""
		local ped0 = showcase and showcase:FindFirstChild("Pedestal" .. i)
		if type(e) == "table" and e.c and not e.gone and ped0 then
			sig = HttpService:JSONEncode(e)
		end
		if sig ~= (s.sig or "") then
			clearSlot(s)
			local ped = showcase and showcase:FindFirstChild("Pedestal" .. i)
			local top = ped and ped:FindFirstChild("Top")
			local spot = top and top:FindFirstChild("DisplaySpot")
			if sig ~= "" and spot then
				local inst, fix = WeaponDisplay.build(e, 4)
				inst.Parent = ped
				s.inst, s.fix, s.pos, s.sig = inst, fix, spot.WorldPosition + Vector3.new(0, 1, 0), sig
				s.gui = makeLabel(top, e)
				s.phase = i * 1.3
			end
		end
	end
end

local function bind(plot, tr, sv)
	if tr.sv == sv then
		return
	end
	tr.sv = sv
	sv:GetPropertyChangedSignal("Value"):Connect(function()
		render(plot, tr, sv.Value)
	end)
	render(plot, tr, sv.Value)
end

local function track(plot)
	if tracked[plot] then
		return
	end
	local tr = { slots = {} }
	tracked[plot] = tr
	local sv = plot:FindFirstChild("ShowcaseData")
	if sv and sv:IsA("StringValue") then
		bind(plot, tr, sv)
	end
	plot.ChildAdded:Connect(function(c)
		if c.Name == "ShowcaseData" and c:IsA("StringValue") then
			bind(plot, tr, c)
		end
	end)
end

local function step(dt)
	t += dt
	local camPos = Common.camPos()
	if not camPos then
		return
	end
	local vfx = Common.vfx()
	for _, tr in tracked do
		for _, s in tr.slots do
			if s.inst and s.pos and (s.pos - camPos).Magnitude < CULL then
				local bob = vfx and math.sin(t * 1.5 + s.phase) * 0.2 or 0
				s.inst:PivotTo(CFrame.new(s.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, t * 0.7 + s.phase, 0) * s.fix)
			end
		end
	end
end

-- Stolen weapons riding above thieves' heads ------------------------------------------------

local Players = game:GetService("Players")
local carried = {} -- [player] = { sig, inst, fix, gui }

local function clearCarry(player)
	local c = carried[player]
	if c then
		if c.inst then c.inst:Destroy() end
		if c.gui then c.gui:Destroy() end
		carried[player] = nil
	end
end

local function updateCarry(player)
	local sig = player:GetAttribute("Carrying")
	local c = carried[player]
	if not sig or sig == "" then
		clearCarry(player)
		return
	end
	if c and c.sig == sig then
		return
	end
	clearCarry(player)
	local m, cl, r, d = string.match(sig, "^(%d+),(%d+),(%d+),(.+)$")
	if not m then
		return
	end
	local e = { m = tonumber(m), c = tonumber(cl), r = tonumber(r), d = d }
	local inst, fix = WeaponDisplay.build(e, 3.5)
	inst.Parent = Common.fxFolder()
	local gui = Instance.new("BillboardGui")
	gui.Name = "ThiefMarker"
	gui.Size = UDim2.fromOffset(180, 44)
	gui.StudsOffset = Vector3.new(0, 7.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	local label = textLabel(gui, 0, 44, if player == Players.LocalPlayer then "RUN HOME!" else "THIEF! TAG THEM!", Color3.fromRGB(255, 80, 90), 30)
	label.Size = UDim2.new(1, 0, 1, 0)
	gui.Parent = Common.player:WaitForChild("PlayerGui")
	carried[player] = { sig = sig, inst = inst, fix = fix, gui = gui }
end

local function stepCarries()
	for player, c in carried do
		local char = player.Character
		local head = char and char:FindFirstChild("Head")
		if not head or player.Parent ~= Players then
			clearCarry(player)
		else
			c.gui.Adornee = head
			c.inst:PivotTo(CFrame.new(head.Position + Vector3.new(0, 3.2 + math.sin(t * 4) * 0.25, 0)) * CFrame.Angles(0, t * 2, 0) * c.fix)
		end
	end
end

function WorldShowcase.start()
	local function watch(player)
		player:GetAttributeChangedSignal("Carrying"):Connect(function()
			updateCarry(player)
		end)
		updateCarry(player)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clearCarry)
	RunService.Heartbeat:Connect(stepCarries)
	-- Podiums appear when they are built; re-render now and then so new ones fill in.
	task.spawn(function()
		while true do
			task.wait(2)
			for plot, tr in tracked do
				if tr.sv and tr.sv.Parent then
					pcall(render, plot, tr, tr.sv.Value)
				end
			end
		end
	end)
	local plots = nil
	while not plots do
		plots = Common.plotsFolder()
		if not plots then
			task.wait(1)
		end
	end
	for _, p in plots:GetChildren() do
		track(p)
	end
	plots.ChildAdded:Connect(track)
	RunService.RenderStepped:Connect(step)
end

return WorldShowcase
