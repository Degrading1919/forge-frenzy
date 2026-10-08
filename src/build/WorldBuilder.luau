--!strict
--[[
	Edit-time world builder (v2, owner playtest remediation, docs/22).

	Builds Workspace.World: a compact, bright hub with the central sell booth, hatchery,
	evolution altar and leaderboards, ringed by six close-together workshops behind an
	invisible perimeter. Every workshop is a physical tycoon:

	  Ore Line (drill -> raised conveyor -> smelter -> output conveyor) -> Storage Vault -> Forges
	  plus display podiums, a cash collector, a Forge Lock button with laser gate, a tool rack
	  and glowing build pads that reveal more lines, forges, podiums and decorations.

	Run from Studio only after backing up the current world:
	    require(game.ServerStorage.Build.WorldBuilder).build()
	build() keeps the previous World as ServerStorage.Backups.World_<timestamp>, so a rebuild is
	recoverable. Runtime scripts only read this hierarchy (names and attributes below are the
	contract; see docs/22 "World contract").
]]

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")

local WorldBuilder = {}

WorldBuilder.PLOT_COUNT = 6
WorldBuilder.PLOT_RING_RADIUS = 86
WorldBuilder.PLOT_SIZE = 64
WorldBuilder.BOUNDARY_RADIUS = 132
WorldBuilder.PLAZA_RADIUS = 40

local PLOT_SIZE = WorldBuilder.PLOT_SIZE
local HALF = PLOT_SIZE / 2

local rgb = Color3.fromRGB
local C = {
	grass = rgb(88, 196, 84),
	grassDark = rgb(62, 160, 70),
	plaza = rgb(236, 214, 170),
	plazaTile = rgb(255, 196, 92),
	stone = rgb(150, 146, 156),
	stoneDark = rgb(92, 88, 104),
	wall = rgb(255, 236, 200),
	wood = rgb(176, 112, 64),
	woodDark = rgb(120, 72, 40),
	iron = rgb(74, 78, 92),
	steel = rgb(176, 186, 200),
	brass = rgb(255, 196, 64),
	ember = rgb(255, 110, 20),
	emberHot = rgb(255, 214, 80),
	magic = rgb(80, 210, 255),
	water = rgb(60, 170, 255),
	belt = rgb(46, 48, 58),
	beltEdge = rgb(255, 200, 40),
	pad = rgb(60, 255, 120),
	laser = rgb(255, 40, 60),
	cash = rgb(70, 230, 90),
	vault = rgb(70, 120, 220),
	purple = rgb(170, 90, 255),
	pink = rgb(255, 90, 170),
}

-- One bright identity color per workshop.
local PLOT_COLORS = {
	rgb(255, 80, 80),
	rgb(255, 170, 40),
	rgb(255, 230, 60),
	rgb(70, 210, 110),
	rgb(70, 160, 255),
	rgb(190, 100, 255),
}

type Props = { [string]: any }

local function make(className: string, props: Props, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: Props?): Part
	local p = make("Part", {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Anchored = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}, parent)
	if extra then
		for k, v in extra do
			(p :: any)[k] = v
		end
	end
	return p
end

local function cyl(parent: Instance, name: string, diameter: number, height: number, cf: CFrame, color: Color3, material: Enum.Material?, extra: Props?): Part
	-- Roblox cylinders run along X; rotate so `height` is vertical.
	local p = part(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, extra)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, d: number, cf: CFrame, color: Color3, material: Enum.Material?, extra: Props?): Part
	local p = part(parent, name, Vector3.new(d, d, d), cf, color, material, extra)
	p.Shape = Enum.PartType.Ball
	return p
end

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): WedgePart
	return make("WedgePart", { Name = name, Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic, Anchored = true }, parent)
end

local function light(p: BasePart, color: Color3, range: number, brightness: number)
	make("PointLight", { Color = color, Range = range, Brightness = brightness, Shadows = false }, p)
end

local function model(parent: Instance, name: string): Model
	return make("Model", { Name = name }, parent)
end

local function attach(p: BasePart, name: string, offset: Vector3): Attachment
	return make("Attachment", { Name = name, Position = offset }, p)
end

local function outline(p: BasePart, color: Color3)
	make("SelectionBox", { Name = "Outline", Adornee = p, Color3 = color, LineThickness = 0.08, SurfaceTransparency = 1, Transparency = 0.1 }, p)
end

-- Big chunky text on a part face.
local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3?, stroke: Color3?)
	local gui = make("SurfaceGui", {
		Name = "Label",
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0,
		Brightness = 1.4,
	}, p)
	local t = make("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = color or Color3.new(1, 1, 1),
	}, gui)
	make("UIStroke", { Color = stroke or rgb(30, 20, 40), Thickness = 4 }, t)
	return t
end

--------------------------------------------------------------------------------
-- Props
--------------------------------------------------------------------------------

local function crate(parent: Instance, cf: CFrame, s: number)
	local m = model(parent, "Crate")
	part(m, "Box", Vector3.new(s, s, s), cf * CFrame.new(0, s / 2, 0), C.wood, Enum.Material.WoodPlanks)
	for _, y in { 0.08, 0.92 } do
		part(m, "Band", Vector3.new(s + 0.1, s * 0.1, s + 0.1), cf * CFrame.new(0, s * y, 0), C.woodDark, Enum.Material.Wood)
	end
	return m
end

local function lamp(parent: Instance, cf: CFrame, color: Color3)
	local m = model(parent, "Lamp")
	cyl(m, "Post", 0.8, 9, cf * CFrame.new(0, 4.5, 0), C.iron, Enum.Material.Metal)
	local glow = ball(m, "Glow", 2.2, cf * CFrame.new(0, 9.6, 0), color, Enum.Material.Neon)
	light(glow, color, 20, 1.4)
	return m
end

local function tree(parent: Instance, cf: CFrame, s: number, color: Color3?)
	local m = model(parent, "Tree")
	cyl(m, "Trunk", 1.6 * s, 7 * s, cf * CFrame.new(0, 3.5 * s, 0), C.woodDark, Enum.Material.Wood)
	ball(m, "Leaves", 8 * s, cf * CFrame.new(0, 8.5 * s, 0), color or C.grassDark, Enum.Material.Grass)
	ball(m, "Leaves2", 5.5 * s, cf * CFrame.new(1.8 * s, 10.5 * s, 0.8 * s), C.grass, Enum.Material.Grass)
	return m
end

local function rock(parent: Instance, cf: CFrame, s: number)
	return part(parent, "Rock", Vector3.new(4, 2.6, 3.2) * s, cf * CFrame.new(0, 1 * s, 0) * CFrame.Angles(0.2, 0.6, 0.15), C.stone, Enum.Material.Slate)
end

