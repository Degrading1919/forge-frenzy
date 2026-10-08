--!nonstrict
-- ViewportFrame helpers for weapon / pet previews (pcall-wrapped visual modules with fallbacks).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Theme = require(script.Parent.Theme)
local Data = require(script.Parent.Data)

local Viewport = {}

local spinning: { [ViewportFrame]: { cam: Camera, center: Vector3, dist: number, angle: number, speed: number } } = {}
local conn: RBXScriptConnection? = nil

local function ensureLoop()
	if conn then return end
	conn = RunService.Heartbeat:Connect(function(dt)
		for vf, s in spinning do
			if not vf.Parent then
				spinning[vf] = nil
			elseif vf.Visible and vf.AbsoluteSize.X > 0 then
				s.angle += dt * s.speed
				s.cam.CFrame = CFrame.lookAt(
					s.center + Vector3.new(math.sin(s.angle) * s.dist, s.dist * 0.25, math.cos(s.angle) * s.dist),
					s.center
				)
			end
		end
	end)
end

local function requireVisual(name: string): any
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local visuals = shared and shared:FindFirstChild("Visuals")
	local mod = visuals and visuals:FindFirstChild(name)
	if not mod then return nil end
	local ok, res = pcall(require, mod)
	return ok and res or nil
end

local function fallbackPart(color: Color3, size: Vector3, shape: Enum.PartType?): Instance
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Metal
	if shape then p.Shape = shape end
	return p
end

-- Fits camera around a model and returns (center, distance).
local function fit(vf: ViewportFrame, model: Instance): (Vector3, number)
	local cf, size
	if model:IsA("Model") then
		cf, size = model:GetBoundingBox()
	elseif model:IsA("BasePart") then
		cf, size = model.CFrame, model.Size
	else
		cf, size = CFrame.new(), Vector3.new(3, 3, 3)
	end
	local extent = math.max(size.X, size.Y, size.Z, 0.5)
	return cf.Position, extent * 1.7
end

local function setup(vf: ViewportFrame, model: Instance, spin: boolean, speed: number?)
	for _, c in vf:GetChildren() do
		c:Destroy()
	end
	model.Parent = vf
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vf
	vf.CurrentCamera = cam
	local center, dist = fit(vf, model)
	cam.CFrame = CFrame.lookAt(center + Vector3.new(0, dist * 0.25, dist), center)
	if spin then
		spinning[vf] = { cam = cam, center = center, dist = dist, angle = 0, speed = speed or 1.1 }
		ensureLoop()
	else
		spinning[vf] = nil
	end
end

local function newFrame(parent: Instance, props: { [string]: any }?): ViewportFrame
	local p = props or {}
	p.BackgroundTransparency = p.BackgroundTransparency or 1
	p.Size = p.Size or UDim2.new(1, 0, 1, 0)
	p.Parent = parent
	local vf = Theme.make("ViewportFrame", p)
	vf.Ambient = Color3.fromRGB(150, 140, 130)
	vf.LightColor = Color3.fromRGB(255, 240, 220)
	return vf
end

-- Renders a weapon record into a new ViewportFrame (or refreshes `into`).
function Viewport.weapon(parent: Instance, w: any, spin: boolean?, props: { [string]: any }?, into: ViewportFrame?): ViewportFrame
	local vf = into or newFrame(parent, props)
	local mat = Data.mat(w.m)
	local skin = { color = mat.color, material = mat.material, accent = mat.accent, glow = mat.glow }
	local model
	local mod = requireVisual("WeaponModels")
	if mod and mod.build then
		local ok, res = pcall(mod.build, w.c, w.d, w.r, skin, w.t)
		if ok and typeof(res) == "Instance" then model = res end
	end
	if not model then
		local m = Instance.new("Model")
		local blade = fallbackPart(mat.color, Vector3.new(0.4, 3.2, 0.12))
		blade.CFrame = CFrame.new(0, 0, 0)
		blade.Parent = m
		local guard = fallbackPart(Theme.Colors.brass, Vector3.new(1.4, 0.25, 0.25))
		guard.CFrame = CFrame.new(0, -1.5, 0)
		guard.Parent = m
		local grip = fallbackPart(Color3.fromRGB(90, 55, 35), Vector3.new(0.3, 1, 0.3))
		grip.CFrame = CFrame.new(0, -2.1, 0)
		grip.Parent = m
		model = m
	end
	setup(vf, model, spin == true)
	return vf
end

function Viewport.pet(parent: Instance, kind: string, spin: boolean?, props: { [string]: any }?, into: ViewportFrame?): ViewportFrame
	local vf = into or newFrame(parent, props)
	local def = Data.companion(kind)
	local rarity = Data.rarityIndex(def.rarity)
	local color = def.color or Color3.fromRGB(180, 180, 180)
	local model
	local mod = requireVisual("PetModels")
	if mod and mod.build then
		local ok, res = pcall(mod.build, def.modelKind or kind, color, rarity)
		if ok and typeof(res) == "Instance" then model = res end
	end
	if not model then
		model = fallbackPart(color, Vector3.new(2, 2, 2), Enum.PartType.Ball)
	end
	setup(vf, model, spin == true, 1.6)
	return vf
end

function Viewport.clear(vf: ViewportFrame)
	spinning[vf] = nil
	for _, c in vf:GetChildren() do
		c:Destroy()
	end
end

return Viewport
