--!strict
-- Edit-time world builder. Regenerates Workspace.World (hub, six workshop plots, props) and lighting
-- from source so the place layout lives in Git. Run from Studio:
--   require(game.ServerStorage.Build.WorldBuilder).build()
-- Runtime scripts only read this hierarchy (names/attributes below are the contract).

local Lighting = game:GetService("Lighting")

local WorldBuilder = {}

local PLOT_COUNT = 6
local PLOT_RING_RADIUS = 125
local PLOT_SIZE = 64

local C = {
	grass = Color3.fromRGB(96, 140, 74),
	grassDark = Color3.fromRGB(74, 112, 58),
	stone = Color3.fromRGB(122, 118, 112),
	stoneDark = Color3.fromRGB(78, 74, 72),
	brick = Color3.fromRGB(150, 82, 60),
	wood = Color3.fromRGB(124, 84, 52),
	woodDark = Color3.fromRGB(86, 56, 36),
	iron = Color3.fromRGB(58, 60, 66),
	steel = Color3.fromRGB(150, 156, 166),
	brass = Color3.fromRGB(196, 150, 70),
	ember = Color3.fromRGB(255, 120, 30),
	emberHot = Color3.fromRGB(255, 196, 80),
	magic = Color3.fromRGB(110, 200, 255),
	water = Color3.fromRGB(70, 140, 190),
	path = Color3.fromRGB(170, 150, 118),
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
	return make("WedgePart", {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Anchored = true,
	}, parent)
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

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3?)
	local gui = make("SurfaceGui", {
		Name = "Label",
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0,
	}, p)
	make("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = color or Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.4,
	}, gui)
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

local function barrel(parent: Instance, cf: CFrame)
	local m = model(parent, "Barrel")
	cyl(m, "Body", 2.6, 3.4, cf * CFrame.new(0, 1.7, 0), C.wood, Enum.Material.WoodPlanks)
	for _, y in { 0.5, 2.9 } do
		cyl(m, "Hoop", 2.75, 0.25, cf * CFrame.new(0, y, 0), C.iron, Enum.Material.Metal)
	end
	return m
end

local function lantern(parent: Instance, cf: CFrame, h: number?)
	local height = h or 9
	local m = model(parent, "Lantern")
	cyl(m, "Post", 0.6, height, cf * CFrame.new(0, height / 2, 0), C.iron, Enum.Material.Metal)
	part(m, "Arm", Vector3.new(2.2, 0.3, 0.3), cf * CFrame.new(0.9, height - 0.3, 0), C.iron, Enum.Material.Metal)
	local glow = part(m, "Glow", Vector3.new(1, 1.3, 1), cf * CFrame.new(1.8, height - 1.2, 0), C.emberHot, Enum.Material.Neon)
	part(m, "Cap", Vector3.new(1.4, 0.3, 1.4), cf * CFrame.new(1.8, height - 0.45, 0), C.iron, Enum.Material.Metal)
	light(glow, Color3.fromRGB(255, 190, 120), 18, 1.6)
	return m
end

local function ingotStack(parent: Instance, cf: CFrame, color: Color3)
	local m = model(parent, "IngotStack")
	for row = 0, 1 do
		for i = -1, 1 do
			part(m, "Ingot", Vector3.new(0.9, 0.5, 2), cf * CFrame.new(i * 1, 0.25 + row * 0.5, 0) * CFrame.Angles(0, row * math.rad(90), 0), color, Enum.Material.Metal)
		end
	end
	return m
end

local function tree(parent: Instance, cf: CFrame, s: number)
	local m = model(parent, "Tree")
	cyl(m, "Trunk", 1.6 * s, 7 * s, cf * CFrame.new(0, 3.5 * s, 0), C.woodDark, Enum.Material.Wood)
	ball(m, "Leaves", 8 * s, cf * CFrame.new(0, 8.5 * s, 0), C.grassDark, Enum.Material.Grass)
	ball(m, "Leaves2", 5.5 * s, cf * CFrame.new(1.8 * s, 10.5 * s, 0.8 * s), C.grass, Enum.Material.Grass)
	return m
end

local function rock(parent: Instance, cf: CFrame, s: number)
	local p = part(parent, "Rock", Vector3.new(4, 2.6, 3.2) * s, cf * CFrame.new(0, 1 * s, 0) * CFrame.Angles(0.2, 0.6, 0.15), C.stone, Enum.Material.Slate)
	return p
end

