--!strict
-- Procedural egg model. Pure construction, no yields, no globals.
-- build(color, accent) -> Model, PrimaryPart "Root" at the egg centre, everything welded, unanchored.

local EggModels = {}

local PLASTIC = Enum.Material.SmoothPlastic

type Ctx = { model: Model, root: Part }

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

local function ball(ctx: Ctx, name: string, d: number, pos: Vector3, color: Color3, material: Enum.Material?): Part
	return mk(ctx, name, Enum.PartType.Ball, Vector3.new(d, d, d), CFrame.new(pos), color, material)
end

-- Unit-ish surface directions for the spots (egg is ~1 stud radius, slightly narrower on top).
local SPOTS = {
	{ Vector3.new(0.55, -0.35, -0.75), 0.4 },
	{ Vector3.new(-0.7, 0.0, -0.7), 0.32 },
	{ Vector3.new(0.1, 0.1, -1.0), 0.28 },
	{ Vector3.new(-0.2, -0.75, -0.6), 0.34 },
	{ Vector3.new(0.85, 0.2, 0.45), 0.36 },
	{ Vector3.new(-0.6, -0.4, 0.7), 0.38 },
	{ Vector3.new(0.4, 0.95, -0.3), 0.26 },
	{ Vector3.new(-0.5, 1.0, 0.2), 0.3 },
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

EggModels.validate = validate

function EggModels.build(color: Color3, accent: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Egg"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.Anchored = false
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Parent = model
	model.PrimaryPart = root

	local ctx: Ctx = { model = model, root = root }

	-- egg body: wide lower ball, round middle, narrower top ball
	ball(ctx, "Lower", 2.0, Vector3.new(0, -0.1, 0), color)
	ball(ctx, "Middle", 1.9, Vector3.new(0, 0.2, 0), color)
	ball(ctx, "Upper", 1.6, Vector3.new(0, 0.5, 0), color)

	-- band around the belly
	mk(ctx, "Band", Enum.PartType.Cylinder, Vector3.new(0.22, 2.06, 2.06), CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2), accent)
	mk(ctx, "BandTop", Enum.PartType.Cylinder, Vector3.new(0.12, 1.66, 1.66), CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.pi / 2), accent)

	-- spots placed on the shell (centre offset so each is half embedded)
	for i, s in SPOTS do
		local dir = (s[1] :: Vector3).Unit
		local d = s[2] :: number
		local radius = if dir.Y > 0.5 then 0.8 else 1.0
		local centreY = if dir.Y > 0.5 then 0.5 else 0.05
		ball(ctx, "Spot" .. i, d, Vector3.new(0, centreY, 0) + dir * (radius - 0.02), accent)
	end

	-- soft shine
	ball(ctx, "Shine", 0.3, Vector3.new(-0.45, 0.75, -0.55), color:Lerp(Color3.new(1, 1, 1), 0.7))

	assert(validate(model), "EggModels.build produced an invalid model")
	return model
end

return EggModels
