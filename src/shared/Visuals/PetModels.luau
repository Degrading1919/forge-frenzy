--!strict
-- Procedural companion models. Pure construction, no yields, no globals.
-- build(modelKind, color, rarity) -> Model
--   * PrimaryPart = "Root" (invisible, at the body centre); creature faces -Z.
--   * Every part is unanchored, non-colliding, massless and welded to Root.

local PetModels = {}

PetModels.Kinds = { "golem", "sprite", "clockwork", "mole", "fox", "turtle", "owl", "slime", "dragon", "phoenix", "bat", "mimic", "salamander", "pup" }

PetModels.RarityColors = {
	Color3.fromRGB(200, 200, 200),
	Color3.fromRGB(90, 200, 90),
	Color3.fromRGB(70, 140, 255),
	Color3.fromRGB(170, 80, 255),
	Color3.fromRGB(255, 170, 40),
	Color3.fromRGB(255, 60, 90),
}

local PLASTIC = Enum.Material.SmoothPlastic
local EMBER = Color3.fromRGB(255, 140, 40)
local BRASS = Color3.fromRGB(196, 150, 70)
local CREAM = Color3.fromRGB(250, 240, 225)
local BLACK = Color3.fromRGB(25, 22, 28)
local WHITE = Color3.fromRGB(255, 255, 255)
local ORANGE = Color3.fromRGB(240, 160, 50)

type Ctx = {
	model: Model,
	root: Part,
	c: Color3, -- main colour
	d: Color3, -- darker
	l: Color3, -- lighter
}