local function toolRack(parent: Instance, cf: CFrame)
	local m = model(parent, "ToolRack")
	part(m, "Board", Vector3.new(6, 4, 0.4), cf * CFrame.new(0, 3.5, 0), C.wood, Enum.Material.WoodPlanks)
	for i, col in { C.steel, C.iron, C.brass } do
		local x = -2 + (i - 1) * 2
		part(m, "Handle", Vector3.new(0.3, 2.6, 0.3), cf * CFrame.new(x, 3.2, -0.4), C.woodDark, Enum.Material.Wood)
		part(m, "Head", Vector3.new(1.2, 0.6, 0.6), cf * CFrame.new(x, 4.6, -0.4), col, Enum.Material.Metal)
	end
	return m
end

--------------------------------------------------------------------------------
-- Machines (local frame: +Z faces the plot entrance)
--------------------------------------------------------------------------------

local function machineBase(m: Model, cf: CFrame, w: number, d: number, color: Color3): Part
	local base = part(m, "Base", Vector3.new(w, 1, d), cf * CFrame.new(0, 0.5, 0), color, Enum.Material.Concrete)
	m.PrimaryPart = base
	return base
end

local function buildExtractor(parent: Instance, cf: CFrame): Model
	local m = model(parent, "Extractor")
	local base = machineBase(m, cf, 11, 11, C.stoneDark)
	attach(base, "PromptPoint", Vector3.new(0, 3, 6))
	-- ore pit
	part(m, "OrePit", Vector3.new(6, 0.4, 6), cf * CFrame.new(0, 1.2, 0), Color3.fromRGB(40, 34, 30), Enum.Material.Slate)
	local ore = part(m, "OreGlow", Vector3.new(3, 1.2, 3), cf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0.5, 0), C.brass, Enum.Material.Neon)
	light(ore, C.emberHot, 10, 0.8)
	-- frame posts
	for _, x in { -4.5, 4.5 } do
		for _, z in { -4.5, 4.5 } do
			part(m, "Post", Vector3.new(0.8, 12, 0.8), cf * CFrame.new(x, 7, z), C.iron, Enum.Material.DiamondPlate)
		end
	end
	part(m, "TopFrame", Vector3.new(10.6, 1, 10.6), cf * CFrame.new(0, 13.3, 0), C.iron, Enum.Material.DiamondPlate)
	-- drill assembly
	local housing = part(m, "DrillHousing", Vector3.new(4, 3, 4), cf * CFrame.new(0, 11, 0), C.brass, Enum.Material.Metal)
	cyl(m, "DrillShaft", 1.2, 6, cf * CFrame.new(0, 7, 0), C.steel, Enum.Material.Metal)
	cyl(m, "DrillBit", 2.2, 1.6, cf * CFrame.new(0, 4, 0), C.steel, Enum.Material.Metal, { Name = "DrillBit" })
	part(m, "DrillTip", Vector3.new(1, 1.6, 1), cf * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, math.rad(45), 0), C.steel, Enum.Material.Metal)
	local gear = cyl(m, "Gear", 5, 0.8, cf * CFrame.new(0, 14.4, 0), C.brass, Enum.Material.Metal)
	gear.Name = "Gear"
	local tierGem = ball(m, "TierGem", 1.6, cf * CFrame.new(0, 15.6, 0), C.magic, Enum.Material.Neon)
	light(tierGem, C.magic, 12, 1)
	label(housing, Enum.NormalId.Back, "EXTRACTOR", C.emberHot)
	-- output chute toward smelter (+X)
	wedge(m, "Chute", Vector3.new(2, 2, 5), cf * CFrame.new(6.5, 2, 0) * CFrame.Angles(0, math.rad(-90), 0), C.iron, Enum.Material.Metal)
	return m
end

