--!nonstrict
-- Cheap, distance-culled machine animation on all plots.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Common = require(script.Parent.WorldUtil.Common)
local State = Common.State

local WorldMachines = { Priority = 0 }

local CULL = 160
local DEFAULT_RATE = 1.5
local DEFAULT_ORE = Color3.fromRGB(190, 140, 90)
local MOLTEN_A = Color3.fromRGB(255, 170, 60)
local MOLTEN_B = Color3.fromRGB(255, 80, 20)
local N_CUBES = 6

local plotData = {} -- [plot] = data
local t = 0
local refreshVisual

local GOLD = Color3.fromRGB(222, 176, 73)
local DRAGON = Color3.fromRGB(150, 68, 45)

-- track -> { machine, anchor part, orbit radius, light color }
local UPGRADES = {
	ExtractorOutput = { "Extractor", "TierGem", 3.2, Color3.fromRGB(190, 120, 255) },
	SmelterSpeed = { "Smelter", "Molten", 3.6, Color3.fromRGB(255, 150, 60) },
	StorageCapacity = { "Storage", "Sign", 4.2, Color3.fromRGB(255, 220, 120) },
	FurnaceHeat = { "Furnace", "Dome", 5.5, Color3.fromRGB(255, 110, 40) },
	AnvilFinish = { "Anvil", "Face", 3.4, Color3.fromRGB(255, 240, 200) },
}

local function scan(plot)
	local machines = plot:FindFirstChild("Machines")
	if not machines then
		return nil
	end
	local d = { plot = plot, ang = 0, cubePhase = 0, fillH = 0.4, orbs = {}, levels = {}, accents = {} }
	local ok, cf = pcall(function()
		return plot:GetPivot()
	end)
	d.center = ok and cf.Position or Vector3.zero
	local ex = machines:FindFirstChild("Extractor")
	if ex then
		d.exModel = ex
		d.gear = ex:FindFirstChild("Gear")
		d.bit = ex:FindFirstChild("DrillBit")
		d.shaft = ex:FindFirstChild("DrillShaft")
		d.gem = ex:FindFirstChild("TierGem")
		d.gearCF = d.gear and d.gear.CFrame
		d.bitCF = d.bit and d.bit.CFrame
		d.shaftCF = d.shaft and d.shaft.CFrame
		d.gemColor0 = d.gem and d.gem.Color
	end
	local sm = machines:FindFirstChild("Smelter")
	if sm then
		d.molten = sm:FindFirstChild("Molten")
		d.mouth = sm:FindFirstChild("Mouth")
		d.mouthLight = d.mouth and d.mouth:FindFirstChildOfClass("PointLight")
		d.mouthBright0 = d.mouthLight and d.mouthLight.Brightness
	end
	local st = machines:FindFirstChild("Storage")
	local fill = st and st:FindFirstChild("Fill")
	if fill then
		d.fill = fill
		d.fillCF = fill.CFrame
		d.fillSize = fill.Size
		d.fillMax = fill:GetAttribute("MaxHeight") or 9.6
		d.fillColor0 = fill.Color
	end
	local belt = plot:FindFirstChild("Belt")
	local a0 = belt and belt:FindFirstChild("BeltStart")
	local a1 = belt and belt:FindFirstChild("BeltEnd")
	if a0 and a1 then
		d.beltA, d.beltB = a0.WorldPosition, a1.WorldPosition
	end
	for _, machine in machines:GetChildren() do
		for _, piece in machine:GetChildren() do
			local name = piece.Name
			if piece:IsA("BasePart") and (name == "Base" or name == "DrillHousing" or name == "TopFrame" or name == "Dome" or name == "Stack" or name == "Face") then
				table.insert(d.accents, { part = piece, machine = machine.Name, name = name, color = piece.Color, material = piece.Material })
			end
		end
	end
	return d
end

local function ensureScanned()
	local plots = Common.plotsFolder()
	if not plots then
		return
	end
	for _, plot in plots:GetChildren() do
		if not plotData[plot] then
			local d = scan(plot)
			plotData[plot] = d
			if d then
				local function changed()
					local raw = plot:GetAttribute("VisualState")
					local ok, public = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw ~= "" and raw or "{}")
					d.public = ok and type(public) == "table" and public or nil
					if refreshVisual then refreshVisual(d) end
				end
				plot:GetAttributeChangedSignal("VisualState"):Connect(changed)
				plot:GetAttributeChangedSignal("OwnerUserId"):Connect(changed)
				changed()
			end
		end
	end
end

local function ensureCubes(d)
	if d.cubes or not d.beltA then
		return
	end
	d.cubes = {}
	for i = 1, N_CUBES do
		local c = Instance.new("Part")
		c.Name = "OreCube"
		c.Size = Vector3.new(0.9, 0.9, 0.9)
		c.Anchored = true
		c.CanCollide = false
		c.CanQuery = false
		c.CanTouch = false
		c.CastShadow = false
		c.Material = Enum.Material.Slate
		c.Color = DEFAULT_ORE
		d.cubes[i] = c
	end