type Builder = (Ctx) -> ()

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function mk(ctx: Ctx, name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or PLASTIC
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = ctx.model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ctx.root
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function rotCF(pos: Vector3, deg: Vector3?): CFrame
	local r = deg or Vector3.zero
	return CFrame.new(pos) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

local function ball(ctx: Ctx, name: string, d: number, pos: Vector3, color: Color3, material: Enum.Material?): Part
	return mk(ctx, name, Enum.PartType.Ball, Vector3.new(d, d, d), CFrame.new(pos), color, material)
end

local function blk(ctx: Ctx, name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?, deg: Vector3?): Part
	return mk(ctx, name, Enum.PartType.Block, size, rotCF(pos, deg), color, material)
end

-- axis: "X" (native), "Y" or "Z"
local function cyl(ctx: Ctx, name: string, d: number, len: number, pos: Vector3, color: Color3, axis: string, material: Enum.Material?): Part
	local rot = if axis == "Y" then Vector3.new(0, 0, 90) elseif axis == "Z" then Vector3.new(0, 90, 0) else Vector3.zero
	return mk(ctx, name, Enum.PartType.Cylinder, Vector3.new(len, d, d), rotCF(pos, rot), color, material)
end

-- flat rhombus in the XY plane (yawDeg = 90 turns it into the ZY plane)
local function gem(ctx: Ctx, name: string, w: number, t: number, pos: Vector3, color: Color3, material: Enum.Material?, yawDeg: number?): Part
	local s = w / math.sqrt(2)
	return mk(ctx, name, Enum.PartType.Block, Vector3.new(s, s, t), rotCF(pos, Vector3.new(0, yawDeg or 0, 45)), color, material)
end

local function eye(ctx: Ctx, name: string, pos: Vector3, d: number)
	ball(ctx, name, d, pos, BLACK)
	ball(ctx, name .. "Glint", d * 0.35, pos + Vector3.new(d * 0.15, d * 0.2, -d * 0.38), WHITE)
end

local function eyes(ctx: Ctx, x: number, y: number, z: number, d: number)
	eye(ctx, "EyeL", Vector3.new(-x, y, z), d)
	eye(ctx, "EyeR", Vector3.new(x, y, z), d)
end

local function emitter(parent: Instance, name: string, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
end

local function fade(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

------------------------------------------------------------------------
-- Creatures (origin = body centre, front = -Z)
------------------------------------------------------------------------

local BUILDERS: { [string]: Builder } = {}

BUILDERS.golem = function(ctx)
	local c, d, l = ctx.c, ctx.d, ctx.l
	local slate = Enum.Material.Slate
	for _, s in { -1, 1 } do
		local t = if s > 0 then "R" else "L"
		blk(ctx, "Leg" .. t, Vector3.new(0.7, 0.6, 0.7), Vector3.new(s * 0.5, -1.0, 0), d, slate)
		blk(ctx, "Arm" .. t, Vector3.new(0.6, 1.1, 0.6), Vector3.new(s * 1.15, -0.1, 0), d, slate)
		blk(ctx, "Fist" .. t, Vector3.new(0.8, 0.7, 0.8), Vector3.new(s * 1.15, -0.85, 0), c, slate)
		blk(ctx, "Shoulder" .. t, Vector3.new(0.7, 0.5, 0.7), Vector3.new(s * 1.0, 0.7, 0), l, slate, Vector3.new(0, 30, s * 20))
	end
	blk(ctx, "Body", Vector3.new(1.7, 1.3, 1.4), Vector3.new(0, -0.05, 0), c, slate)
	blk(ctx, "ChestPlate", Vector3.new(1.2, 0.5, 0.1), Vector3.new(0, 0.1, -0.72), l, slate)
	ball(ctx, "Core", 0.45, Vector3.new(0, -0.05, -0.76), EMBER, Enum.Material.Neon)
	blk(ctx, "Head", Vector3.new(1.1, 0.9, 1.0), Vector3.new(0, 1.0, -0.1), c, slate)
	blk(ctx, "Brow", Vector3.new(1.2, 0.2, 0.2), Vector3.new(0, 1.3, -0.65), d, slate)
	ball(ctx, "EyeL", 0.24, Vector3.new(-0.28, 1.05, -0.62), EMBER, Enum.Material.Neon)
	ball(ctx, "EyeR", 0.24, Vector3.new(0.28, 1.05, -0.62), EMBER, Enum.Material.Neon)
	blk(ctx, "CrystalA", Vector3.new(0.35, 0.9, 0.35), Vector3.new(-0.4, 0.9, 0.7), EMBER, Enum.Material.Neon, Vector3.new(15, 0, -20))
	blk(ctx, "CrystalB", Vector3.new(0.35, 1.0, 0.35), Vector3.new(0.1, 1.0, 0.75), EMBER, Enum.Material.Neon, Vector3.new(15, 0, 5))
	blk(ctx, "CrystalC", Vector3.new(0.35, 0.8, 0.35), Vector3.new(0.5, 0.8, 0.7), EMBER, Enum.Material.Neon, Vector3.new(15, 0, 22))
end

BUILDERS.sprite = function(ctx)
	local c, l = ctx.c, ctx.l
	local neon = Enum.Material.Neon
	ball(ctx, "Core", 1.5, Vector3.zero, c, neon)
	ball(ctx, "Inner", 0.9, Vector3.new(0, -0.1, -0.15), l, neon)
	ball(ctx, "Upper", 1.1, Vector3.new(0, 0.55, 0.05), c, neon)
	gem(ctx, "TipA", 0.9, 0.7, Vector3.new(0, 1.15, 0), c, neon)
	gem(ctx, "TipB", 0.9, 0.7, Vector3.new(0, 1.15, 0), c, neon, 90)
	gem(ctx, "TongueL", 0.5, 0.4, Vector3.new(-0.7, 0.75, 0), c, neon)
	gem(ctx, "TongueR", 0.5, 0.4, Vector3.new(0.7, 0.75, 0), c, neon)
	ball(ctx, "Wisp1", 0.8, Vector3.new(0, -0.85, 0.1), c, neon)
	ball(ctx, "Wisp2", 0.45, Vector3.new(0, -1.2, 0.1), l, neon)
	eyes(ctx, 0.3, 0.1, -0.66, 0.32)
	blk(ctx, "Mouth", Vector3.new(0.25, 0.06, 0.06), Vector3.new(0, -0.2, -0.72), BLACK)
	emitter(ctx.root, "Embers", {
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 70, 0)),
		Size = NumberSequence.new(0.25, 0),
		Transparency = fade(0, 1),
		Lifetime = NumberRange.new(0.6, 1.1),
		Rate = 12,
		Speed = NumberRange.new(0.5, 1.5),
		Acceleration = Vector3.new(0, 3, 0),
		SpreadAngle = Vector2.new(30, 30),
		LightEmission = 1,
	})
end

BUILDERS.clockwork = function(ctx)
	local c, d = ctx.c, ctx.d
	local metal = Enum.Material.Metal
	local cyan = Color3.fromRGB(90, 230, 255)
	blk(ctx, "Body", Vector3.new(1.3, 1.2, 1.0), Vector3.zero, c, metal)
	blk(ctx, "BellyPlate", Vector3.new(0.8, 0.6, 0.1), Vector3.new(0, -0.05, -0.52), BRASS, metal)
	ball(ctx, "Gauge", 0.25, Vector3.new(0, -0.05, -0.58), cyan, Enum.Material.Neon)
	blk(ctx, "Head", Vector3.new(1.2, 0.9, 1.0), Vector3.new(0, 1.1, -0.05), c, metal)
	blk(ctx, "Visor", Vector3.new(0.95, 0.4, 0.1), Vector3.new(0, 1.15, -0.56), BLACK)
	ball(ctx, "EyeL", 0.24, Vector3.new(-0.25, 1.15, -0.6), cyan, Enum.Material.Neon)
	ball(ctx, "EyeR", 0.24, Vector3.new(0.25, 1.15, -0.6), cyan, Enum.Material.Neon)
	cyl(ctx, "Antenna", 0.08, 0.5, Vector3.new(0.3, 1.75, 0), d, "Y", metal)
	ball(ctx, "AntennaTip", 0.2, Vector3.new(0.3, 2.05, 0), Color3.fromRGB(255, 80, 80), Enum.Material.Neon)
	cyl(ctx, "BoltL", 0.3, 0.2, Vector3.new(-0.7, 1.1, 0), BRASS, "X", metal)
	cyl(ctx, "BoltR", 0.3, 0.2, Vector3.new(0.7, 1.1, 0), BRASS, "X", metal)
	cyl(ctx, "Gear", 0.9, 0.15, Vector3.new(0, 0.1, 0.58), BRASS, "Z", metal)
	blk(ctx, "GearSpokeA", Vector3.new(0.15, 1.1, 0.12), Vector3.new(0, 0.1, 0.66), BRASS, metal)
	blk(ctx, "GearSpokeB", Vector3.new(1.1, 0.15, 0.12), Vector3.new(0, 0.1, 0.66), BRASS, metal)
	for _, s in { -1, 1 } do
		local t = if s > 0 then "R" else "L"
		cyl(ctx, "Arm" .. t, 0.3, 0.6, Vector3.new(s * 0.95, 0.1, 0), d, "X", metal)
		ball(ctx, "Hand" .. t, 0.45, Vector3.new(s * 1.3, 0.1, 0), BRASS, metal)
		blk(ctx, "Leg" .. t, Vector3.new(0.4, 0.5, 0.5), Vector3.new(s * 0.35, -0.85, 0), d, metal)
		blk(ctx, "Foot" .. t, Vector3.new(0.5, 0.2, 0.7), Vector3.new(s * 0.35, -1.15, -0.1), BRASS, metal)
	end
end

BUILDERS.mole = function(ctx)
	local c, d, l = ctx.c, ctx.d, ctx.l
	local yellow = Color3.fromRGB(240, 190, 50)
	local pink = Color3.fromRGB(230, 120, 140)
	local coal = Color3.fromRGB(40, 40, 45)
	ball(ctx, "Body", 2.1, Vector3.zero, c)
	ball(ctx, "Belly", 1.5, Vector3.new(0, -0.25, -0.55), l)
	ball(ctx, "Helmet", 1.1, Vector3.new(0, 0.85, -0.2), yellow)
	cyl(ctx, "Brim", 1.3, 0.12, Vector3.new(0, 0.65, -0.25), Color3.fromRGB(200, 150, 30), "Y")
	ball(ctx, "Lamp", 0.3, Vector3.new(0, 0.9, -0.75), Color3.fromRGB(255, 230, 150), Enum.Material.Neon)
	ball(ctx, "Snout", 0.75, Vector3.new(0, -0.05, -1.0), l)
	ball(ctx, "Nose", 0.3, Vector3.new(0, 0.1, -1.35), pink)
	eyes(ctx, 0.4, 0.3, -0.9, 0.24)
	for _, s in { -1, 1 } do
		local t = if s > 0 then "R" else "L"
		blk(ctx, "Arm" .. t, Vector3.new(0.5, 0.45, 0.8), Vector3.new(s * 1.0, -0.6, -0.45), d)
		blk(ctx, "ClawA" .. t, Vector3.new(0.12, 0.1, 0.3), Vector3.new(s * 1.0 - 0.1, -0.6, -0.95), CREAM)
		blk(ctx, "ClawB" .. t, Vector3.new(0.12, 0.1, 0.3), Vector3.new(s * 1.0 + 0.1, -0.6, -0.95), CREAM)
		blk(ctx, "Foot" .. t, Vector3.new(0.5, 0.25, 0.6), Vector3.new(s * 0.5, -1.0, -0.2), d)
	end
	blk(ctx, "CoalA", Vector3.new(0.45, 0.4, 0.4), Vector3.new(-0.3, 0.75, 0.5), coal, Enum.Material.Slate, Vector3.new(20, 30, 10))
	blk(ctx, "CoalB", Vector3.new(0.45, 0.4, 0.4), Vector3.new(0.35, 0.5, 0.65), coal, Enum.Material.Slate, Vector3.new(-15, 10, 25))
	ball(ctx, "Ember", 0.2, Vector3.new(0.3, 0.75, 0.75), EMBER, Enum.Material.Neon)
end

BUILDERS.fox = function(ctx)
	local c, d = ctx.c, ctx.d
	blk(ctx, "Body", Vector3.new(1.0, 0.9, 1.6), Vector3.new(0, 0, 0.1), c)
	blk(ctx, "Chest", Vector3.new(0.8, 0.6, 0.5), Vector3.new(0, -0.1, -0.6), CREAM)
	blk(ctx, "Head", Vector3.new(1.0, 0.85, 0.9), Vector3.new(0, 0.65, -1.0), c)
	blk(ctx, "Snout", Vector3.new(0.5, 0.4, 0.55), Vector3.new(0, 0.5, -1.6), CREAM)
	ball(ctx, "Nose", 0.22, Vector3.new(0, 0.62, -1.9), BLACK)
	eyes(ctx, 0.28, 0.78, -1.47, 0.24)
	for _, s in { -1, 1 } do
		local t = if s > 0 then "R" else "L"
		gem(ctx, "Ear" .. t, 0.55, 0.18, Vector3.new(s * 0.32, 1.3, -0.95), c)
		gem(ctx, "EarIn" .. t, 0.3, 0.18, Vector3.new(s * 0.32, 1.25, -1.02), d)
		gem(ctx, "Bolt" .. t, 0.35, 0.06, Vector3.new(s * 0.52, 0.1, 0.1), Color3.fromRGB(255, 230, 90), Enum.Material.Neon)
		for _, z in { -0.65, 0.65 } do
			blk(ctx, "Leg" .. t .. (if z < 0 then "F" else "B"), Vector3.new(0.3, 0.7, 0.3), Vector3.new(s * 0.3, -0.75, z), d)
		end
	end
	ball(ctx, "Tail1", 0.6, Vector3.new(0, 0.2, 0.95), c)
	ball(ctx, "Tail2", 0.8, Vector3.new(0, 0.55, 1.45), c)
	ball(ctx, "Tail3", 0.55, Vector3.new(0, 0.95, 1.85), CREAM)
	ball(ctx, "TailSpark", 0.3, Vector3.new(0, 1.2, 2.05), Color3.fromRGB(255, 230, 90), Enum.Material.Neon)
end

BUILDERS.turtle = function(ctx)
	local c, d = ctx.c, ctx.d
	local iron = Color3.fromRGB(70, 72, 80)
	local metal = Enum.Material.Metal
	blk(ctx, "Body", Vector3.new(2.0, 0.6, 2.0), Vector3.new(0, -0.7, 0), c)
	ball(ctx, "Neck", 0.6, Vector3.new(0, -0.65, -1.0), c)
	ball(ctx, "Head", 0.95, Vector3.new(0, -0.5, -1.35), c)
	eyes(ctx, 0.25, -0.35, -1.75, 0.22)
	ball(ctx, "Tail", 0.3, Vector3.new(0, -0.8, 1.1), d)
	for _, s in { -1, 1 } do
		for _, z in { -0.7, 0.7 } do
			ball(ctx, "Leg" .. (if s > 0 then "R" else "L") .. (if z < 0 then "F" else "B"), 0.65, Vector3.new(s * 0.8, -1.0, z), d)
		end
	end
	blk(ctx, "AnvilBase", Vector3.new(1.4, 0.35, 1.1), Vector3.new(0, -0.25, 0.05), iron, metal)
	blk(ctx, "AnvilWaist", Vector3.new(0.8, 0.45, 0.8), Vector3.new(0, 0.15, 0.05), iron, metal)
	blk(ctx, "AnvilTop", Vector3.new(2.0, 0.45, 1.1), Vector3.new(0, 0.6, 0.05), iron, metal)
	gem(ctx, "AnvilHorn", 0.8, 0.8, Vector3.new(-1.2, 0.6, 0.05), iron, metal)
	blk(ctx, "AnvilFace", Vector3.new(1.9, 0.06, 1.0), Vector3.new(0, 0.85, 0.05), ctx.l, metal)
	blk(ctx, "HotSpot", Vector3.new(0.5, 0.05, 0.4), Vector3.new(0.3, 0.9, 0.05), EMBER, Enum.Material.Neon)
end

BUILDERS.owl = function(ctx)
	local c, d, l = ctx.c, ctx.d, ctx.l
	local metal = Enum.Material.Metal
	ball(ctx, "Body", 1.9, Vector3.zero, c)
	ball(ctx, "Belly", 1.35, Vector3.new(0, -0.1, -0.5), l)
	cyl(ctx, "ChestGear", 0.5, 0.08, Vector3.new(0, -0.1, -1.12), BRASS, "Z", metal)
	blk(ctx, "ChestGearSpoke", Vector3.new(0.12, 0.65, 0.06), Vector3.new(0, -0.1, -1.15), BRASS, metal)
	ball(ctx, "Head", 1.5, Vector3.new(0, 1.05, -0.1), c)
	for _, s in { -1, 1 } do
		local t = if s > 0 then "R" else "L"
		ball(ctx, "EyeRim" .. t, 0.75, Vector3.new(s * 0.4, 1.15, -0.62), BRASS, metal)
		ball(ctx, "EyeWhite" .. t, 0.6, Vector3.new(s * 0.4, 1.15, -0.72), WHITE)
		ball(ctx, "Pupil" .. t, 0.3, Vector3.new(s * 0.4, 1.15, -0.9), BLACK)
		gem(ctx, "Tuft" .. t, 0.5, 0.2, Vector3.new(s * 0.5, 1.8, -0.05), d)
		blk(ctx, "Wing" .. t, Vector3.new(0.3, 1.2, 0.9), Vector3.new(s * 1.0, 0, 0.05), d, nil, Vector3.new(0, 0, s * 8))
		blk(ctx, "WingTip" .. t, Vector3.new(0.28, 0.4, 0.7), Vector3.new(s * 1.05, -0.7, 0.1), d)
		blk(ctx, "Foot" .. t, Vector3.new(0.5, 0.15, 0.5), Vector3.new(s * 0.35, -0.95, -0.35), ORANGE)
	end
	gem(ctx, "Beak", 0.35, 0.3, Vector3.new(0, 0.95, -0.85), ORANGE)
	blk(ctx, "Tail", Vector3.new(0.7, 0.5, 0.15), Vector3.new(0, -0.6, 0.9), d, nil, Vector3.new(-30, 0, 0))
end

BUILDERS.slime = function(ctx)
	local c, l = ctx.c, ctx.l
	local neon = Enum.Material.Neon
	cyl(ctx, "Puddle", 2.8, 0.15, Vector3.new(0, -0.95, 0), c, "Y")
	local body = ball(ctx, "Body", 2.2, Vector3.new(0, 0.1, 0), c)
	body.Transparency = 0.15
	ball(ctx, "Core", 1.2, Vector3.new(0, 0, 0.1), l, neon)
	ball(ctx, "BubbleA", 0.3, Vector3.new(0.5, 0.5, 0.3), l, neon)
	ball(ctx, "BubbleB", 0.3, Vector3.new(-0.4, -0.3, 0.5), l, neon)
	ball(ctx, "BubbleC", 0.22, Vector3.new(0.2, -0.5, 0.2), l, neon)
	ball(ctx, "Drip", 0.4, Vector3.new(0.9, -0.7, -0.5), c)
	local cap = ball(ctx, "Cap", 0.7, Vector3.new(0, 1.2, 0), c)
	cap.Transparency = 0.15
	eyes(ctx, 0.4, 0.35, -0.95, 0.34)
	blk(ctx, "Mouth", Vector3.new(0.35, 0.08, 0.06), Vector3.new(0, 0.0, -1.07), BLACK)
end

BUILDERS.dragon = function(ctx)
	local c, d, l = ctx.c, ctx.d, ctx.l
	local horn = Color3.fromRGB(120, 90, 40)
	ball(ctx, "Body", 2.4, Vector3.zero, c)
	ball(ctx, "Belly", 1.8, Vector3.new(0, -0.25, -0.75), l)
	ball(ctx, "Neck", 1.1, Vector3.new(0, 0.9, -0.9), c)
	blk(ctx, "Head", Vector3.new(1.1, 0.95, 1.2), Vector3.new(0, 1.5, -1.35), c)
	blk(ctx, "Snout", Vector3.new(0.75, 0.55, 0.7), Vector3.new(0, 1.35, -2.1), c)
	blk(ctx, "Jaw", Vector3.new(0.7, 0.2, 0.6), Vector3.new(0, 1.05, -2.0), d)
	ball(ctx, "NostrilL", 0.12, Vector3.new(-0.2, 1.5, -2.43), BLACK)
	ball(ctx, "NostrilR", 0.12, Vector3.new(0.2, 1.5, -2.43), BLACK)
	eyes(ctx, 0.4, 1.7, -1.9, 0.3)
	for _, s in { -1, 1 } do
		local t = if s > 0 then "R" else "L"
		blk(ctx, "Horn" .. t, Vector3.new(0.18, 0.8, 0.18), Vector3.new(s * 0.35, 2.15, -1.0), horn, Enum.Material.Metal, Vector3.new(-30, 0, s * 15))
		blk(ctx, "LegF" .. t, Vector3.new(0.6, 0.9, 0.7), Vector3.new(s * 0.8, -1.0, -0.5), c)
		blk(ctx, "LegB" .. t, Vector3.new(0.65, 0.9, 0.75), Vector3.new(s * 0.85, -1.0, 0.7), c)
		blk(ctx, "FootF" .. t, Vector3.new(0.7, 0.2, 0.9), Vector3.new(s * 0.8, -1.5, -0.6), d)
		blk(ctx, "FootB" .. t, Vector3.new(0.75, 0.2, 0.9), Vector3.new(s * 0.85, -1.5, 0.6), d)
		-- wing
		blk(ctx, "WingArm" .. t, Vector3.new(1.4, 0.2, 0.2), Vector3.new(s * 1.5, 1.3, 0.2), horn, Enum.Material.Metal, Vector3.new(0, 0, s * 25))
		blk(ctx, "WingMembA" .. t, Vector3.new(1.8, 0.06, 1.4), Vector3.new(s * 1.7, 1.0, 0.5), l, nil, Vector3.new(0, 0, s * 20))
		blk(ctx, "WingMembB" .. t, Vector3.new(1.0, 0.06, 1.1), Vector3.new(s * 2.6, 1.4, 0.4), d, nil, Vector3.new(0, 0, s * 20))
		gem(ctx, "WingClaw" .. t, 0.3, 0.12, Vector3.new(s * 2.35, 1.95, 0.2), horn, Enum.Material.Metal)
	end
	for i, z in { -0.2, 0.55, 1.0 } do
		gem(ctx, "Spike" .. i, 0.45, 0.2, Vector3.new(0, 1.3 - (i - 1) * 0.25, z), horn, Enum.Material.Metal, 90)
	end
	ball(ctx, "Tail1", 1.3, Vector3.new(0, -0.3, 1.5), c)
	ball(ctx, "Tail2", 1.0, Vector3.new(0, -0.1, 2.3), c)
	ball(ctx, "Tail3", 0.7, Vector3.new(0, 0.25, 3.0), c)
	gem(ctx, "TailFlame", 0.7, 0.2, Vector3.new(0, 0.6, 3.5), EMBER, Enum.Material.Neon, 90)
end

BUILDERS.phoenix = function(ctx)
	local c, d, l = ctx.c, ctx.d, ctx.l
	local neon = Enum.Material.Neon
	ball(ctx, "Body", 1.5, Vector3.zero, c)
	ball(ctx, "Chest", 1.0, Vector3.new(0, -0.1, -0.45), l)
	ball(ctx, "Head", 1.0, Vector3.new(0, 0.95, -0.45), c)
	gem(ctx, "CrestA", 0.5, 0.12, Vector3.new(0, 1.6, -0.4), l, neon, 90)
	gem(ctx, "CrestB", 0.4, 0.12, Vector3.new(0, 1.55, -0.1), l, neon, 90)
	gem(ctx, "Beak", 0.3, 0.25, Vector3.new(0, 0.9, -1.0), ORANGE)
	eyes(ctx, 0.28, 1.05, -0.82, 0.2)
	local feathers = { { 1.6, 15 }, { 1.4, 35 }, { 1.1, 55 } }
	for _, s in { -1, 1 } do
		local t = if s > 0 then "R" else "L"
		for i, f in feathers do
			local len, deg = f[1], f[2]
			local a = math.rad(deg)
			local pos = Vector3.new(s * (0.6 + len / 2 * math.cos(a)), 0.3 + len / 2 * math.sin(a), 0.2)
			blk(ctx, "Feather" .. t .. i, Vector3.new(len, 0.12, 0.5), pos, if i % 2 == 1 then c else l, nil, Vector3.new(0, 0, s * deg))
			gem(ctx, "FeatherTip" .. t .. i, 0.4, 0.12, Vector3.new(s * (0.6 + len * math.cos(a)), 0.3 + len * math.sin(a), 0.2), EMBER, neon)
		end
		blk(ctx, "Leg" .. t, Vector3.new(0.12, 0.5, 0.12), Vector3.new(s * 0.25, -0.85, -0.1), ORANGE)
	end
	local tails = { { -0.4, -15, c }, { 0, 0, l }, { 0.4, 15, d } }
	for i, tl in tails do
		blk(ctx, "TailFeather" .. i, Vector3.new(0.3, 0.1, 1.6), Vector3.new(tl[1], -0.1, 1.4), tl[3], nil, Vector3.new(0, tl[2], 0))
		gem(ctx, "TailTip" .. i, 0.35, 0.1, Vector3.new(tl[1] + math.sin(math.rad(-tl[2])) * 0.9, -0.1, 2.3), EMBER, neon, 90)
	end
end

BUILDERS.bat = function(ctx)
	local c, d, l = ctx.c, ctx.d, ctx.l
	ball(ctx, "Body", 1.4, Vector3.zero, c)
	ball(ctx, "Belly", 1.0, Vector3.new(0, -0.1, -0.35), l)
	ball(ctx, "Head", 1.2, Vector3.new(0, 0.85, -0.2), c)
	ball(ctx, "Snout", 0.45, Vector3.new(0, 0.7, -0.75), l)
	ball(ctx, "Nose", 0.16, Vector3.new(0, 0.75, -0.95), BLACK)
	eyes(ctx, 0.3, 0.95, -0.68, 0.28)
	for _, s in { -1, 1 } do
		local t = if s > 0 then "R" else "L"
		gem(ctx, "Ear" .. t, 0.7, 0.14, Vector3.new(s * 0.4, 1.7, -0.2), c)
		gem(ctx, "EarIn" .. t, 0.4, 0.14, Vector3.new(s * 0.4, 1.62, -0.28), Color3.fromRGB(230, 120, 140))
		blk(ctx, "WingArm" .. t, Vector3.new(1.2, 0.14, 0.14), Vector3.new(s * 1.2, 0.5, 0.2), d, nil, Vector3.new(0, 0, s * 25))
		blk(ctx, "Wing" .. t, Vector3.new(1.7, 0.05, 1.2), Vector3.new(s * 1.5, 0.2, 0.3), d, nil, Vector3.new(0, 0, s * 15))
		gem(ctx, "WingTip" .. t, 0.6, 0.05, Vector3.new(s * 2.4, 0.25, 0.4), d)
		blk(ctx, "Foot" .. t, Vector3.new(0.2, 0.3, 0.2), Vector3.new(s * 0.3, -0.8, 0), l)
		gem(ctx, "Fang" .. t, 0.14, 0.06, Vector3.new(s * 0.1, 0.5, -0.9), WHITE)
	end
end

BUILDERS.mimic = function(ctx)
	local c, d = ctx.c, ctx.d
	local gold = Color3.fromRGB(230, 180, 60)
	local metal = Enum.Material.Metal
	blk(ctx, "Base", Vector3.new(2.0, 1.0, 1.5), Vector3.new(0, -0.5, 0), c, Enum.Material.Wood)
	blk(ctx, "Lid", Vector3.new(2.0, 0.6, 1.5), Vector3.new(0, 0.55, 0.15), d, Enum.Material.Wood, Vector3.new(-20, 0, 0))
	blk(ctx, "Mouth", Vector3.new(1.8, 0.2, 1.3), Vector3.new(0, 0.0, 0), Color3.fromRGB(120, 30, 50))
	for i = -2, 2 do
		local y = if i % 2 == 0 then 0.2 else 0.08
		gem(ctx, "Tooth" .. i, 0.4, 0.15, Vector3.new(i * 0.38, y, -0.7), WHITE)
	end
	blk(ctx, "BandL", Vector3.new(0.2, 1.05, 1.55), Vector3.new(-0.8, -0.5, 0), gold, metal)
	blk(ctx, "BandR", Vector3.new(0.2, 1.05, 1.55), Vector3.new(0.8, -0.5, 0), gold, metal)
	blk(ctx, "Lock", Vector3.new(0.4, 0.4, 0.12), Vector3.new(0, -0.2, -0.78), gold, metal)
	ball(ctx, "Tongue", 0.5, Vector3.new(0, -0.1, -0.5), Color3.fromRGB(230, 90, 120))
	eyes(ctx, 0.5, 0.55, -0.7, 0.34)
	ball(ctx, "Coin", 0.35, Vector3.new(0.6, 0.25, 0.1), gold, Enum.Material.Neon)
	blk(ctx, "FootL", Vector3.new(0.5, 0.25, 0.5), Vector3.new(-0.7, -1.1, -0.3), d)
	blk(ctx, "FootR", Vector3.new(0.5, 0.25, 0.5), Vector3.new(0.7, -1.1, -0.3), d)
end

BUILDERS.salamander = function(ctx)
	local c, d, l = ctx.c, ctx.d, ctx.l
	blk(ctx, "Body", Vector3.new(1.0, 0.8, 1.8), Vector3.zero, c)
	blk(ctx, "Belly", Vector3.new(0.8, 0.3, 1.5), Vector3.new(0, -0.3, 0), l)
	blk(ctx, "Head", Vector3.new(1.0, 0.8, 0.9), Vector3.new(0, 0.1, -1.2), c)
	blk(ctx, "Snout", Vector3.new(0.7, 0.4, 0.4), Vector3.new(0, 0, -1.7), l)
	eyes(ctx, 0.35, 0.45, -1.52, 0.3)
	for _, s in { -1, 1 } do
		for _, z in { -0.6, 0.6 } do
			local t = (if s > 0 then "R" else "L") .. (if z < 0 then "F" else "B")
			blk(ctx, "Leg" .. t, Vector3.new(0.4, 0.5, 0.4), Vector3.new(s * 0.6, -0.5, z), d)
			blk(ctx, "Foot" .. t, Vector3.new(0.5, 0.15, 0.55), Vector3.new(s * 0.65, -0.8, z - 0.05), l)
		end
	end
	ball(ctx, "Tail1", 0.7, Vector3.new(0, -0.1, 1.3), c)
	ball(ctx, "Tail2", 0.5, Vector3.new(0, -0.1, 1.9), c)
	ball(ctx, "Tail3", 0.35, Vector3.new(0, 0.0, 2.35), d)
	ball(ctx, "TailFlame", 0.45, Vector3.new(0, 0.3, 2.6), EMBER, Enum.Material.Neon)
	gem(ctx, "FlameTip", 0.45, 0.3, Vector3.new(0, 0.65, 2.6), Color3.fromRGB(255, 210, 80), Enum.Material.Neon, 90)
	for i = 1, 3 do
		gem(ctx, "Spot" .. i, 0.3, 0.08, Vector3.new(0, 0.42, -0.5 + i * 0.5), EMBER, Enum.Material.Neon, 90)
	end
	emitter(ctx.root, "Embers", {
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 70), Color3.fromRGB(255, 70, 0)),
		Size = NumberSequence.new(0.18, 0),
		Transparency = fade(0, 1),
		Lifetime = NumberRange.new(0.5, 0.9),
		Rate = 6,
		Speed = NumberRange.new(0.5, 1),
		Acceleration = Vector3.new(0, 2, 0),
		LightEmission = 1,
	})