local function buildSmelter(parent: Instance, cf: CFrame): Model
	local m = model(parent, "Smelter")
	local base = machineBase(m, cf, 10, 10, C.stoneDark)
	attach(base, "PromptPoint", Vector3.new(0, 3, 6))
	local body = part(m, "Body", Vector3.new(8, 7, 8), cf * CFrame.new(0, 4.5, 0), C.brick, Enum.Material.Brick)
	part(m, "Rim", Vector3.new(8.8, 1, 8.8), cf * CFrame.new(0, 8.4, 0), C.stoneDark, Enum.Material.Slate)
	cyl(m, "Chimney", 2.6, 9, cf * CFrame.new(2, 12.5, 2), C.brick, Enum.Material.Brick)
	cyl(m, "ChimneyCap", 3.2, 0.8, cf * CFrame.new(2, 17.2, 2), C.iron, Enum.Material.Metal)
	local mouth = part(m, "Mouth", Vector3.new(3.6, 2.4, 0.3), cf * CFrame.new(0, 3.6, 4.05), C.ember, Enum.Material.Neon)
	light(mouth, C.ember, 14, 2)
	make("Smoke", { Name = "Smoke", Color = Color3.fromRGB(90, 90, 90), Opacity = 0.15, RiseVelocity = 4, Size = 2.5 }, make("Attachment", { Position = Vector3.new(0, 4.6, 0) }, (m:FindFirstChild("ChimneyCap") :: Part)))
	local crucible = cyl(m, "Crucible", 3, 1.6, cf * CFrame.new(0, 9.4, 0), C.iron, Enum.Material.Metal)
	cyl(m, "Molten", 2.4, 0.3, cf * CFrame.new(0, 10.2, 0), C.emberHot, Enum.Material.Neon)
	label(body, Enum.NormalId.Back, "SMELTER", C.emberHot)
	crucible.Name = "Crucible"
	return m
end

local function buildStorage(parent: Instance, cf: CFrame): Model
	local m = model(parent, "Storage")
	local base = machineBase(m, cf, 10, 8, C.stoneDark)
	attach(base, "PromptPoint", Vector3.new(0, 3, 5))
	for _, x in { -4.4, 4.4 } do
		part(m, "Upright", Vector3.new(0.6, 9, 6), cf * CFrame.new(x, 5.5, 0), C.wood, Enum.Material.WoodPlanks)
	end
	for _, y in { 1.6, 4.8, 8 } do
		part(m, "Shelf", Vector3.new(8.4, 0.4, 6), cf * CFrame.new(0, y, 0), C.wood, Enum.Material.WoodPlanks)
	end
	-- Fill bar: runtime scales its Y size by storage fill fraction.
	local fill = part(m, "Fill", Vector3.new(7.6, 0.01, 4.8), cf * CFrame.new(0, 1.8, 0), C.brass, Enum.Material.Metal)
	fill:SetAttribute("MaxHeight", 9.6)
	local sign = part(m, "Sign", Vector3.new(6, 1.6, 0.3), cf * CFrame.new(0, 10.6, 3), C.woodDark, Enum.Material.Wood)
	label(sign, Enum.NormalId.Back, "STORAGE", C.emberHot)
	return m
end

local function buildFurnace(parent: Instance, cf: CFrame): Model
	local m = model(parent, "Furnace")
	local base = machineBase(m, cf, 10, 10, C.stoneDark)
	attach(base, "PromptPoint", Vector3.new(0, 3, 6))
	local body = part(m, "Body", Vector3.new(8, 6, 7), cf * CFrame.new(0, 4, 0), C.stone, Enum.Material.Cobblestone)
	ball(m, "Dome", 8, cf * CFrame.new(0, 7, 0), C.stone, Enum.Material.Cobblestone)
	cyl(m, "Stack", 2.2, 6, cf * CFrame.new(0, 12, -1), C.stoneDark, Enum.Material.Slate)
	local fire = part(m, "FireMouth", Vector3.new(4, 3, 0.4), cf * CFrame.new(0, 3.5, 3.4), C.ember, Enum.Material.Neon)
	light(fire, C.ember, 18, 3)
	local fireAtt = make("Attachment", { Name = "FireAttachment", Position = Vector3.new(0, -0.6, 0.5) }, fire)
	make("Fire", { Name = "Fire", Heat = 6, Size = 4, Color = C.ember, SecondaryColor = C.emberHot }, fireAtt)
	-- bellows
	wedge(m, "Bellows", Vector3.new(2.4, 1.4, 3.6), cf * CFrame.new(-5.2, 2, 1) * CFrame.Angles(0, math.rad(90), 0), C.woodDark, Enum.Material.Fabric)
	local fsign = part(m, "Sign", Vector3.new(6, 1.6, 0.3), cf * CFrame.new(0, 7.2, 3.9), C.woodDark, Enum.Material.Wood)
	label(fsign, Enum.NormalId.Back, "FURNACE", C.emberHot)
	body.Name = "Body"
	return m
end