-- A conveyor belt from local point a to b (both at belt-top height), with yellow edges.
local function belt(parent: Instance, name: string, a: Vector3, b: Vector3, frame: CFrame, width: number?): Part
	local w = width or 2.6
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local cf = frame * CFrame.lookAt(mid, b) * CFrame.new(0, -0.3, 0)
	local p = part(parent, name, Vector3.new(w, 0.6, length), cf, C.belt, Enum.Material.DiamondPlate)
	for _, side in { -1, 1 } do
		part(parent, name .. "Edge", Vector3.new(0.3, 0.8, length), cf * CFrame.new(side * (w / 2 + 0.15), 0.2, 0), C.beltEdge, Enum.Material.SmoothPlastic)
	end
	-- Ore travels BeltStart -> BeltEnd (client animation).
	attach(p, "BeltStart", Vector3.new(0, 0.6, length / 2))
	attach(p, "BeltEnd", Vector3.new(0, 0.6, -length / 2))
	return p
end

-- Support legs under a raised belt.
local function legs(parent: Instance, a: Vector3, b: Vector3, frame: CFrame)
	for _, t in { 0.25, 0.75 } do
		local p = a:Lerp(b, t)
		local h = p.Y - 1
		if h > 1 then
			part(parent, "Leg", Vector3.new(0.6, h, 0.6), frame * CFrame.new(p.X, 1 + h / 2 - 0.3, p.Z), C.iron, Enum.Material.Metal)
		end
	end
end

--------------------------------------------------------------------------------
-- Workshop machines (local frame: +Z faces the plot entrance / hub)
--------------------------------------------------------------------------------

local function prompt(base: BasePart, offset: Vector3)
	attach(base, "PromptPoint", offset)
end

-- Ore station: a drill over an ore pit. `tint` colors the ore gem (runtime recolors per material).
local function buildDrill(parent: Instance, cf: CFrame, accent: Color3): Model
	local m = model(parent, "Drill")
	local base = part(m, "Base", Vector3.new(9, 1.2, 9), cf * CFrame.new(0, 0.6, 0), C.stoneDark, Enum.Material.Concrete)
	m.PrimaryPart = base
	prompt(base, Vector3.new(0, 3, 5.5))
	part(m, "OrePit", Vector3.new(5.6, 0.4, 5.6), cf * CFrame.new(0, 1.3, 0), rgb(40, 34, 30), Enum.Material.Slate)
	local gem = part(m, "OreGem", Vector3.new(2.6, 1.6, 2.6), cf * CFrame.new(0, 1.9, 0) * CFrame.Angles(0, 0.6, 0), C.brass, Enum.Material.Neon)
	light(gem, C.emberHot, 12, 1)
	for _, x in { -3.6, 3.6 } do
		part(m, "Post", Vector3.new(0.9, 11, 0.9), cf * CFrame.new(x, 6.7, 0), accent, Enum.Material.SmoothPlastic)
	end
	part(m, "TopBeam", Vector3.new(8.4, 1.2, 1.6), cf * CFrame.new(0, 12.6, 0), accent, Enum.Material.SmoothPlastic)
	part(m, "Housing", Vector3.new(3.6, 3, 3.6), cf * CFrame.new(0, 10.6, 0), C.brass, Enum.Material.Metal)
	cyl(m, "Shaft", 1.2, 5, cf * CFrame.new(0, 6.6, 0), C.steel, Enum.Material.Metal)
	cyl(m, "DrillBit", 2.4, 1.6, cf * CFrame.new(0, 3.6, 0), C.steel, Enum.Material.Metal)
	local sign = part(m, "Sign", Vector3.new(7, 1.8, 0.4), cf * CFrame.new(0, 14.2, 0), C.woodDark, Enum.Material.Wood)
	label(sign, Enum.NormalId.Back, "ORE DRILL", C.emberHot)
	attach(base, "OreOut", Vector3.new(0, 2.4, -3.2))
	return m
end

local function buildSmelter(parent: Instance, cf: CFrame): Model
	local m = model(parent, "Smelter")
	local base = part(m, "Base", Vector3.new(8, 1, 8), cf * CFrame.new(0, 0.5, 0), C.stoneDark, Enum.Material.Concrete)
	m.PrimaryPart = base
	prompt(base, Vector3.new(0, 3, 5))
	local body = part(m, "Body", Vector3.new(6.5, 5.5, 6.5), cf * CFrame.new(0, 3.75, 0), rgb(200, 90, 60), Enum.Material.Brick)
	-- Open hopper on top: ore from the raised belt drops in here.
	part(m, "Hopper", Vector3.new(5, 1.2, 5), cf * CFrame.new(0, 7.1, 0), C.iron, Enum.Material.Metal)
	local molten = part(m, "Molten", Vector3.new(4.2, 0.3, 4.2), cf * CFrame.new(0, 7.6, 0), C.emberHot, Enum.Material.Neon)
	light(molten, C.ember, 14, 2)
	attach(molten, "OreIn", Vector3.new(0, 0.4, 0))
	cyl(m, "Chimney", 1.8, 6, cf * CFrame.new(2.2, 9.5, -2.2), rgb(200, 90, 60), Enum.Material.Brick)
	local mouth = part(m, "Mouth", Vector3.new(3, 2, 0.3), cf * CFrame.new(0, 2.6, 3.3), C.ember, Enum.Material.Neon)
	light(mouth, C.ember, 12, 2)
	label(body, Enum.NormalId.Back, "SMELTER", C.emberHot)
	attach(base, "IngotOut", Vector3.new(4.2, 1.4, 0))
	return m
end

-- One ore line: drill in front, a raised belt carrying ore up into the smelter, and an
-- output belt from the smelter toward the vault. `outTo` is the local point where the output
-- belt ends (at the vault).
local function buildLine(parent: Instance, plot: CFrame, index: number, drillAt: Vector3, smelterAt: Vector3, outTo: Vector3, accent: Color3, padId: string?): Model
	local m = model(parent, "Line" .. index)
	m:SetAttribute("LineIndex", index)
	if padId then
		m:SetAttribute("PadId", padId)
	end
	buildDrill(m, plot * CFrame.new(drillAt) * CFrame.Angles(0, if drillAt.X > 0 then math.rad(0) else 0, 0), accent)
	local smelterCf = plot * CFrame.new(smelterAt)
	buildSmelter(m, smelterCf)
	-- Raised ore belt: from the drill (low) up to above the smelter hopper (high).
	local a = Vector3.new(drillAt.X, 2.6, drillAt.Z - 4.2)
	local b = Vector3.new(smelterAt.X, 8.6, smelterAt.Z + 2.6)
	local oreBelt = belt(m, "OreBelt", a, b, plot)
	oreBelt.Name = "OreBelt"
	legs(m, a, b, plot)
	-- Output belt: from the smelter's side to the vault, at floor height.
	local outFrom = Vector3.new(smelterAt.X + (if outTo.X > smelterAt.X then 4.4 else -4.4), 1.6, smelterAt.Z)
	if math.abs(outTo.X - smelterAt.X) < 3 then
		outFrom = Vector3.new(smelterAt.X, 1.6, smelterAt.Z - 4.4)
	end
	local outBelt = belt(m, "OutBelt", outFrom, Vector3.new(outTo.X, 1.6, outTo.Z), plot, 2.2)
	outBelt.Name = "OutBelt"
	return m