end

local function setCubesVisible(d, on)
	if not d.cubes then
		return
	end
	if on and not d.cubesShown then
		local f = Common.fxFolder()
		for _, c in d.cubes do
			c.Parent = f
		end
		d.cubesShown = true
	elseif not on and d.cubesShown then
		for _, c in d.cubes do
			c.Parent = nil
		end
		d.cubesShown = false
	end
end

local function clearOrbs(d, track)
	local list = d.orbs[track]
	if list then
		for _, o in list do
			if type(o) == "table" and o.part then
				o.part:Destroy()
			end
		end
	end
	d.orbs[track] = nil
end

-- Decorative accent for a machine track level: extra light + orbiting glow balls.
local function applyTrack(d, track, level)
	local cfg = UPGRADES[track]
	local machines = d.plot:FindFirstChild("Machines")
	local model = machines and machines:FindFirstChild(cfg[1])
	local anchor = model and model:FindFirstChild(cfg[2])
	if not anchor then
		return
	end
	local light = anchor:FindFirstChild("UpgradeGlow")
	if level <= 0 then
		if light then
			light:Destroy()
		end
		clearOrbs(d, track)
		return
	end
	if not light then
		light = Instance.new("PointLight")
		light.Name = "UpgradeGlow"
		light.Color = cfg[4]
		light.Parent = anchor
	end
	light.Brightness = math.min(6, 0.6 + level * 0.3)
	light.Range = 12 + math.min(16, level)
	local rings = math.min(3, 1 + math.floor(level / 5))
	local have = d.orbs[track]
	if have and have.rings == rings then
		return
	end
	clearOrbs(d, track)
	local list = { rings = rings }
	for r = 1, rings do
		for k = 1, 4 do
			local p = Instance.new("Part")
			p.Name = "UpgradeOrb"
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(0.5, 0.5, 0.5)
			p.Material = Enum.Material.Neon
			p.Color = cfg[4]
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			local angle = k * math.pi / 2 + r
			p.Position = anchor.Position + Vector3.new(math.cos(angle) * cfg[3], (r - 1) * 0.9, math.sin(angle) * cfg[3])
			p.Parent = model
			table.insert(list, { part = p, ring = r, k = k })
		end
	end
	list.center = anchor.Position
	list.radius = cfg[3]
	d.orbs[track] = list
end

local function visualProfile(d)
	if (d.plot:GetAttribute("OwnerUserId") or 0) == 0 then return nil end
	if d.plot == Common.myPlot() then return State.profile end
	local public = d.public
	return public and public.ownerUserId == d.plot:GetAttribute("OwnerUserId") and public or nil
end

refreshVisual = function(d)
	local profile = visualProfile(d)
	local levels = profile and profile.levels or {}
	local passes = profile and profile.entitlements or {}
	local gear = profile and profile.gear or {}
	local parts = {}
	for track in UPGRADES do
		table.insert(parts, tostring(levels[track] or 0))
	end
	for _, key in { "TitanExcavator", "DragonFurnace", "VIPWorkshop" } do table.insert(parts, tostring(passes[key] == true)) end
	table.insert(parts, tostring(gear.Hammer or 0))
	table.insert(parts, tostring(profile and profile.selectedMaterial or 0))
	local sig = table.concat(parts, ",")
	if sig == d.visualSig then return end
	d.visualSig = sig
	-- Material identity is replicated appearance, even outside the animation culling radius
	-- or when Studio/headless clients do not render frames. Only motion needs RenderStepped.
	local materialColor = profile and Common.materialColor(profile.selectedMaterial) or nil
	if d.gem then d.gem.Color = materialColor or d.gemColor0 end
	if d.fill then d.fill.Color = materialColor or d.fillColor0 end
	for track in UPGRADES do applyTrack(d, track, levels[track] or 0) end
	for _, accent in d.accents do
		local color, material = accent.color, accent.material
		if passes.VIPWorkshop and accent.name == "Base" then
			color, material = GOLD:Lerp(accent.color, 0.35), Enum.Material.Metal
		elseif passes.TitanExcavator and accent.machine == "Extractor" and accent.name ~= "Base" then
			color, material = GOLD, Enum.Material.Metal
		elseif passes.DragonFurnace and accent.machine == "Furnace" and accent.name ~= "Base" then
			color, material = DRAGON, Enum.Material.Metal
		elseif accent.machine == "Anvil" and accent.name == "Face" then
			color = accent.color:Lerp(GOLD, math.clamp((gear.Hammer or 0) / 20, 0, 0.45))
		end
		accent.part.Color, accent.part.Material = color, material
	end
end

local function onProfile(profile)
	ensureScanned()
	for _, d in plotData do refreshVisual(d) end
end