local function buildAnvil(parent: Instance, cf: CFrame): Model
	local m = model(parent, "Anvil")
	local base = machineBase(m, cf, 9, 9, C.stoneDark)
	attach(base, "PromptPoint", Vector3.new(0, 3, 5))
	cyl(m, "Stump", 3.6, 3, cf * CFrame.new(0, 2.5, 0), C.woodDark, Enum.Material.Wood)
	part(m, "Foot", Vector3.new(3.6, 0.8, 2.4), cf * CFrame.new(0, 4.4, 0), C.iron, Enum.Material.Metal)
	part(m, "Waist", Vector3.new(2, 1.2, 1.4), cf * CFrame.new(0, 5.4, 0), C.iron, Enum.Material.Metal)
	local face = part(m, "Face", Vector3.new(4.6, 1, 2.2), cf * CFrame.new(0.2, 6.5, 0), C.iron, Enum.Material.Metal)
	wedge(m, "Horn", Vector3.new(2.2, 1, 2.4), cf * CFrame.new(-3.3, 6.5, 0) * CFrame.Angles(0, math.rad(-90), 0), C.iron, Enum.Material.Metal)
	-- Forged weapons appear here during the forge sequence.
	attach(face, "WeaponSpot", Vector3.new(0, 1.2, 0))
	attach(face, "SparkSpot", Vector3.new(0, 0.6, 0))
	-- quench trough beside the anvil
	local trough = part(m, "Trough", Vector3.new(5, 2, 2.6), cf * CFrame.new(5.5, 1.5, 1.5), C.woodDark, Enum.Material.WoodPlanks)
	part(m, "Water", Vector3.new(4.4, 0.2, 2), cf * CFrame.new(5.5, 2.45, 1.5), C.water, Enum.Material.Glass, { Transparency = 0.25 })
	attach(trough, "SteamSpot", Vector3.new(0, 1.4, 0))
	return m
end

local function buildPedestal(parent: Instance, cf: CFrame, slot: number): Model
	local m = model(parent, "Pedestal" .. slot)
	m:SetAttribute("Slot", slot)
	local base = part(m, "Base", Vector3.new(4, 1, 4), cf * CFrame.new(0, 0.5, 0), C.stoneDark, Enum.Material.Marble)
	m.PrimaryPart = base
	cyl(m, "Column", 2.4, 3, cf * CFrame.new(0, 2.5, 0), C.stone, Enum.Material.Marble)
	local top = part(m, "Top", Vector3.new(3.2, 0.5, 3.2), cf * CFrame.new(0, 4.25, 0), C.brass, Enum.Material.Metal)
	attach(top, "DisplaySpot", Vector3.new(0, 2.6, 0))
	return m
end

--------------------------------------------------------------------------------
-- Plots
--------------------------------------------------------------------------------

