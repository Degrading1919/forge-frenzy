--!nonstrict
-- Renders each plot owner's showcase weapons on the pedestals (data: plot.ShowcaseData StringValue, JSON array of 6).
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

local function makeLabel(top, e)
	local gui = Instance.new("BillboardGui")
	gui.Name = "ShowcaseLabel"
	gui.Adornee = top
	gui.Size = UDim2.fromOffset(240, 54)
	gui.StudsOffset = Vector3.new(0, 7.5, 0)
	gui.MaxDistance = 30
	gui.AlwaysOnTop = false
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 28)
	name.Font = Enum.Font.FredokaOne
	name.TextSize = 20
	name.TextColor3 = Common.rarityColor(e.r)
	name.TextStrokeTransparency = 0.3
	name.Text = WeaponDisplay.displayName(e)
	name.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(0, 28)
	sub.Size = UDim2.new(1, 0, 0, 22)
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 16
	sub.TextColor3 = Color3.fromRGB(255, 220, 120)
	sub.TextStrokeTransparency = 0.4
	local rn = Common.RarityNames[e.r or 1] or ""
	sub.Text = e.v and (rn .. "  -  " .. Common.abbrev(e.v) .. " coins") or rn
	sub.Parent = gui
	gui.Parent = top
	return gui
end

local function render(plot, tr, raw)
	local ok, list = pcall(HttpService.JSONDecode, HttpService, raw ~= "" and raw or "[]")
	if not ok or type(list) ~= "table" then
		list = {}
	end
	local showcase = plot:FindFirstChild("Showcase")
	for i = 1, 6 do
		local s = tr.slots[i]
		if not s then
			s = {}
			tr.slots[i] = s
		end
		local e = list[i]
		local sig = ""
		if type(e) == "table" and e.c then
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

function WorldShowcase.start()
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