end

-- The storage vault: a chunky blue hopper-vault with a glass window and one bin per material.
local function buildVault(parent: Instance, cf: CFrame): Model
	local m = model(parent, "Storage")
	local base = part(m, "Base", Vector3.new(14, 1, 10), cf * CFrame.new(0, 0.5, 0), C.stoneDark, Enum.Material.Concrete)
	m.PrimaryPart = base
	prompt(base, Vector3.new(0, 3, 6))
	local body = part(m, "Body", Vector3.new(12, 7, 8), cf * CFrame.new(0, 4.5, 0), C.vault, Enum.Material.DiamondPlate)
	outline(body, C.brass)
	-- Hopper funnel on top where the belts drop ingots.
	wedge(m, "FunnelL", Vector3.new(8, 2.4, 3), cf * CFrame.new(-3, 9.2, 0) * CFrame.Angles(0, math.rad(90), 0), C.steel, Enum.Material.Metal)
	wedge(m, "FunnelR", Vector3.new(8, 2.4, 3), cf * CFrame.new(3, 9.2, 0) * CFrame.Angles(0, math.rad(-90), 0), C.steel, Enum.Material.Metal)
	local window = part(m, "Window", Vector3.new(9, 4.4, 0.3), cf * CFrame.new(0, 4.6, 4.1), rgb(160, 220, 255), Enum.Material.Glass, { Transparency = 0.35 })
	-- Fill: runtime scales its height with the fullest bin.
	local fill = part(m, "Fill", Vector3.new(8.6, 0.05, 0.6), cf * CFrame.new(0, 2.5, 3.7), C.brass, Enum.Material.Neon)
	fill:SetAttribute("MaxHeight", 4.2)
	-- Counts board: the client draws ingot bins on this SurfaceGui.
	local board = part(m, "BinBoard", Vector3.new(12, 3, 0.3), cf * CFrame.new(0, 9.6, 4.2), C.woodDark, Enum.Material.Wood)
	make("SurfaceGui", { Name = "Bins", Face = Enum.NormalId.Back, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0 }, board)
	local sign = part(m, "Sign", Vector3.new(10, 1.8, 0.4), cf * CFrame.new(0, 11.8, 4.2), C.brass, Enum.Material.Metal)
	label(sign, Enum.NormalId.Back, "STORAGE VAULT", Color3.new(1, 1, 1))
	light(window, C.magic, 10, 0.8)
	attach(base, "IngotIn", Vector3.new(0, 10, 0))
	return m
end

-- A forge station: furnace hearth + anvil + quench tank on one platform.
local function buildForge(parent: Instance, cf: CFrame, index: number, accent: Color3, padId: string?): Model
	local m = model(parent, "Forge" .. index)
	m:SetAttribute("ForgeIndex", index)
	if padId then
		m:SetAttribute("PadId", padId)
	end
	local base = part(m, "Base", Vector3.new(11, 1, 9), cf * CFrame.new(0, 0.5, 0), C.stoneDark, Enum.Material.Concrete)
	m.PrimaryPart = base
	part(m, "Trim", Vector3.new(11.4, 0.4, 9.4), cf * CFrame.new(0, 0.2, 0), accent, Enum.Material.Neon)
	prompt(base, Vector3.new(0, 3, 5.2))
	-- Furnace hearth (back).
	local hearth = part(m, "Hearth", Vector3.new(5, 4.5, 3.5), cf * CFrame.new(-2.5, 3.25, -2.4), rgb(120, 110, 120), Enum.Material.Cobblestone)
	local fire = part(m, "FireMouth", Vector3.new(3.2, 2, 0.3), cf * CFrame.new(-2.5, 2.6, -0.55), C.ember, Enum.Material.Neon)
	light(fire, C.ember, 16, 2.5)
	make("Fire", { Name = "Fire", Heat = 5, Size = 3, Color = C.ember, SecondaryColor = C.emberHot }, attach(fire, "FireAttachment", Vector3.new(0, -0.4, 0.3)))
	cyl(m, "Stack", 1.6, 5, cf * CFrame.new(-2.5, 7.8, -3), rgb(120, 110, 120), Enum.Material.Slate)
	-- Anvil (front right).
	cyl(m, "Stump", 2.6, 2.2, cf * CFrame.new(2.2, 2.1, 1.2), C.woodDark, Enum.Material.Wood)
	part(m, "Waist", Vector3.new(1.4, 0.9, 1), cf * CFrame.new(2.2, 3.6, 1.2), C.iron, Enum.Material.Metal)
	local face = part(m, "Anvil", Vector3.new(3.4, 0.8, 1.6), cf * CFrame.new(2.4, 4.4, 1.2), C.iron, Enum.Material.Metal)
	wedge(m, "Horn", Vector3.new(1.6, 0.8, 1.6), cf * CFrame.new(0, 4.4, 1.2) * CFrame.Angles(0, math.rad(-90), 0), C.iron, Enum.Material.Metal)
	-- Weapons rest just above the anvil face (owner feedback: previews were too high).
	attach(face, "WeaponSpot", Vector3.new(0, 1.1, 0))
	attach(face, "SparkSpot", Vector3.new(0, 0.5, 0))
	-- Quench tank (right).
	local tank = part(m, "Tank", Vector3.new(2.6, 1.8, 3.6), cf * CFrame.new(4.2, 1.9, -2.4), C.woodDark, Enum.Material.WoodPlanks)
	part(m, "QuenchWater", Vector3.new(2.1, 0.2, 3.1), cf * CFrame.new(4.2, 2.75, -2.4), C.water, Enum.Material.Glass, { Transparency = 0.2 })
	attach(tank, "SteamSpot", Vector3.new(0, 1.2, 0))
	-- Status board above the station (client draws the countdown here).
	local board = part(m, "StatusBoard", Vector3.new(8, 2.2, 0.3), cf * CFrame.new(0, 9.6, -3.6), accent, Enum.Material.SmoothPlastic)
	label(board, Enum.NormalId.Back, "FORGE " .. index, Color3.new(1, 1, 1))
	attach(base, "StatusSpot", Vector3.new(0, 11, 0))
	hearth.Name = "Hearth"
	return m
end

local function buildPodium(parent: Instance, cf: CFrame, slot: number, accent: Color3, padId: string?): Model
	local m = model(parent, "Pedestal" .. slot)
	m:SetAttribute("Slot", slot)
	if padId then
		m:SetAttribute("PadId", padId)
	end
	local base = part(m, "Base", Vector3.new(4.6, 1, 4.6), cf * CFrame.new(0, 0.5, 0), C.stoneDark, Enum.Material.Marble)
	m.PrimaryPart = base
	cyl(m, "Column", 2.8, 2.6, cf * CFrame.new(0, 2.3, 0), C.wall, Enum.Material.Marble)
	local top = part(m, "Top", Vector3.new(3.8, 0.6, 3.8), cf * CFrame.new(0, 3.9, 0), accent, Enum.Material.Neon)
	attach(top, "DisplaySpot", Vector3.new(0, 2.4, 0))
	return m