local function buildPlot(parent: Instance, index: number, cf: CFrame): Model
	local plot = model(parent, "Plot" .. index)
	plot:SetAttribute("PlotIndex", index)
	plot:SetAttribute("OwnerUserId", 0)
	local half = PLOT_SIZE / 2
	local floor = part(plot, "Floor", Vector3.new(PLOT_SIZE, 1, PLOT_SIZE), cf * CFrame.new(0, 0.5, 0), Color3.fromRGB(150, 128, 100), Enum.Material.WoodPlanks)
	plot.PrimaryPart = floor
	part(plot, "Border", Vector3.new(PLOT_SIZE + 2, 0.8, PLOT_SIZE + 2), cf * CFrame.new(0, 0.3, 0), C.stoneDark, Enum.Material.Cobblestone)
	-- back and side walls (low, open front toward hub at +Z)
	part(plot, "BackWall", Vector3.new(PLOT_SIZE, 8, 1.5), cf * CFrame.new(0, 4.5, -half + 0.75), C.brick, Enum.Material.Brick)
	for _, x in { -1, 1 } do
		part(plot, "SideWall", Vector3.new(1.5, 4, PLOT_SIZE - 16), cf * CFrame.new(x * (half - 0.75), 2.5, -8), C.brick, Enum.Material.Brick)
		part(plot, "Pillar", Vector3.new(3, 18, 3), cf * CFrame.new(x * (half - 1.5), 9, half - 1.5), C.stoneDark, Enum.Material.Slate)
		local torch = part(plot, "Torch", Vector3.new(1, 1.4, 1), cf * CFrame.new(x * (half - 1.5), 18.8, half - 1.5), C.emberHot, Enum.Material.Neon)
		light(torch, C.ember, 22, 1.5)
	end
	-- roof beams over the back half
	for i = -2, 2 do
		part(plot, "Beam", Vector3.new(1.2, 1.2, 26), cf * CFrame.new(i * 12, 14, -half + 13), C.woodDark, Enum.Material.Wood)
	end
	part(plot, "Roof", Vector3.new(PLOT_SIZE, 0.6, 26), cf * CFrame.new(0, 14.9, -half + 13), Color3.fromRGB(120, 60, 46), Enum.Material.Slate)
	-- owner sign arch at the entrance
	local signBoard = part(plot, "SignBoard", Vector3.new(22, 3.2, 0.8), cf * CFrame.new(0, 15.4, half - 1.5), C.woodDark, Enum.Material.Wood)
	local gui = make("SurfaceGui", { Name = "OwnerGui", Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 30, LightInfluence = 0 }, signBoard)
	make("TextLabel", { Name = "OwnerText", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "Unclaimed Workshop", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = C.emberHot, TextStrokeTransparency = 0.3 }, gui)
	part(plot, "ArchBeam", Vector3.new(PLOT_SIZE - 2, 1.2, 1.2), cf * CFrame.new(0, 17.6, half - 1.5), C.woodDark, Enum.Material.Wood)

	local machines = make("Folder", { Name = "Machines" }, plot)
	buildExtractor(machines, cf * CFrame.new(-18, 1, -18))
	buildSmelter(machines, cf * CFrame.new(0, 1, -19))
	buildStorage(machines, cf * CFrame.new(18, 1, -19))
	buildFurnace(machines, cf * CFrame.new(-9, 1, 2))
	buildAnvil(machines, cf * CFrame.new(5, 1, 2))
	-- decorative belt linking extractor -> smelter -> storage
	local belt = part(plot, "Belt", Vector3.new(30, 0.6, 2.4), cf * CFrame.new(0, 1.9, -11.5), C.iron, Enum.Material.DiamondPlate)
	attach(belt, "BeltStart", Vector3.new(-15, 0.6, 0))
	attach(belt, "BeltEnd", Vector3.new(15, 0.6, 0))

	local showcase = make("Folder", { Name = "Showcase" }, plot)
	local slot = 0
	for _, x in { -26, 26 } do
		for _, z in { -2, 10, 22 } do
			slot += 1
			buildPedestal(showcase, cf * CFrame.new(x, 1, z) * CFrame.Angles(0, x < 0 and math.rad(-90) or math.rad(90), 0), slot)
		end
	end

	local deco = make("Folder", { Name = "Decor" }, plot)
	toolRack(deco, cf * CFrame.new(-6, 1, -half + 1.8))
	barrel(deco, cf * CFrame.new(-27, 1, -27))
	barrel(deco, cf * CFrame.new(-24, 1, -28))
	crate(deco, cf * CFrame.new(27, 1, -27), 3)
	crate(deco, cf * CFrame.new(27, 4, -27) * CFrame.Angles(0, 0.4, 0), 2)
	ingotStack(deco, cf * CFrame.new(24, 1, -8), C.brass)
	part(deco, "Workbench", Vector3.new(8, 3, 3), cf * CFrame.new(14, 2.5, 4), C.wood, Enum.Material.WoodPlanks)

	local spawnPart = part(plot, "PlotSpawn", Vector3.new(4, 0.2, 4), cf * CFrame.new(0, 1.1, 16), C.stone, Enum.Material.Slate, { Transparency = 1, CanCollide = false })
	spawnPart:SetAttribute("Spawn", true)
	-- Companions idle here (client renders equipped pets near the owner).
	attach(floor, "PetHome", Vector3.new(-14, 2, 10))
	return plot
end

--------------------------------------------------------------------------------
-- Hub
--------------------------------------------------------------------------------

local function buildBoard(parent: Instance, name: string, metric: string, title: string, cf: CFrame)
	local m = model(parent, name)
	m:SetAttribute("Metric", metric)
	for _, x in { -6.5, 6.5 } do
		part(m, "Post", Vector3.new(1.4, 18, 1.4), cf * CFrame.new(x, 9, 0), C.woodDark, Enum.Material.Wood)
	end
	local screen = part(m, "Screen", Vector3.new(12, 13, 0.6), cf * CFrame.new(0, 10.5, 0), Color3.fromRGB(34, 28, 26), Enum.Material.Slate)
	m.PrimaryPart = screen
	local header = part(m, "Header", Vector3.new(14, 2.6, 1), cf * CFrame.new(0, 18.2, 0), C.brass, Enum.Material.Metal)
	label(header, Enum.NormalId.Front, title, Color3.fromRGB(60, 34, 14))
	part(m, "Footer", Vector3.new(13, 1, 1), cf * CFrame.new(0, 3.6, 0), C.brass, Enum.Material.Metal)
	return m
end