local function step(dt)
	t += dt
	local camPos = Common.camPos()
	if not camPos then
		return
	end
	local profile = State.profile
	local vfx = Common.vfx()
	local myPlot = Common.myPlot()
	local pulse = 0.5 + 0.5 * math.sin(t * 4)

	for plot, d in plotData do
		if (d.center - camPos).Magnitude > CULL then
			setCubesVisible(d, false)
			for _, list in d.orbs do
				for _, orb in list do
					if type(orb) == "table" then orb.part.Transparency = 1 end
				end
			end
		else
			local own = plot == myPlot and profile ~= nil
			local visual = visualProfile(d)
			local owned = own or (plot:GetAttribute("OwnerUserId") or 0) ~= 0
			local rate = DEFAULT_RATE
			if visual and visual.rates and visual.rates.orePerSec then
				rate = visual.rates.orePerSec
			elseif not owned then
				rate = 0.1
			end
			local speed = math.clamp(0.5 + math.sqrt(math.max(rate, 0)) * 1.1, 0.5, 7)
			d.ang += dt * speed
			local matColor = visual and Common.materialColor(visual.selectedMaterial) or nil

			-- Extractor
			if d.gear and d.gear.Parent then
				d.gear.CFrame = CFrame.new(d.gearCF.Position) * CFrame.Angles(0, d.ang, 0) * d.gearCF.Rotation
			end
			local bob = math.sin(d.ang * 2.2) * 0.35
			if d.bit and d.bit.Parent then
				d.bit.CFrame = CFrame.new(d.bitCF.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, d.ang * 3, 0) * d.bitCF.Rotation
			end
			if d.shaft and d.shaft.Parent then
				d.shaft.CFrame = d.shaftCF + Vector3.new(0, bob, 0)
			end
			if d.gem and d.gem.Parent then
				local target = matColor or d.gemColor0
				if target and d.gem.Color ~= target then
					d.gem.Color = d.gem.Color:Lerp(target, math.min(1, dt * 6))
				end
			end

			-- Smelter
			if d.molten and d.molten.Parent then
				d.molten.Color = MOLTEN_A:Lerp(MOLTEN_B, pulse)
				d.molten.Transparency = (owned and 0 or 0.5) + 0.12 * pulse
			end
			if d.mouthLight and d.mouthBright0 then
				d.mouthLight.Brightness = d.mouthBright0 * (owned and (0.75 + 0.5 * pulse) or 0.3)
			end

			-- Storage fill
			if d.fill and d.fill.Parent then
				local frac = 0.4
				if own and profile.rates and profile.rates.capacity and profile.rates.capacity > 0 then
					frac = math.min(1, Common.sumArray(profile.ingots) / profile.rates.capacity)
				elseif not owned then
					frac = 0.05
				end
				local target = frac * d.fillMax
				d.fillH += (target - d.fillH) * math.min(1, dt * 3)
				local h = math.max(0.01, d.fillH)
				d.fill.Size = Vector3.new(d.fillSize.X, h, d.fillSize.Z)
				d.fill.CFrame = d.fillCF * CFrame.new(0, (h - d.fillSize.Y) / 2, 0)
				local tc = matColor or d.fillColor0
				if d.fill.Color ~= tc then
					d.fill.Color = d.fill.Color:Lerp(tc, math.min(1, dt * 5))
				end
			end

			-- Belt cubes
			if d.beltA and vfx and owned then
				ensureCubes(d)
				setCubesVisible(d, true)
				d.cubePhase = (d.cubePhase + dt * (0.08 + speed * 0.035)) % 1
				local col = matColor or DEFAULT_ORE
				for i, c in d.cubes do
					local p = (d.cubePhase + (i - 1) / N_CUBES) % 1
					c.Position = d.beltA:Lerp(d.beltB, p) + Vector3.new(0, 0.45, 0)
					if c.Color ~= col then
						c.Color = col
					end
				end
			else
				setCubesVisible(d, false)
			end

			-- Upgrade orbs
			for _, list in d.orbs do
				for _, o in list do
					if type(o) == "table" then
						o.part.Transparency = vfx and 0 or 1
						if vfx then
							local dir = (o.ring % 2 == 0) and -1 or 1
							local a = t * 1.2 * dir + o.k * math.pi / 2 + o.ring
							local r = list.radius + (o.ring - 1) * 0.6
							o.part.Position = list.center + Vector3.new(math.cos(a) * r, 0.9 * (o.ring - 1) + math.sin(t * 2 + o.k) * 0.15, math.sin(a) * r)
						end
					end
				end
			end
		end
	end
end

function WorldMachines.start()
	local plots = nil
	while not plots do
		plots = Common.plotsFolder()
		if not plots then
			task.wait(1)
		end
	end
	ensureScanned()
	plots.ChildAdded:Connect(function()
		task.defer(ensureScanned)
	end)
	State.observe(onProfile)
	RunService.RenderStepped:Connect(step)
end

return WorldMachines