end

local function buildPad(parent: Instance, cf: CFrame, padId: string, size: Vector2?): Part
	local s = size or Vector2.new(6, 6)
	local pad = part(parent, "Pad_" .. padId, Vector3.new(s.X, 0.4, s.Y), cf * CFrame.new(0, 1.2, 0), C.pad, Enum.Material.Neon, { CanCollide = false, Transparency = 0.15 })
	pad:SetAttribute("PadId", padId)
	attach(pad, "PromptPoint", Vector3.new(0, 2, 0))
	attach(pad, "LabelSpot", Vector3.new(0, 4, 0))
	return pad
end

-- Decorations a decor pad reveals.
local function buildDecor(parent: Instance, plot: CFrame, padId: string, accent: Color3)
	local m = model(parent, "Decor_" .. padId)
	m:SetAttribute("PadId", padId)
	if padId == "decor_banners" then
		for _, x in { -30.4, 30.4 } do
			for _, z in { -18, 0 } do
				local banner = part(m, "Banner", Vector3.new(0.3, 8, 4), plot * CFrame.new(x, 9, z), accent, Enum.Material.Fabric)
				part(m, "Rod", Vector3.new(0.6, 0.4, 5), plot * CFrame.new(x, 13.2, z), C.brass, Enum.Material.Metal)
				banner.Name = "Banner"
			end
		end
	elseif padId == "decor_fountain" then
		local cf = plot * CFrame.new(-10, 1, 17)
		cyl(m, "Basin", 7, 1.4, cf * CFrame.new(0, 0.7, 0), C.stone, Enum.Material.Marble)
		local lava = cyl(m, "Lava", 6, 0.3, cf * CFrame.new(0, 1.45, 0), C.ember, Enum.Material.Neon)
		light(lava, C.ember, 18, 2)
		cyl(m, "Spout", 1.2, 4, cf * CFrame.new(0, 3, 0), C.brass, Enum.Material.Metal)
		make("ParticleEmitter", { Name = "Sparks", Rate = 18, Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(8, 12), SpreadAngle = Vector2.new(25, 25), LightEmission = 1, Size = NumberSequence.new(0.5, 0), Color = ColorSequence.new(C.emberHot, C.ember), Acceleration = Vector3.new(0, -30, 0) }, attach(lava, "Jet", Vector3.new(0, 4, 0)))
	elseif padId == "decor_statue" then
		local cf = plot * CFrame.new(10, 1, 17)
		part(m, "Plinth", Vector3.new(5, 2, 5), cf * CFrame.new(0, 1, 0), C.stoneDark, Enum.Material.Marble)
		local face = part(m, "GoldAnvil", Vector3.new(4.6, 1.4, 2.2), cf * CFrame.new(0, 4.4, 0), C.brass, Enum.Material.Foil)
		part(m, "GoldWaist", Vector3.new(2, 1.6, 1.4), cf * CFrame.new(0, 3, 0), C.brass, Enum.Material.Foil)
		light(face, C.brass, 14, 1.5)
	elseif padId == "decor_crystals" then
		for i, offset in { Vector3.new(-28, 1, -28), Vector3.new(28, 1, -28), Vector3.new(-28, 1, 4), Vector3.new(28, 1, 4) } do
			local color = if i % 2 == 0 then C.magic else C.purple
			local crystal = part(m, "Crystal", Vector3.new(2, 7, 2), plot * CFrame.new(offset + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0.2, i, 0.15), color, Enum.Material.Neon, { Transparency = 0.15 })
			light(crystal, color, 14, 1.2)
		end
	elseif padId == "decor_portal" then
		local cf = plot * CFrame.new(4, 1, -13)
		for _, x in { -4, 4 } do
			part(m, "PortalPost", Vector3.new(1.4, 10, 1.4), cf * CFrame.new(x, 5, 0), C.purple, Enum.Material.Neon)
		end
		part(m, "PortalTop", Vector3.new(9.4, 1.4, 1.4), cf * CFrame.new(0, 10.7, 0), C.purple, Enum.Material.Neon)
		local swirl = part(m, "Swirl", Vector3.new(6.6, 9, 0.3), cf * CFrame.new(0, 5.5, 0), C.pink, Enum.Material.Neon, { Transparency = 0.45, CanCollide = false })
		light(swirl, C.pink, 18, 2)
	end
	return m
end

local function buildToolRack(parent: Instance, cf: CFrame): Model
	local m = model(parent, "ToolRack")
	local base = part(m, "Base", Vector3.new(7, 1, 4), cf * CFrame.new(0, 0.5, 0), C.stoneDark, Enum.Material.Concrete)
	m.PrimaryPart = base
	prompt(base, Vector3.new(0, 3, 3))
	part(m, "Board", Vector3.new(6, 5, 0.5), cf * CFrame.new(0, 4, -1.2), C.wood, Enum.Material.WoodPlanks)
	for i, col in { C.steel, C.brass, C.magic } do
		local x = -2 + (i - 1) * 2
		part(m, "Handle", Vector3.new(0.35, 3, 0.35), cf * CFrame.new(x, 3.8, -0.8), C.woodDark, Enum.Material.Wood)
		part(m, "Head", Vector3.new(1.3, 0.8, 0.7), cf * CFrame.new(x, 5.4, -0.8), col, Enum.Material.Metal)
	end
	local sign = part(m, "Sign", Vector3.new(6, 1.4, 0.4), cf * CFrame.new(0, 7.2, -1.2), C.brass, Enum.Material.Metal)
	label(sign, Enum.NormalId.Back, "TOOLS", Color3.new(1, 1, 1))
	return m
end

--------------------------------------------------------------------------------
-- Plots
--------------------------------------------------------------------------------

-- Podium slots, in unlock order (slots 1-2 are free; each podium pad adds the next pair).
local PODIUMS = {
	{ slot = 1, at = Vector3.new(-26, 0, 26) },
	{ slot = 2, at = Vector3.new(26, 0, 26) },
	{ slot = 3, at = Vector3.new(-26, 0, 19), pad = "podiums_1" },
	{ slot = 4, at = Vector3.new(26, 0, 19), pad = "podiums_1" },
	{ slot = 5, at = Vector3.new(-26, 0, 12), pad = "podiums_2" },
	{ slot = 6, at = Vector3.new(26, 0, 12), pad = "podiums_2" },
	{ slot = 7, at = Vector3.new(-26, 0, 5), pad = "podiums_3" },
	{ slot = 8, at = Vector3.new(26, 0, 5), pad = "podiums_3" },
}