local function buildEggStand(parent: Instance, eggId: string, title: string, color: Color3, cf: CFrame)
	local m = model(parent, "Egg_" .. eggId)
	m:SetAttribute("EggId", eggId)
	local base = part(m, "Base", Vector3.new(4.2, 1.2, 4.2), cf * CFrame.new(0, 0.6, 0), C.stoneDark, Enum.Material.Marble)
	m.PrimaryPart = base
	cyl(m, "Plinth", 3.4, 2, cf * CFrame.new(0, 2.2, 0), C.stone, Enum.Material.Marble)
	local egg = part(m, "Egg", Vector3.new(3, 4, 3), cf * CFrame.new(0, 5.4, 0), color, Enum.Material.SmoothPlastic)
	egg.Shape = Enum.PartType.Ball
	local glow = make("Highlight", { FillTransparency = 0.8, OutlineColor = color, FillColor = color }, egg)
	glow.Name = "Glow"
	light(egg, color, 10, 1)
	attach(base, "PromptPoint", Vector3.new(0, 3, 0))
	local sign = part(m, "Sign", Vector3.new(4.2, 1.1, 0.3), cf * CFrame.new(0, 1.6, -2.3), C.woodDark, Enum.Material.Wood)
	label(sign, Enum.NormalId.Front, title, color)
	return m
end