end

BUILDERS.pup = function(ctx)
	local c, d, l = ctx.c, ctx.d, ctx.l
	local iron = Color3.fromRGB(70, 72, 80)
	local metal = Enum.Material.Metal
	blk(ctx, "Body", Vector3.new(1.0, 0.9, 1.5), Vector3.new(0, -0.2, 0.2), c)
	blk(ctx, "AnvilBack", Vector3.new(1.3, 0.35, 1.3), Vector3.new(0, 0.4, 0.25), iron, metal)
	gem(ctx, "AnvilHorn", 0.6, 0.6, Vector3.new(0, 0.4, 1.1), iron, metal, 90)
	blk(ctx, "AnvilFace", Vector3.new(1.2, 0.05, 1.2), Vector3.new(0, 0.6, 0.25), l, metal)
	blk(ctx, "Head", Vector3.new(1.0, 0.85, 0.9), Vector3.new(0, 0.35, -0.9), c)
	blk(ctx, "Snout", Vector3.new(0.55, 0.4, 0.5), Vector3.new(0, 0.15, -1.45), l)
	ball(ctx, "Nose", 0.25, Vector3.new(0, 0.3, -1.72), BLACK)
	eyes(ctx, 0.28, 0.5, -1.33, 0.26)
	for _, s in { -1, 1 } do
		local t = if s > 0 then "R" else "L"
		blk(ctx, "Ear" .. t, Vector3.new(0.25, 0.6, 0.4), Vector3.new(s * 0.62, 0.45, -0.85), d, nil, Vector3.new(0, 0, s * 15))
		for _, z in { -0.4, 0.8 } do
			blk(ctx, "Leg" .. t .. (if z < 0 then "F" else "B"), Vector3.new(0.32, 0.6, 0.32), Vector3.new(s * 0.3, -0.85, z), d)
		end
	end
	ball(ctx, "Tail", 0.4, Vector3.new(0, 0.1, 1.2), c)
	ball(ctx, "Spark", 0.2, Vector3.new(0.3, 0.7, 0.2), EMBER, Enum.Material.Neon)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