-- Where each build pad sits (on the spot its building appears, so the reveal reads clearly).
local PAD_SPOTS: { [string]: { at: Vector3, size: Vector2? } } = {
	podiums_1 = { at = Vector3.new(-21, 0, 19), size = Vector2.new(4, 4) },
	podiums_2 = { at = Vector3.new(-21, 0, 12.5), size = Vector2.new(4, 4) },
	podiums_3 = { at = Vector3.new(-22, 0, 8), size = Vector2.new(4, 4) },
	forge_2 = { at = Vector3.new(-14, 0, 1), size = Vector2.new(8, 7) },
	forge_3 = { at = Vector3.new(14, 0, 1), size = Vector2.new(8, 7) },
	line_2 = { at = Vector3.new(24, 0, -8), size = Vector2.new(7, 7) },
	line_3 = { at = Vector3.new(-8, 0, -9), size = Vector2.new(7, 7) },
	decor_banners = { at = Vector3.new(4, 0, 22), size = Vector2.new(4, 4) },
	decor_fountain = { at = Vector3.new(-10, 0, 17), size = Vector2.new(5, 5) },
	decor_statue = { at = Vector3.new(10, 0, 17), size = Vector2.new(5, 5) },
	decor_crystals = { at = Vector3.new(-4, 0, 22), size = Vector2.new(4, 4) },
	decor_portal = { at = Vector3.new(4, 0, -13), size = Vector2.new(5, 5) },
}
WorldBuilder.PAD_SPOTS = PAD_SPOTS