local function buildHub(world: Instance)
	local hub = model(world, "Hub")
	local center = CFrame.new(0, 0, 0)
	cyl(hub, "Plaza", 96, 1, center * CFrame.new(0, 0.5, 0), C.stone, Enum.Material.Cobblestone)
	cyl(hub, "PlazaRing", 100, 0.8, center * CFrame.new(0, 0.35, 0), C.stoneDark, Enum.Material.Slate)
	cyl(hub, "InnerRing", 34, 1.1, center * CFrame.new(0, 0.6, 0), C.path, Enum.Material.Sandstone)

	-- Great Forge centerpiece
	local forge = model(hub, "GreatForge")
	cyl(forge, "Base", 22, 2, center * CFrame.new(0, 1.6, 0), C.stoneDark, Enum.Material.Slate)
	cyl(forge, "Body", 16, 8, center * CFrame.new(0, 6.6, 0), C.brick, Enum.Material.Brick)
	cyl(forge, "Lip", 18, 1.2, center * CFrame.new(0, 11.2, 0), C.iron, Enum.Material.Metal)
	local lava = cyl(forge, "Lava", 14.5, 0.6, center * CFrame.new(0, 11.4, 0), C.ember, Enum.Material.Neon)
	light(lava, C.ember, 40, 3)
	make("Fire", { Heat = 12, Size = 10, Color = C.ember, SecondaryColor = C.emberHot }, make("Attachment", { Position = Vector3.new(0, 0, 0) }, lava))
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local cf = center * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 10)
		part(forge, "Buttress", Vector3.new(2.4, 12, 3), cf * CFrame.new(0, 7, 0), C.iron, Enum.Material.Metal)
		part(forge, "Rune", Vector3.new(1.6, 1.6, 0.3), cf * CFrame.new(0, 7, 1.6), C.magic, Enum.Material.Neon)
	end
	local hammer = model(forge, "GiantHammer")
	part(hammer, "Handle", Vector3.new(1.6, 16, 1.6), center * CFrame.new(0, 21, 0) * CFrame.Angles(0, 0, math.rad(25)), C.woodDark, Enum.Material.Wood)
	part(hammer, "Head", Vector3.new(7, 3.6, 3.6), center * CFrame.new(-3.4, 28.2, 0) * CFrame.Angles(0, 0, math.rad(25)), C.steel, Enum.Material.Metal)
	local title = part(forge, "TitlePlate", Vector3.new(14, 3, 0.6), center * CFrame.new(0, 6, 8.2), C.brass, Enum.Material.Metal)
	label(title, Enum.NormalId.Front, "FORGE FRENZY", Color3.fromRGB(70, 36, 12))

	-- Hall of Blacksmiths (north arc, -Z)
	local hall = make("Folder", { Name = "HallOfBlacksmiths" }, hub)
	local boards = {
		{ "Board_Wealth", "lifetimeCoins", "LIFETIME WEALTH" },
		{ "Board_Forged", "weaponsForged", "WEAPONS FORGED" },
		{ "Board_Evolutions", "evolutionRank", "EVOLUTIONS" },
		{ "Board_Highest", "highestWeaponValue", "BEST WEAPON" },
	}
	for i, b in boards do
		local angle = math.rad(-36 + (i - 1) * 24)
		local cf = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -40)
		cf = CFrame.lookAt(cf.Position, Vector3.new(0, 0, 0))
		buildBoard(hall, b[1], b[2], b[3], cf)
	end

	-- Hatchery (east, +X)
	local hatch = make("Folder", { Name = "Hatchery" }, hub)
	local hatchCenter = CFrame.lookAt(Vector3.new(36, 0, 0), Vector3.new(0, 0, 0))
	part(hatch, "Platform", Vector3.new(32, 1, 12), hatchCenter * CFrame.new(0, 1, -2), C.stoneDark, Enum.Material.Marble)
	local arch = part(hatch, "ArchTop", Vector3.new(34, 2, 2), hatchCenter * CFrame.new(0, 14, -7), C.magic, Enum.Material.Neon, { Transparency = 0.2 })
	light(arch, C.magic, 25, 1)
	for _, x in { -16, 16 } do
		part(hatch, "ArchPost", Vector3.new(2, 14, 2), hatchCenter * CFrame.new(x, 7, -7), C.stone, Enum.Material.Marble)
	end
	local hatchSign = part(hatch, "HatcherySign", Vector3.new(16, 2.6, 0.6), hatchCenter * CFrame.new(0, 11, -7), C.woodDark, Enum.Material.Wood)
	label(hatchSign, Enum.NormalId.Front, "COMPANION HATCHERY", C.magic)
	local eggs = {
		{ "hearth", "Hearth Egg", Color3.fromRGB(200, 120, 70) },
		{ "ember", "Ember Egg", Color3.fromRGB(255, 110, 40) },
		{ "rune", "Rune Egg", Color3.fromRGB(80, 200, 210) },
		{ "storm", "Storm Egg", Color3.fromRGB(110, 130, 255) },
		{ "astral", "Astral Egg", Color3.fromRGB(150, 110, 255) },
		{ "primordial", "Primordial Egg", Color3.fromRGB(255, 240, 200) },
	}
	for i, e in eggs do
		buildEggStand(hatch, e[1], e[2], e[3], hatchCenter * CFrame.new(-11.5 + (i - 1) * 4.6, 1.5, -2))
	end

	-- Evolution altar (west, -X)
	local evo = model(hub, "EvolutionAltar")
	local evoCf = CFrame.lookAt(Vector3.new(-36, 0, 0), Vector3.new(0, 0, 0))
	local evoBase = part(evo, "Base", Vector3.new(14, 1.4, 14), evoCf * CFrame.new(0, 1, 0), C.stoneDark, Enum.Material.Marble)
	evo.PrimaryPart = evoBase
	for i = 0, 5 do
		local a = math.rad(i * 60)
		local p = evoCf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 5.5)
		part(evo, "Pillar", Vector3.new(1.2, 6 + (i % 2) * 2, 1.2), p * CFrame.new(0, 4.5, 0), C.stone, Enum.Material.Marble)
	end
	local core = ball(evo, "Core", 4, evoCf * CFrame.new(0, 7, 0), Color3.fromRGB(190, 110, 255), Enum.Material.Neon)
	light(core, Color3.fromRGB(190, 110, 255), 24, 2)
	make("ParticleEmitter", { Name = "Motes", Rate = 8, Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(1, 2), SpreadAngle = Vector2.new(180, 180), LightEmission = 1, Size = NumberSequence.new(0.4, 0), Color = ColorSequence.new(Color3.fromRGB(220, 160, 255)) }, core)
	attach(evoBase, "PromptPoint", Vector3.new(0, 3, 0))
	local evoSign = part(evo, "Sign", Vector3.new(12, 2.2, 0.6), evoCf * CFrame.new(0, 2.2, -7.2), C.woodDark, Enum.Material.Wood)
	label(evoSign, Enum.NormalId.Front, "BLACKSMITH EVOLUTION", Color3.fromRGB(220, 170, 255))

	-- Merchant stall / shop (south-west, between altar and plots)
	local shop = model(hub, "MerchantStall")
	local shopCf = CFrame.lookAt(Vector3.new(-24, 0, 30), Vector3.new(0, 0, 0))
	local counter = part(shop, "Counter", Vector3.new(12, 3.5, 3), shopCf * CFrame.new(0, 2.75, 0), C.wood, Enum.Material.WoodPlanks)
	shop.PrimaryPart = counter
	for _, x in { -5.5, 5.5 } do
		part(shop, "Post", Vector3.new(0.8, 10, 0.8), shopCf * CFrame.new(x, 5, -1), C.woodDark, Enum.Material.Wood)
	end
	part(shop, "Awning", Vector3.new(14, 0.4, 6), shopCf * CFrame.new(0, 10.2, 0) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(176, 52, 52), Enum.Material.Fabric)
	local shopSign = part(shop, "Sign", Vector3.new(9, 1.8, 0.4), shopCf * CFrame.new(0, 8.4, -1.6), C.brass, Enum.Material.Metal)
	label(shopSign, Enum.NormalId.Front, "MASTER MERCHANT", Color3.fromRGB(70, 36, 12))
	attach(counter, "PromptPoint", Vector3.new(0, 1, -2))
	ingotStack(shop, shopCf * CFrame.new(-3, 4.5, 0), Color3.fromRGB(255, 210, 90))
	crate(shop, shopCf * CFrame.new(7.5, 0, 1), 3)

	-- lanterns around plaza
	for i = 0, 11 do
		local a = math.rad(i * 30 + 15)
		lantern(hub, CFrame.Angles(0, a, 0) * CFrame.new(0, 0.5, -47))
	end

	local spawn = make("SpawnLocation", {
		Name = "HubSpawn",
		Size = Vector3.new(8, 1, 8),
		CFrame = CFrame.new(0, 1.2, 22),
		Anchored = true,
		Neutral = true,
		Duration = 0,
		Material = Enum.Material.Marble,
		Color = C.path,
		TopSurface = Enum.SurfaceType.Smooth,
	}, hub)
	spawn:SetAttribute("Hub", true)