local GLOW_AURA: { [string]: { color: Color3, size: number } } = {
	dragon = { color = Color3.fromRGB(255, 200, 80), size = 3 },
	phoenix = { color = Color3.fromRGB(255, 120, 40), size = 2 },
}

local function validate(model: Model): boolean
	if not model.PrimaryPart or model.PrimaryPart.Name ~= "Root" then
		return false
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Anchored or d.CanCollide) then
			return false
		end
	end
	return true
end

PetModels.validate = validate

local RARITY_NAMES: { [string]: number } = {
	common = 1,
	uncommon = 2,
	rare = 3,
	epic = 4,
	legendary = 5,
	mythic = 6,
	exclusive = 6,
}

-- Accepts a number or a rarity name ("Common".."Exclusive"); returns 1..6.
function PetModels.rarityIndex(rarity: any): number
	if type(rarity) == "string" then
		return RARITY_NAMES[string.lower(rarity)] or 1
	elseif type(rarity) == "number" then
		return math.clamp(math.floor(rarity), 1, 6)
	end
	return 1
end

function PetModels.build(modelKind: string, color: Color3, rarity: number | string): Model
	local kind = string.lower(tostring(modelKind))
	if not BUILDERS[kind] then
		kind = "slime"
	end
	local rar = PetModels.rarityIndex(rarity)

	local model = Instance.new("Model")
	model.Name = kind

	local aura = GLOW_AURA[kind]
	local rootSize = if aura then aura.size else 1
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(rootSize, rootSize, rootSize)
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.Anchored = false
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Parent = model
	model.PrimaryPart = root

	local ctx: Ctx = {
		model = model,
		root = root,
		c = color,
		d = color:Lerp(Color3.new(0, 0, 0), 0.3),
		l = color:Lerp(Color3.new(1, 1, 1), 0.4),
	}
	BUILDERS[kind](ctx)

	if rar >= 4 then
		emitter(root, "Sparkles", {
			Color = ColorSequence.new(PetModels.RarityColors[rar]),
			Size = NumberSequence.new(0.25, 0),
			Transparency = fade(0, 1),
			Lifetime = NumberRange.new(0.8, 1.4),
			Rate = if rar >= 6 then 18 elseif rar == 5 then 12 else 7,
			Speed = NumberRange.new(0.3, 1),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 0.9,
		})
	end

	if aura then
		local light = Instance.new("PointLight")
		light.Name = "AuraLight"
		light.Color = aura.color
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = root
		emitter(root, "AuraGlow", {
			Color = ColorSequence.new(aura.color, Color3.fromRGB(255, 80, 30)),
			Size = NumberSequence.new(0.6, 0),
			Transparency = fade(0.3, 1),
			Lifetime = NumberRange.new(0.8, 1.4),
			Rate = 14,
			Speed = NumberRange.new(0.5, 1.5),
			Acceleration = Vector3.new(0, 2, 0),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		})
	end

	assert(validate(model), "PetModels.build produced an invalid model")
	return model
end

return PetModels