local function buildPlot(parent: Instance, index: number, cf: CFrame): Model
	local accent = PLOT_COLORS[index]
	local plot = model(parent, "Plot" .. index)
	plot:SetAttribute("PlotIndex", index)
	plot:SetAttribute("OwnerUserId", 0)
	plot:SetAttribute("Accent", accent)
	local function P(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	local floor = part(plot, "Floor", Vector3.new(PLOT_SIZE, 1, PLOT_SIZE), P(0, 0.5, 0), rgb(214, 190, 150), Enum.Material.WoodPlanks)
	plot.PrimaryPart = floor
	part(plot, "Border", Vector3.new(PLOT_SIZE + 3, 0.8, PLOT_SIZE + 3), P(0, 0.4, 0), accent, Enum.Material.SmoothPlastic)
	-- Invisible region used by the server for "inside this workshop" checks.
	local bounds = part(plot, "Bounds", Vector3.new(PLOT_SIZE + 1, 40, PLOT_SIZE + 1), P(0, 20, 0), accent, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	bounds.Name = "Bounds"

	-- Low walls with a wide entrance facing the hub (+Z).
	local wallH = 5
	part(plot, "BackWall", Vector3.new(PLOT_SIZE, wallH, 1.6), P(0, wallH / 2 + 1, -HALF + 0.8), C.wall, Enum.Material.Brick)
	for _, x in { -1, 1 } do
		part(plot, "SideWall", Vector3.new(1.6, wallH, PLOT_SIZE), P(x * (HALF - 0.8), wallH / 2 + 1, 0), C.wall, Enum.Material.Brick)
		part(plot, "FrontWall", Vector3.new(HALF - 8, wallH, 1.6), P(x * (HALF + 8) / 2, wallH / 2 + 1, HALF - 0.8), C.wall, Enum.Material.Brick)
		part(plot, "WallCap", Vector3.new(1.9, 0.6, PLOT_SIZE), P(x * (HALF - 0.8), wallH + 1.3, 0), accent, Enum.Material.SmoothPlastic)
		local post = part(plot, "GatePost", Vector3.new(2.4, 12, 2.4), P(x * 9.2, 7, HALF - 0.8), accent, Enum.Material.SmoothPlastic)
		local cap = ball(plot, "GateLight", 2.6, P(x * 9.2, 13.6, HALF - 0.8), C.emberHot, Enum.Material.Neon)
		light(cap, C.emberHot, 18, 1.2)
		post.Name = "GatePost"
	end
	part(plot, "BackWallCap", Vector3.new(PLOT_SIZE, 0.6, 1.9), P(0, wallH + 1.3, -HALF + 0.8), accent, Enum.Material.SmoothPlastic)

	-- Owner sign over the entrance. It faces the hub (+Z = the part's Back face).
	local signBoard = part(plot, "SignBoard", Vector3.new(20, 3.6, 0.8), P(0, 15.6, HALF - 0.8), accent, Enum.Material.SmoothPlastic)
	outline(signBoard, Color3.new(1, 1, 1))
	local gui = make("SurfaceGui", { Name = "OwnerGui", Face = Enum.NormalId.Back, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 30, LightInfluence = 0, Brightness = 1.3 }, signBoard)
	local ownerText = make("TextLabel", { Name = "OwnerText", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "Free Workshop", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = Color3.new(1, 1, 1) }, gui)
	make("UIStroke", { Color = rgb(30, 20, 40), Thickness = 4 }, ownerText)
	part(plot, "ArchBeam", Vector3.new(20, 1.2, 1.2), P(0, 13.2, HALF - 0.8), C.woodDark, Enum.Material.Wood)

	-- Laser gate: invisible until the owner locks the forge (client shows them).
	local lasers = make("Folder", { Name = "Lasers" }, plot)
	for i = 0, 4 do
		local laser = part(lasers, "Laser", Vector3.new(16.4, 0.35, 0.35), P(0, 2 + i * 2.3, HALF - 0.8), C.laser, Enum.Material.Neon, { Transparency = 1, CanCollide = false, CanQuery = false })
		laser.Name = "Laser"
	end
	-- Lasers also run along the wall tops so the whole workshop reads as sealed.
	for _, x in { -1, 1 } do
		part(lasers, "Laser", Vector3.new(0.35, 0.35, PLOT_SIZE), P(x * (HALF - 0.8), wallH + 2.6, 0), C.laser, Enum.Material.Neon, { Transparency = 1, CanCollide = false, CanQuery = false })
	end
	part(lasers, "Laser", Vector3.new(PLOT_SIZE, 0.35, 0.35), P(0, wallH + 2.6, -HALF + 0.8), C.laser, Enum.Material.Neon, { Transparency = 1, CanCollide = false, CanQuery = false })
	local eject = part(plot, "EjectPoint", Vector3.new(4, 1, 4), P(0, 1.5, HALF + 7), accent, Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	eject.Name = "EjectPoint"

	-- Lock button (owner) inside the entrance, right; cash collector, left.
	local lockBase = part(plot, "LockButton", Vector3.new(4, 1.2, 4), P(13, 1.6, 26), rgb(60, 60, 70), Enum.Material.Metal)
	local lockTop = cyl(plot, "LockCap", 3, 0.8, P(13, 2.6, 26), C.laser, Enum.Material.Neon)
	lockTop.Name = "LockCap"
	attach(lockBase, "PromptPoint", Vector3.new(0, 2.5, 0))
	local lockSign = part(plot, "LockSign", Vector3.new(5, 1.4, 0.3), P(13, 5.2, 24), rgb(40, 40, 50), Enum.Material.SmoothPlastic)
	label(lockSign, Enum.NormalId.Back, "LOCK", C.laser, Color3.new(1, 1, 1))
	part(plot, "LockSignPost", Vector3.new(0.4, 3.6, 0.4), P(13, 2.8, 24), C.iron, Enum.Material.Metal)

	local collector = part(plot, "Collector", Vector3.new(6, 0.6, 6), P(-13, 1.3, 26), C.cash, Enum.Material.Neon, { Transparency = 0.1 })
	attach(collector, "PromptPoint", Vector3.new(0, 2, 0))
	attach(collector, "LabelSpot", Vector3.new(0, 4.5, 0))
	outline(collector, Color3.new(1, 1, 1))

	local machines = make("Folder", { Name = "Machines" }, plot)
	-- Storage vault at the back center; lines feed it from both sides.
	buildVault(machines, P(0, 1, -26))
	buildLine(machines, cf, 1, Vector3.new(-24, 1, -8), Vector3.new(-24, 1, -24), Vector3.new(-7, 1, -24), accent, nil)
	buildLine(machines, cf, 2, Vector3.new(24, 1, -8), Vector3.new(24, 1, -24), Vector3.new(7, 1, -24), accent, "line_2")
	buildLine(machines, cf, 3, Vector3.new(-8, 1, -9), Vector3.new(-10, 1, -17), Vector3.new(-3, 1, -20.5), accent, "line_3")
	-- Forges in a row in front of the production area.
	buildForge(machines, P(0, 1, 1), 1, accent, nil)
	buildForge(machines, P(-14, 1, 1), 2, accent, "forge_2")
	buildForge(machines, P(14, 1, 1), 3, accent, "forge_3")
	buildToolRack(machines, P(14, 1, -14))

	local showcase = make("Folder", { Name = "Showcase" }, plot)
	for _, spec in PODIUMS do
		buildPodium(showcase, cf * CFrame.new(spec.at + Vector3.new(0, 1, 0)), spec.slot, accent, spec.pad)
	end

	local pads = make("Folder", { Name = "BuildPads" }, plot)
	for padId, spot in PAD_SPOTS do
		buildPad(pads, cf * CFrame.new(spot.at), padId, spot.size)
	end

	local decor = make("Folder", { Name = "Decor" }, plot)
	for _, padId in { "decor_banners", "decor_fountain", "decor_statue", "decor_crystals", "decor_portal" } do
		buildDecor(decor, cf, padId, accent)
	end
	crate(decor, P(-28, 1, -29), 3)
	crate(decor, P(28, 1, -29), 3)

	local spawnPart = part(plot, "PlotSpawn", Vector3.new(4, 0.2, 4), P(0, 1.1, 14), C.stone, Enum.Material.Slate, { Transparency = 1, CanCollide = false })
	spawnPart:SetAttribute("Spawn", true)
	-- Companions idle here (client renders equipped pets near the owner).
	attach(floor, "PetHome", Vector3.new(-6, 2, 12))
	return plot
end

--------------------------------------------------------------------------------
-- Hub
--------------------------------------------------------------------------------

local function buildBoard(parent: Instance, name: string, metric: string, title: string, cf: CFrame, color: Color3)
	local m = model(parent, name)
	m:SetAttribute("Metric", metric)
	for _, x in { -5.5, 5.5 } do
		part(m, "Post", Vector3.new(1.2, 15, 1.2), cf * CFrame.new(x, 7.5, 0), C.woodDark, Enum.Material.Wood)
	end
	local screen = part(m, "Screen", Vector3.new(10, 10, 0.6), cf * CFrame.new(0, 9, 0), rgb(34, 28, 44), Enum.Material.SmoothPlastic)
	m.PrimaryPart = screen
	local header = part(m, "Header", Vector3.new(12, 2.4, 1), cf * CFrame.new(0, 15.2, 0), color, Enum.Material.SmoothPlastic)
	label(header, Enum.NormalId.Front, title, Color3.new(1, 1, 1))
	part(m, "Footer", Vector3.new(11, 0.8, 1), cf * CFrame.new(0, 3.6, 0), color, Enum.Material.SmoothPlastic)
	return m
end

local function buildEggStand(parent: Instance, eggId: string, title: string, color: Color3, cf: CFrame)
	local m = model(parent, "Egg_" .. eggId)
	m:SetAttribute("EggId", eggId)
	local base = part(m, "Base", Vector3.new(4.6, 1.2, 4.6), cf * CFrame.new(0, 0.6, 0), C.stoneDark, Enum.Material.Marble)
	m.PrimaryPart = base
	cyl(m, "Plinth", 3.8, 1.6, cf * CFrame.new(0, 2, 0), C.wall, Enum.Material.Marble)
	local egg = part(m, "Egg", Vector3.new(3.2, 4.2, 3.2), cf * CFrame.new(0, 5, 0), color, Enum.Material.SmoothPlastic)
	egg.Shape = Enum.PartType.Ball
	local glow = make("Highlight", { FillTransparency = 0.75, OutlineColor = Color3.new(1, 1, 1), FillColor = color }, egg)
	glow.Name = "Glow"
	light(egg, color, 12, 1.2)
	attach(base, "PromptPoint", Vector3.new(0, 3, 2.6))
	local sign = part(m, "Sign", Vector3.new(4.6, 1.2, 0.3), cf * CFrame.new(0, 1.4, 2.45), color, Enum.Material.SmoothPlastic)
	label(sign, Enum.NormalId.Back, title, Color3.new(1, 1, 1))
	return m
end

local function buildSellBooth(hub: Instance)
	local m = model(hub, "SellBooth")
	local center = CFrame.new(0, 0, 0)
	local base = cyl(m, "Base", 22, 1.6, center * CFrame.new(0, 1.3, 0), C.cash, Enum.Material.SmoothPlastic)
	m.PrimaryPart = base
	cyl(m, "Ring", 23.5, 1, center * CFrame.new(0, 0.9, 0), C.brass, Enum.Material.Neon)
	local counter = cyl(m, "Counter", 13, 3.6, center * CFrame.new(0, 3.9, 0), rgb(255, 250, 235), Enum.Material.SmoothPlastic)
	cyl(m, "CounterTop", 14, 0.6, center * CFrame.new(0, 6, 0), C.brass, Enum.Material.Metal)
	-- Merchant: a friendly chunky shopkeeper made of parts.
	part(m, "MerchantBody", Vector3.new(3, 3.6, 2), center * CFrame.new(0, 8.1, 0), rgb(80, 140, 255), Enum.Material.SmoothPlastic)
	ball(m, "MerchantHead", 2.6, center * CFrame.new(0, 11.2, 0), rgb(255, 214, 170), Enum.Material.SmoothPlastic)
	part(m, "MerchantHat", Vector3.new(3, 1.2, 3), center * CFrame.new(0, 12.6, 0), C.cash, Enum.Material.SmoothPlastic)
	-- Canopy and a giant spinning dollar sign.
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		part(m, "Pillar", Vector3.new(1.2, 13, 1.2), center * CFrame.Angles(0, a, 0) * CFrame.new(0, 7.5, 9.5), C.brass, Enum.Material.Metal)
	end
	local roof = cyl(m, "Roof", 24, 1.2, center * CFrame.new(0, 14.6, 0), C.cash, Enum.Material.SmoothPlastic)
	outline(roof, Color3.new(1, 1, 1))
	local sign = part(m, "DollarSign", Vector3.new(6, 6, 1), center * CFrame.new(0, 19.6, 0), C.brass, Enum.Material.Neon, { CanCollide = false })
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		label(sign, face, "$", Color3.new(1, 1, 1), rgb(30, 110, 30))
	end
	light(sign, C.brass, 30, 2)
	for i = 0, 3 do
		local a = math.rad(i * 90)
		local banner = part(m, "SellBanner", Vector3.new(12, 2.6, 0.4), center * CFrame.Angles(0, a, 0) * CFrame.new(0, 16.2, 12.1), C.cash, Enum.Material.SmoothPlastic)
		label(banner, Enum.NormalId.Back, "SELL HERE", Color3.new(1, 1, 1), rgb(20, 80, 20))
	end
	-- Prompts on all four sides so the booth is reachable from every workshop.
	for i = 0, 3 do
		local a = math.rad(i * 90)
		local spot = part(m, "Window", Vector3.new(4, 0.2, 2), center * CFrame.Angles(0, a, 0) * CFrame.new(0, 2.2, 7.6), C.cash, Enum.Material.Neon, { Transparency = 0.3, CanCollide = false })
		attach(spot, "PromptPoint", Vector3.new(0, 2.5, 0))
	end
	counter.Name = "Counter"
end

local function buildHub(world: Instance)
	local hub = model(world, "Hub")
	local R = WorldBuilder.PLAZA_RADIUS
	cyl(hub, "Plaza", R * 2, 1, CFrame.new(0, 0.5, 0), C.plaza, Enum.Material.Pavement)
	cyl(hub, "PlazaRing", R * 2 + 3, 0.8, CFrame.new(0, 0.4, 0), C.plazaTile, Enum.Material.SmoothPlastic)
	-- Bright sunburst tiles.
	for i = 0, 11 do
		local a = math.rad(i * 30)
		local color = PLOT_COLORS[(i % 6) + 1]
		part(hub, "Tile", Vector3.new(4, 0.12, R - 14), CFrame.Angles(0, a, 0) * CFrame.new(0, 1.04, -(R - 14) / 2 - 12), color, Enum.Material.SmoothPlastic)
	end
	buildSellBooth(hub)

	-- Leaderboards on the north-west arc, facing the booth.
	local hall = make("Folder", { Name = "HallOfBlacksmiths" }, hub)
	local boards = {
		{ "Board_Wealth", "lifetimeCoins", "RICHEST", rgb(70, 200, 90) },
		{ "Board_Forged", "weaponsForged", "MOST FORGED", rgb(255, 150, 40) },
		{ "Board_Evolutions", "evolutionRank", "EVOLUTIONS", rgb(170, 90, 255) },
		{ "Board_Highest", "highestWeaponValue", "BEST WEAPON", rgb(255, 80, 120) },
	}
	for i, b in boards do
		local angle = math.rad(-54 + (i - 1) * 18)
		local cf = CFrame.Angles(0, angle, 0) * CFrame.new(0, 1, -(R - 5))
		cf = CFrame.lookAt(cf.Position, Vector3.new(0, 1, 0))
		buildBoard(hall, b[1], b[2], b[3], cf, b[4])
	end

	-- Hatchery: an arc of egg stands on the east side.
	local hatch = make("Folder", { Name = "Hatchery" }, hub)
	local eggs = {
		{ "hearth", "HEARTH", rgb(255, 150, 80) },
		{ "ember", "EMBER", rgb(255, 90, 30) },
		{ "rune", "RUNE", rgb(60, 220, 220) },
		{ "storm", "STORM", rgb(100, 130, 255) },
		{ "astral", "ASTRAL", rgb(170, 110, 255) },
		{ "primordial", "PRIMORDIAL", rgb(255, 230, 150) },
	}
	for i, e in eggs do
		local angle = math.rad(60 + (i - 1) * 12)
		local cf = CFrame.Angles(0, angle, 0) * CFrame.new(0, 1, -(R - 7))
		cf = CFrame.lookAt(cf.Position, Vector3.new(0, 1, 0))
		buildEggStand(hatch, e[1], e[2], e[3], cf)
	end
	local archCf = CFrame.lookAt((CFrame.Angles(0, math.rad(90), 0) * CFrame.new(0, 0, -(R - 2))).Position, Vector3.new(0, 0, 0))
	local arch = part(hatch, "HatcherySign", Vector3.new(18, 3, 0.6), archCf * CFrame.new(0, 12, 0), rgb(255, 120, 200), Enum.Material.SmoothPlastic)
	label(arch, Enum.NormalId.Front, "PET EGGS", Color3.new(1, 1, 1))
	for _, x in { -9.5, 9.5 } do
		part(hatch, "ArchPost", Vector3.new(1.4, 13, 1.4), archCf * CFrame.new(x, 6.5, 0), rgb(255, 120, 200), Enum.Material.SmoothPlastic)
	end

	-- Evolution altar to the south-east.
	local evo = model(hub, "EvolutionAltar")
	local evoCf = CFrame.lookAt((CFrame.Angles(0, math.rad(150), 0) * CFrame.new(0, 0, -(R - 9))).Position, Vector3.new(0, 0, 0))
	local evoBase = part(evo, "Base", Vector3.new(12, 1.4, 12), evoCf * CFrame.new(0, 1, 0), C.stoneDark, Enum.Material.Marble)
	evo.PrimaryPart = evoBase
	for i = 0, 5 do
		local a = math.rad(i * 60)
		part(evo, "Pillar", Vector3.new(1.2, 6 + (i % 2) * 2, 1.2), evoCf * CFrame.Angles(0, a, 0) * CFrame.new(0, 4.5, 5), C.purple, Enum.Material.Neon)
	end
	local core = ball(evo, "Core", 4, evoCf * CFrame.new(0, 7, 0), rgb(190, 110, 255), Enum.Material.Neon)
	light(core, rgb(190, 110, 255), 24, 2)
	make("ParticleEmitter", { Name = "Motes", Rate = 10, Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(1, 2), SpreadAngle = Vector2.new(180, 180), LightEmission = 1, Size = NumberSequence.new(0.5, 0), Color = ColorSequence.new(rgb(220, 160, 255)) }, core)
	attach(evoBase, "PromptPoint", Vector3.new(0, 3, 6.5))
	local evoSign = part(evo, "Sign", Vector3.new(12, 2.4, 0.6), evoCf * CFrame.new(0, 12, 0), C.purple, Enum.Material.SmoothPlastic)
	label(evoSign, Enum.NormalId.Front, "EVOLVE", Color3.new(1, 1, 1))

	-- Premium/test shop stall to the south-west.
	local shop = model(hub, "MerchantStall")
	local shopCf = CFrame.lookAt((CFrame.Angles(0, math.rad(210), 0) * CFrame.new(0, 0, -(R - 8))).Position, Vector3.new(0, 0, 0))
	local counter = part(shop, "Counter", Vector3.new(11, 3.5, 3), shopCf * CFrame.new(0, 2.75, 0), C.wood, Enum.Material.WoodPlanks)
	shop.PrimaryPart = counter
	for _, x in { -5, 5 } do
		part(shop, "Post", Vector3.new(0.8, 10, 0.8), shopCf * CFrame.new(x, 5, -1), C.woodDark, Enum.Material.Wood)
	end
	part(shop, "Awning", Vector3.new(13, 0.4, 6), shopCf * CFrame.new(0, 10.2, 0) * CFrame.Angles(math.rad(-12), 0, 0), rgb(255, 80, 120), Enum.Material.Fabric)
	local shopSign = part(shop, "Sign", Vector3.new(9, 1.8, 0.4), shopCf * CFrame.new(0, 8.4, -1.6), C.brass, Enum.Material.Metal)
	label(shopSign, Enum.NormalId.Front, "SHOP", Color3.new(1, 1, 1))
	attach(counter, "PromptPoint", Vector3.new(0, 1, 2.5))

	for i = 0, 11 do
		local a = math.rad(i * 30 + 15)
		lamp(hub, CFrame.Angles(0, a, 0) * CFrame.new(0, 1, -(R + 0.5)), PLOT_COLORS[(i % 6) + 1])
	end

	local spawn = make("SpawnLocation", {
		Name = "HubSpawn",
		Size = Vector3.new(8, 1, 8),
		CFrame = CFrame.new(0, 1.2, 22),
		Anchored = true,
		Neutral = true,
		Duration = 0,
		Material = Enum.Material.SmoothPlastic,
		Color = C.plazaTile,
		Transparency = 0.6,
		CanCollide = false,
		TopSurface = Enum.SurfaceType.Smooth,
	}, hub)
	spawn:SetAttribute("Hub", true)
end

--------------------------------------------------------------------------------

local function buildBoundary(world: Instance)
	local folder = make("Folder", { Name = "Boundary" }, world)
	local segments = 36
	local r = WorldBuilder.BOUNDARY_RADIUS
	local width = 2 * math.pi * r / segments + 2
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local pos = Vector3.new(math.sin(a) * r, 30, math.cos(a) * r)
		part(folder, "Wall", Vector3.new(width, 60, 2), CFrame.lookAt(pos, Vector3.new(0, 30, 0)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CanQuery = false })
	end
	-- A low hedge ring marks the edge so players see where the world ends.
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local pos = Vector3.new(math.sin(a) * (r - 2), 1.5, math.cos(a) * (r - 2))
		part(folder, "Hedge", Vector3.new(width, 3, 3), CFrame.lookAt(pos, Vector3.new(0, 1.5, 0)), C.grassDark, Enum.Material.Grass)
	end
	part(folder, "Ceiling", Vector3.new(r * 2 + 10, 2, r * 2 + 10), CFrame.new(0, 70, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CanQuery = false })
end

local function buildLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 3
	Lighting.Ambient = rgb(110, 100, 120)
	Lighting.OutdoorAmbient = rgb(170, 160, 170)
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
			c:Destroy()
		end
	end
	make("Atmosphere", { Density = 0.25, Offset = 0.1, Color = rgb(200, 230, 255), Decay = rgb(140, 180, 255), Glare = 0.15, Haze = 0.6 }, Lighting)
	make("BloomEffect", { Intensity = 0.35, Size = 20, Threshold = 2.2 }, Lighting)
	make("ColorCorrectionEffect", { Saturation = 0.28, Contrast = 0.08, Brightness = 0.03, TintColor = rgb(255, 250, 245) }, Lighting)
	make("SunRaysEffect", { Intensity = 0.05, Spread = 0.5 }, Lighting)
end

-- Moves the current World into ServerStorage.Backups instead of destroying it.
local function backupExisting()
	local existing = workspace:FindFirstChild("World")
	if not existing then
		return
	end
	local backups = ServerStorage:FindFirstChild("Backups") or make("Folder", { Name = "Backups" }, ServerStorage)
	existing.Name = "World_" .. os.date("!%Y%m%d_%H%M%S")
	existing.Parent = backups
end

function WorldBuilder.build()
	backupExisting()
	for _, name in { "Baseplate", "SpawnLocation" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local world = make("Folder", { Name = "World" }, workspace)
	world:SetAttribute("Version", 2)
	part(world, "Ground", Vector3.new(420, 4, 420), CFrame.new(0, -2, 0), C.grass, Enum.Material.Grass)
	buildHub(world)

	local plots = make("Folder", { Name = "Plots" }, world)
	local paths = make("Folder", { Name = "Paths" }, world)
	for i = 1, WorldBuilder.PLOT_COUNT do
		local angle = math.rad((i - 1) * (360 / WorldBuilder.PLOT_COUNT) + 30)
		local pos = Vector3.new(math.sin(angle) * WorldBuilder.PLOT_RING_RADIUS, 0, math.cos(angle) * WorldBuilder.PLOT_RING_RADIUS)
		-- The plot's +Z (entrance) faces the hub.
		local cf = CFrame.lookAt(pos, Vector3.new(0, 0, 0)) * CFrame.Angles(0, math.rad(180), 0)
		buildPlot(plots, i, cf)
		local inner = WorldBuilder.PLAZA_RADIUS - 2
		local outer = WorldBuilder.PLOT_RING_RADIUS - HALF + 1
		local mid = pos.Unit * ((inner + outer) / 2)
		part(paths, "Path", Vector3.new(16, 0.3, outer - inner), CFrame.lookAt(Vector3.new(mid.X, 0.15, mid.Z), Vector3.new(0, 0.15, 0)), PLOT_COLORS[i], Enum.Material.SmoothPlastic)
	end
	buildBoundary(world)

	-- Scenery between the workshops and around the edge (inside the boundary).
	local scenery = make("Folder", { Name = "Scenery" }, world)
	local rng = Random.new(1919)
	for i = 0, 5 do
		-- Between neighbouring workshops: a lamp near the plaza, a tree out by the hedge.
		local a = math.rad(i * 60)
		local p = Vector3.new(math.sin(a), 0, math.cos(a))
		lamp(scenery, CFrame.new(p * 46), PLOT_COLORS[i + 1])
		tree(scenery, CFrame.new(p * 122), 1.3, PLOT_COLORS[i + 1]:Lerp(C.grassDark, 0.6))
		rock(scenery, CFrame.new(p * 114 + Vector3.new(4, 0, 0)), 1.4)
	end
	for _ = 1, 40 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(150, 200)
		local cf = CFrame.new(math.sin(a) * r, 0, math.cos(a) * r) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		tree(scenery, cf, rng:NextNumber(1.2, 2), C.grassDark)
	end
	buildLighting()
	return world
end

return WorldBuilder