end

--------------------------------------------------------------------------------

local function buildLighting()
	Lighting.ClockTime = 15.2
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(70, 60, 56)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 128, 118)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	for _, c in Lighting:GetChildren() do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
			c:Destroy()
		end
	end
	make("Atmosphere", { Density = 0.32, Offset = 0.15, Color = Color3.fromRGB(230, 205, 180), Decay = Color3.fromRGB(150, 110, 90), Glare = 0.2, Haze = 1.4 }, Lighting)
	make("BloomEffect", { Intensity = 0.7, Size = 28, Threshold = 1.6 }, Lighting)
	make("ColorCorrectionEffect", { Saturation = 0.12, Contrast = 0.06, TintColor = Color3.fromRGB(255, 244, 232) }, Lighting)
	make("SunRaysEffect", { Intensity = 0.06, Spread = 0.6 }, Lighting)
end

function WorldBuilder.build()
	local existing = workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end
	for _, name in { "Baseplate", "SpawnLocation" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local world = make("Folder", { Name = "World" }, workspace)
	local ground = part(world, "Ground", Vector3.new(2048, 4, 2048), CFrame.new(0, -2, 0), C.grass, Enum.Material.Grass)
	ground.Name = "Ground"
	buildHub(world)

	local plots = make("Folder", { Name = "Plots" }, world)
	local paths = make("Folder", { Name = "Paths" }, world)
	for i = 1, PLOT_COUNT do
		local angle = math.rad((i - 1) * (360 / PLOT_COUNT) + 30)
		local pos = Vector3.new(math.sin(angle) * PLOT_RING_RADIUS, 0, math.cos(angle) * PLOT_RING_RADIUS)
		-- plot's +Z (entrance) faces the hub
		local cf = CFrame.lookAt(pos, Vector3.new(0, 0, 0)) * CFrame.Angles(0, math.rad(180), 0)
		buildPlot(plots, i, cf)
		local mid = pos * 0.58
		local len = PLOT_RING_RADIUS - 48 - PLOT_SIZE / 2 + 4
		part(paths, "Path", Vector3.new(10, 0.4, len), CFrame.lookAt(Vector3.new(mid.X, 0.2, mid.Z), Vector3.new(0, 0.2, 0)), C.path, Enum.Material.Sandstone)
	end

	-- scenery ring
	local scenery = make("Folder", { Name = "Scenery" }, world)
	local rng = Random.new(1919)
	for i = 1, 70 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(185, 330)
		local cf = CFrame.new(math.sin(a) * r, 0, math.cos(a) * r) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		if i % 3 == 0 then
			rock(scenery, cf, rng:NextNumber(1, 3))
		else
			tree(scenery, cf, rng:NextNumber(0.9, 1.6))
		end
	end
	for i = 0, 5 do
		local a = math.rad(i * 60)
		rock(scenery, CFrame.new(math.sin(a) * 70, 0, math.cos(a) * 70), 1.2)
		tree(scenery, CFrame.new(math.sin(a + 0.3) * 74, 0, math.cos(a + 0.3) * 74), 1.1)
	end

	buildLighting()
	return world
end

return WorldBuilder
