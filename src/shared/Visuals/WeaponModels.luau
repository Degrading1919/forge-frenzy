--!strict
-- Procedural weapon models. Pure construction, no yields, no globals.
-- build(classIndex, designId, rarity, skin, trait) -> Model
--   * PrimaryPart = "Grip" (invisible, at the grip); weapon points along +Y.
--   * Every part is unanchored, non-colliding, massless and welded to Grip.
--   * Design table: DESIGNS[classKey][designId] = builder(ctx) -> Info.

local WeaponModels = {}

export type Skin = {
	color: Color3,
	material: string,
	accent: Color3?,
	glow: boolean?,
}

WeaponModels.ClassNames = { "Sword", "Greatsword", "Axe", "Dagger", "Hammer" }
WeaponModels.RarityColors = {
	Color3.fromRGB(200, 200, 200), -- Common
	Color3.fromRGB(90, 200, 90), -- Uncommon
	Color3.fromRGB(70, 140, 255), -- Rare
	Color3.fromRGB(170, 80, 255), -- Epic
	Color3.fromRGB(255, 170, 40), -- Legendary
	Color3.fromRGB(255, 60, 90), -- Mythic
}

local CLASS_KEYS = { "sword", "greatsword", "axe", "dagger", "hammer" }
local BRASS = Color3.fromRGB(196, 150, 70)
local WOOD = Color3.fromRGB(86, 56, 36)
local LEATHER = Color3.fromRGB(58, 38, 28)
local PI = math.pi

type Ctx = {
	model: Model,
	grip: Part,
	skin: Skin,
	material: Enum.Material,
	accent: Color3,
	glowColor: Color3,
	rarityColor: Color3,
	inlay: boolean,
}

-- top: highest y of the weapon; mid/len: centre/extent of the business end;
-- wy/wx: height and half-width where extra "wing" decoration attaches.
type Info = { top: number, mid: number, len: number, wy: number, wx: number }
type Builder = (Ctx) -> Info

------------------------------------------------------------------------
-- Primitive helpers
------------------------------------------------------------------------

local function resolveMaterial(name: string): Enum.Material
	local ok, mat = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(mat) == "EnumItem" then
		return mat :: Enum.Material
	end
	return Enum.Material.Metal
end

local function mk(ctx: Ctx, name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = ctx.model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ctx.grip
	weld.Part1 = p
	weld.Parent = p
	return p
end

-- kind: metal (skin), dark (skin, darker), trim (accent/brass), wood, leather, neon (glow colour)
local function P(ctx: Ctx, kind: string, name: string, size: Vector3, cf: CFrame, shape: Enum.PartType?): Part
	local color: Color3
	local mat: Enum.Material
	if kind == "metal" then
		color, mat = ctx.skin.color, ctx.material
	elseif kind == "dark" then
		color, mat = ctx.skin.color:Lerp(Color3.new(0, 0, 0), 0.35), ctx.material
	elseif kind == "trim" then
		color, mat = ctx.accent, Enum.Material.Metal
	elseif kind == "wood" then
		color, mat = WOOD, Enum.Material.Wood
	elseif kind == "leather" then
		color, mat = LEATHER, Enum.Material.Fabric
	else
		color, mat = ctx.glowColor, Enum.Material.Neon
	end
	return mk(ctx, name, shape or Enum.PartType.Block, size, cf, color, mat)
end

local function cfp(pos: Vector3, rot: Vector3?): CFrame
	local r = rot or Vector3.zero
	return CFrame.new(pos) * CFrame.Angles(r.X, r.Y, r.Z)
end

local function blk(ctx: Ctx, kind: string, name: string, size: Vector3, pos: Vector3, rot: Vector3?): Part
	return P(ctx, kind, name, size, cfp(pos, rot))
end

-- cylinder whose axis runs along Y (Roblox cylinders run along X natively)
local function cylY(ctx: Ctx, kind: string, name: string, diameter: number, length: number, pos: Vector3): Part
	return P(ctx, kind, name, Vector3.new(length, diameter, diameter), cfp(pos, Vector3.new(0, 0, PI / 2)), Enum.PartType.Cylinder)
end

local function ball(ctx: Ctx, kind: string, name: string, diameter: number, pos: Vector3): Part
	return P(ctx, kind, name, Vector3.new(diameter, diameter, diameter), cfp(pos), Enum.PartType.Ball)
end

-- flat rhombus (pointed on all four sides) in the XY plane, w wide/tall, t thick along Z
local function gem(ctx: Ctx, kind: string, name: string, w: number, t: number, pos: Vector3, extraRz: number?): Part
	local s = w / math.sqrt(2)
	return P(ctx, kind, name, Vector3.new(s, s, t), cfp(pos, Vector3.new(0, 0, PI / 4 + (extraRz or 0))))
end

local function hilt(ctx: Ctx, y0: number, y1: number, pommel: number)
	local len = y1 - y0
	cylY(ctx, "wood", "Handle", 0.32, len, Vector3.new(0, (y0 + y1) / 2, 0))
	cylY(ctx, "leather", "Wrap1", 0.4, 0.14, Vector3.new(0, y0 + len * 0.3, 0))
	cylY(ctx, "leather", "Wrap2", 0.4, 0.14, Vector3.new(0, y0 + len * 0.65, 0))
	ball(ctx, "trim", "Pommel", pommel, Vector3.new(0, y0 - pommel * 0.25, 0))
end

-- tapered blade of three slabs plus a rhombus tip; bend curves the blade toward +X. Returns tip height.
local function blade(ctx: Ctx, y0: number, y1: number, w0: number, w1: number, t: number, bend: number): number
	local len = y1 - y0
	local n = 3
	for i = 1, n do
		local f = (i - 0.5) / n
		local w = w0 + (w1 - w0) * f
		local rz = -math.atan2(2 * bend * f, len)
		blk(ctx, "metal", "Blade" .. i, Vector3.new(w, len / n * 1.05, t), Vector3.new(bend * f * f, y0 + len * f, 0), Vector3.new(0, 0, rz))
	end
	gem(ctx, "metal", "Tip", w1, t, Vector3.new(bend, y1, 0), -math.atan2(2 * bend, len))
	return y1 + w1 * 0.5
end

local function inlayBlade(ctx: Ctx, y0: number, y1: number, t: number, bend: number)
	if not ctx.inlay then
		return
	end
	local len = y1 - y0
	for i = 1, 3 do
		local f = (i - 0.5) / 3
		local rz = -math.atan2(2 * bend * f, len)
		blk(ctx, "neon", "Inlay" .. i, Vector3.new(0.07, len / 3 * 1.05, t + 0.04), Vector3.new(bend * f * f, y0 + len * f, 0), Vector3.new(0, 0, rz))
	end
end

-- zig-zag blade (flamberge / kris)
local function waveBlade(ctx: Ctx, y0: number, y1: number, w: number, t: number, amp: number, n: number): number
	local seg = (y1 - y0) / n
	local x = 0.0
	local wd = w
	for i = 1, n do
		x = amp * math.sin(i * 1.7)
		wd = w * (1 - 0.4 * (i - 1) / n)
		local pos = Vector3.new(x, y0 + seg * (i - 0.5), 0)
		blk(ctx, "metal", "Blade" .. i, Vector3.new(wd, seg * 1.15, t), pos, Vector3.new(0, 0, 0.12 * math.cos(i * 1.7)))
		if ctx.inlay then
			blk(ctx, "neon", "Inlay" .. i, Vector3.new(0.07, seg * 1.15, t + 0.04), pos, Vector3.new(0, 0, 0.12 * math.cos(i * 1.7)))
		end
	end
	gem(ctx, "metal", "Tip", wd * 0.8, t, Vector3.new(x, y1, 0))
	return y1 + wd * 0.4
end

------------------------------------------------------------------------
-- Design builders
------------------------------------------------------------------------

local DESIGNS: { [string]: { [string]: Builder } } = {
	sword = {},
	greatsword = {},
	axe = {},
	dagger = {},
	hammer = {},
}

-- Swords ---------------------------------------------------------------

DESIGNS.sword.sword_1 = function(ctx)
	hilt(ctx, -0.6, 0.6, 0.42)
	blk(ctx, "trim", "Guard", Vector3.new(1.6, 0.24, 0.34), Vector3.new(0, 0.7, 0))
	local top = blade(ctx, 0.82, 3.7, 0.62, 0.42, 0.14, 0)
	blk(ctx, "dark", "Fuller", Vector3.new(0.12, 2.1, 0.18), Vector3.new(0, 2.1, 0))
	inlayBlade(ctx, 0.82, 3.7, 0.18, 0)
	return { top = top, mid = 2.3, len = 3.0, wy = 0.7, wx = 0.8 }
end

DESIGNS.sword.sword_2 = function(ctx)
	hilt(ctx, -0.6, 0.6, 0.46)
	blk(ctx, "trim", "Guard", Vector3.new(1.2, 0.24, 0.34), Vector3.new(0, 0.7, 0))
	blk(ctx, "trim", "Knuckle", Vector3.new(0.12, 1.35, 0.3), Vector3.new(0.52, 0.07, 0), Vector3.new(0, 0, -0.12))
	local top = blade(ctx, 0.82, 3.4, 0.5, 0.95, 0.16, 0.55)
	inlayBlade(ctx, 0.82, 3.4, 0.16, 0.55)
	return { top = top, mid = 2.2, len = 2.7, wy = 0.7, wx = 0.6 }
end

DESIGNS.sword.sword_3 = function(ctx)
	hilt(ctx, -0.6, 0.6, 0.4)
	cylY(ctx, "trim", "Cup", 1.3, 0.12, Vector3.new(0, 0.7, 0))
	local cx, cy, r, n = 0.62, 0.2, 0.5, 8
	local chord = 2 * r * math.sin(PI / n) * 1.15
	for i = 1, n do
		local a = (i - 1) / n * PI * 2
		blk(ctx, "trim", "Ring" .. i, Vector3.new(0.1, chord, 0.1), Vector3.new(cx + r * math.cos(a), cy + r * math.sin(a), 0), Vector3.new(0, 0, a))
	end
	blk(ctx, "trim", "Quillon", Vector3.new(1.0, 0.1, 0.1), Vector3.new(-0.3, 0.8, 0))
	local top = blade(ctx, 0.76, 4.7, 0.2, 0.1, 0.1, 0)
	inlayBlade(ctx, 0.76, 4.7, 0.1, 0)
	return { top = top, mid = 2.8, len = 3.9, wy = 0.8, wx = 0.65 }
end

-- Greatswords ----------------------------------------------------------

DESIGNS.greatsword.greatsword_1 = function(ctx)
	hilt(ctx, -0.8, 0.8, 0.55)
	blk(ctx, "trim", "Guard", Vector3.new(2.4, 0.3, 0.42), Vector3.new(0, 0.92, 0))
	ball(ctx, "trim", "GuardL", 0.45, Vector3.new(-1.2, 0.92, 0))
	ball(ctx, "trim", "GuardR", 0.45, Vector3.new(1.2, 0.92, 0))
	local top = blade(ctx, 1.1, 5.5, 1.0, 0.7, 0.2, 0)
	blk(ctx, "dark", "Fuller", Vector3.new(0.22, 3.0, 0.26), Vector3.new(0, 3.2, 0))
	inlayBlade(ctx, 1.1, 5.5, 0.26, 0)
	return { top = top, mid = 3.3, len = 4.4, wy = 0.92, wx = 1.2 }
end

DESIGNS.greatsword.greatsword_2 = function(ctx)
	hilt(ctx, -0.8, 0.8, 0.5)
	blk(ctx, "trim", "Guard", Vector3.new(2.0, 0.3, 0.42), Vector3.new(0, 0.92, 0))
	gem(ctx, "trim", "HornL", 0.6, 0.3, Vector3.new(-1.05, 0.62, 0))
	gem(ctx, "trim", "HornR", 0.6, 0.3, Vector3.new(1.05, 0.62, 0))
	local top = waveBlade(ctx, 1.1, 5.4, 0.9, 0.18, 0.15, 6)
	return { top = top, mid = 3.2, len = 4.3, wy = 0.92, wx = 1.0 }
end

DESIGNS.greatsword.greatsword_3 = function(ctx)
	hilt(ctx, -0.8, 0.8, 0.5)
	blk(ctx, "trim", "Guard", Vector3.new(2.0, 0.28, 0.4), Vector3.new(0, 0.92, 0))
	gem(ctx, "trim", "SpikeL", 0.5, 0.3, Vector3.new(-1.05, 0.92, 0))
	gem(ctx, "trim", "SpikeR", 0.5, 0.3, Vector3.new(1.05, 0.92, 0))
	blk(ctx, "metal", "Ricasso", Vector3.new(0.5, 0.9, 0.2), Vector3.new(0, 1.5, 0))
	gem(ctx, "metal", "LugL", 0.55, 0.16, Vector3.new(-0.5, 1.95, 0))
	gem(ctx, "metal", "LugR", 0.55, 0.16, Vector3.new(0.5, 1.95, 0))
	local top = blade(ctx, 1.95, 5.7, 0.9, 0.6, 0.2, 0)
	blk(ctx, "dark", "Fuller", Vector3.new(0.18, 2.6, 0.24), Vector3.new(0, 3.9, 0))
	inlayBlade(ctx, 1.95, 5.7, 0.24, 0)
	return { top = top, mid = 3.8, len = 3.8, wy = 0.92, wx = 1.0 }
end

-- Axes -----------------------------------------------------------------

DESIGNS.axe.axe_1 = function(ctx)
	hilt(ctx, -0.8, 3.4, 0.45)
	blk(ctx, "trim", "Socket", Vector3.new(0.55, 0.8, 0.55), Vector3.new(0, 2.9, 0))
	blk(ctx, "metal", "Body", Vector3.new(0.8, 1.1, 0.24), Vector3.new(0.65, 2.9, 0))
	blk(ctx, "metal", "Edge", Vector3.new(0.28, 1.9, 0.2), Vector3.new(1.15, 2.9, 0))
	gem(ctx, "metal", "HornT", 0.5, 0.2, Vector3.new(1.15, 3.85, 0))
	gem(ctx, "metal", "HornB", 0.5, 0.2, Vector3.new(1.15, 1.95, 0))
	gem(ctx, "metal", "Poll", 0.45, 0.24, Vector3.new(-0.5, 2.9, 0))
	if ctx.inlay then
		blk(ctx, "neon", "Inlay", Vector3.new(0.07, 1.7, 0.24), Vector3.new(1.3, 2.9, 0))
	end
	return { top = 4.1, mid = 2.9, len = 2.2, wy = 2.4, wx = 0.4 }
end

DESIGNS.axe.axe_2 = function(ctx)
	hilt(ctx, -0.8, 3.4, 0.45)
	blk(ctx, "trim", "Socket", Vector3.new(0.55, 0.8, 0.55), Vector3.new(0, 2.9, 0))
	for _, s in { 1, -1 } do
		local tag = if s > 0 then "R" else "L"
		blk(ctx, "metal", "Body" .. tag, Vector3.new(0.7, 1.0, 0.24), Vector3.new(s * 0.6, 2.9, 0))
		blk(ctx, "metal", "Edge" .. tag, Vector3.new(0.26, 1.7, 0.2), Vector3.new(s * 1.05, 2.9, 0))
		gem(ctx, "metal", "HornT" .. tag, 0.45, 0.2, Vector3.new(s * 1.05, 3.75, 0))
		gem(ctx, "metal", "HornB" .. tag, 0.45, 0.2, Vector3.new(s * 1.05, 2.05, 0))
		if ctx.inlay then
			blk(ctx, "neon", "Inlay" .. tag, Vector3.new(0.07, 1.5, 0.24), Vector3.new(s * 1.2, 2.9, 0))
		end
	end
	return { top = 4.0, mid = 2.9, len = 2.0, wy = 2.4, wx = 0.4 }
end

DESIGNS.axe.axe_3 = function(ctx)
	hilt(ctx, -0.8, 3.8, 0.45)
	blk(ctx, "trim", "Socket", Vector3.new(0.55, 0.8, 0.55), Vector3.new(0, 3.0, 0))
	blk(ctx, "metal", "Body", Vector3.new(0.7, 1.2, 0.24), Vector3.new(0.6, 3.0, 0))
	blk(ctx, "metal", "Edge", Vector3.new(0.26, 1.5, 0.2), Vector3.new(1.05, 2.9, 0))
	gem(ctx, "metal", "Beard", 0.9, 0.2, Vector3.new(1.0, 2.15, 0))
	gem(ctx, "metal", "HornT", 0.5, 0.2, Vector3.new(1.05, 3.65, 0))
	blk(ctx, "metal", "SpearShaft", Vector3.new(0.28, 0.5, 0.2), Vector3.new(0, 4.0, 0))
	gem(ctx, "metal", "SpearTip", 0.45, 0.2, Vector3.new(0, 4.3, 0))
	blk(ctx, "metal", "HookArm", Vector3.new(0.6, 0.22, 0.22), Vector3.new(-0.45, 3.1, 0))
	gem(ctx, "metal", "HookTip", 0.4, 0.2, Vector3.new(-0.85, 3.1, 0))
	if ctx.inlay then
		blk(ctx, "neon", "Inlay", Vector3.new(0.07, 1.3, 0.24), Vector3.new(1.2, 2.9, 0))
	end
	return { top = 4.5, mid = 3.0, len = 2.4, wy = 2.5, wx = 0.4 }
end

-- Daggers --------------------------------------------------------------

DESIGNS.dagger.dagger_1 = function(ctx)
	hilt(ctx, -0.4, 0.4, 0.34)
	blk(ctx, "trim", "Guard", Vector3.new(0.95, 0.2, 0.3), Vector3.new(0, 0.5, 0))
	local top = blade(ctx, 0.6, 2.3, 0.38, 0.2, 0.1, 0)
	inlayBlade(ctx, 0.6, 2.3, 0.1, 0)
	return { top = top, mid = 1.5, len = 1.7, wy = 0.5, wx = 0.45 }
end

DESIGNS.dagger.dagger_2 = function(ctx)
	hilt(ctx, -0.4, 0.4, 0.34)
	blk(ctx, "trim", "Guard", Vector3.new(0.8, 0.2, 0.3), Vector3.new(0, 0.5, 0))
	gem(ctx, "trim", "FangL", 0.3, 0.26, Vector3.new(-0.45, 0.35, 0))
	gem(ctx, "trim", "FangR", 0.3, 0.26, Vector3.new(0.45, 0.35, 0))
	local top = waveBlade(ctx, 0.6, 2.5, 0.34, 0.1, 0.1, 5)
	return { top = top, mid = 1.6, len = 1.9, wy = 0.5, wx = 0.4 }
end

DESIGNS.dagger.dagger_3 = function(ctx)
	hilt(ctx, -0.4, 0.4, 0.34)
	blk(ctx, "trim", "Guard", Vector3.new(0.9, 0.2, 0.3), Vector3.new(0, 0.5, 0))
	local top = blade(ctx, 0.6, 2.5, 0.32, 0.18, 0.1, 0)
	for _, s in { 1, -1 } do
		local tag = if s > 0 then "R" else "L"
		blk(ctx, "metal", "Fang" .. tag, Vector3.new(0.14, 1.2, 0.09), Vector3.new(s * 0.32, 1.15, 0), Vector3.new(0, 0, -s * 0.2))
		gem(ctx, "metal", "FangTip" .. tag, 0.16, 0.09, Vector3.new(s * 0.43, 1.78, 0))
	end
	inlayBlade(ctx, 0.6, 2.5, 0.1, 0)
	return { top = top, mid = 1.6, len = 1.9, wy = 0.5, wx = 0.45 }
end

-- Hammers --------------------------------------------------------------

DESIGNS.hammer.hammer_1 = function(ctx)
	hilt(ctx, -0.7, 3.3, 0.45)
	blk(ctx, "metal", "Head", Vector3.new(2.0, 1.1, 1.1), Vector3.new(0, 3.3, 0))
	blk(ctx, "trim", "CapL", Vector3.new(0.2, 1.25, 1.25), Vector3.new(-1.05, 3.3, 0))
	blk(ctx, "trim", "CapR", Vector3.new(0.2, 1.25, 1.25), Vector3.new(1.05, 3.3, 0))
	gem(ctx, "trim", "Finial", 0.5, 0.3, Vector3.new(0, 3.95, 0))
	if ctx.inlay then
		blk(ctx, "neon", "InlayL", Vector3.new(0.1, 1.14, 1.14), Vector3.new(-0.5, 3.3, 0))
		blk(ctx, "neon", "InlayR", Vector3.new(0.1, 1.14, 1.14), Vector3.new(0.5, 3.3, 0))
	end
	return { top = 4.2, mid = 3.3, len = 1.4, wy = 2.7, wx = 0.4 }
end

DESIGNS.hammer.hammer_2 = function(ctx)
	hilt(ctx, -0.7, 3.3, 0.45)
	P(ctx, "metal", "Head", Vector3.new(2.2, 1.4, 1.4), cfp(Vector3.new(0, 3.3, 0)), Enum.PartType.Cylinder)
	for _, s in { 1, -1 } do
		local tag = if s > 0 then "R" else "L"
		P(ctx, "trim", "Band" .. tag, Vector3.new(0.2, 1.5, 1.5), cfp(Vector3.new(s * 0.7, 3.3, 0)), Enum.PartType.Cylinder)
		P(ctx, "dark", "End" .. tag, Vector3.new(0.2, 1.3, 1.3), cfp(Vector3.new(s * 1.15, 3.3, 0)), Enum.PartType.Cylinder)
	end
	gem(ctx, "trim", "Finial", 0.5, 0.3, Vector3.new(0, 4.1, 0))
	if ctx.inlay then
		P(ctx, "neon", "Inlay", Vector3.new(0.14, 1.46, 1.46), cfp(Vector3.new(0, 3.3, 0)), Enum.PartType.Cylinder)
	end
	return { top = 4.35, mid = 3.3, len = 1.6, wy = 2.7, wx = 0.4 }
end

DESIGNS.hammer.hammer_3 = function(ctx)
	hilt(ctx, -0.7, 3.3, 0.45)
	blk(ctx, "trim", "Socket", Vector3.new(0.6, 0.8, 0.7), Vector3.new(0, 3.3, 0))
	blk(ctx, "metal", "Striker", Vector3.new(0.9, 1.0, 0.9), Vector3.new(0.65, 3.3, 0))
	blk(ctx, "trim", "Face", Vector3.new(0.14, 0.8, 0.8), Vector3.new(1.15, 3.3, 0))
	blk(ctx, "metal", "SpikeBase", Vector3.new(0.6, 0.55, 0.55), Vector3.new(-0.55, 3.3, 0))
	gem(ctx, "metal", "SpikeTip", 0.55, 0.5, Vector3.new(-0.85, 3.3, 0))
	gem(ctx, "trim", "Finial", 0.5, 0.3, Vector3.new(0, 3.95, 0))
	if ctx.inlay then
		blk(ctx, "neon", "Inlay", Vector3.new(0.1, 0.94, 0.94), Vector3.new(0.65, 3.3, 0))
	end
	return { top = 4.2, mid = 3.3, len = 1.5, wy = 2.7, wx = 0.4 }
end

-- Legendary / Mythic: elaborated versions of the _2 / _3 cores ---------

local function extras(ctx: Ctx, info: Info, tier: string)
	local top = info.top
	for _, s in { 1, -1 } do
		local tag = if s > 0 then "R" else "L"
		gem(ctx, "trim", "WingA" .. tag, 0.7, 0.12, Vector3.new(s * (info.wx + 0.35), info.wy + 0.15, 0))
		gem(ctx, "trim", "WingB" .. tag, 0.5, 0.12, Vector3.new(s * (info.wx + 0.7), info.wy - 0.15, 0))
	end
	gem(ctx, "neon", "Crown", 0.4, 0.14, Vector3.new(0, top + 0.45, 0))
	if tier == "mythic" then
		gem(ctx, "neon", "CrownL", 0.28, 0.12, Vector3.new(-0.4, top + 0.25, 0))
		gem(ctx, "neon", "CrownR", 0.28, 0.12, Vector3.new(0.4, top + 0.25, 0))
		for i = 1, 4 do
			local a = i * PI / 2 + 0.5
			local pos = Vector3.new(math.cos(a) * 0.95, info.mid + (i - 2.5) * info.len * 0.2, math.sin(a) * 0.95)
			local s = 0.4 / math.sqrt(2)
			P(ctx, "neon", "Rune" .. i, Vector3.new(s, s, 0.1), CFrame.new(pos) * CFrame.Angles(0, -a, PI / 4))
		end
	end
end

for _, key in CLASS_KEYS do
	local d = DESIGNS[key]
	local legendaryCore = d[key .. "_2"]
	local mythicCore = d[key .. "_3"]
	d[key .. "_legendary"] = function(ctx)
		ctx.inlay = true
		local info = legendaryCore(ctx)
		extras(ctx, info, "legendary")
		return info
	end
	d[key .. "_mythic"] = function(ctx)
		ctx.inlay = true
		local info = mythicCore(ctx)
		extras(ctx, info, "mythic")
		return info
	end
end

------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------

local function fade(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local function emitter(parent: Instance, name: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function addTrait(fx: Part, trait: string)
	if trait == "Infernal" then
		emitter(fx, "TraitFx", {
			Color = ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 60, 0)),
			Size = NumberSequence.new(0.3, 0),
			Transparency = fade(0, 1),
			Lifetime = NumberRange.new(0.7, 1.3),
			Rate = 10,
			Speed = NumberRange.new(0.5, 1.5),
			Acceleration = Vector3.new(0, 3, 0),
			SpreadAngle = Vector2.new(30, 30),
			LightEmission = 1,
		})
	elseif trait == "Frozen" then
		emitter(fx, "TraitFx", {
			Color = ColorSequence.new(Color3.fromRGB(215, 245, 255), Color3.fromRGB(120, 190, 255)),
			Size = NumberSequence.new(0.25, 0.08),
			Transparency = fade(0.1, 1),
			Lifetime = NumberRange.new(1.2, 1.8),
			Rate = 7,
			Speed = NumberRange.new(0.3, 1),
			Acceleration = Vector3.new(0, -1.5, 0),
			SpreadAngle = Vector2.new(60, 60),
			LightEmission = 0.5,
		})
	elseif trait == "Stormforged" then
		emitter(fx, "TraitFx", {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 150), Color3.fromRGB(120, 170, 255)),
			Size = NumberSequence.new(0.18, 0),
			Transparency = fade(0, 1),
			Lifetime = NumberRange.new(0.2, 0.4),
			Rate = 14,
			Speed = NumberRange.new(4, 8),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		})
	elseif trait == "Radiant" then
		emitter(fx, "TraitFx", {
			Color = ColorSequence.new(Color3.fromRGB(255, 245, 190), Color3.fromRGB(255, 210, 90)),
			Size = NumberSequence.new(0.5, 1.6),
			Transparency = fade(0.4, 1),
			Lifetime = NumberRange.new(1.0, 1.6),
			Rate = 3,
			Speed = NumberRange.new(0, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-30, 30),
			LightEmission = 1,
		})
	end
end

local function validate(model: Model): boolean
	if not model.PrimaryPart then
		return false
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Anchored or d.CanCollide then
				return false
			end
		end
	end
	return true
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

WeaponModels.validate = validate

function WeaponModels.build(classIndex: number, designId: string, rarity: number, skin: Skin, trait: string?): Model
	local ci = math.clamp(math.floor(classIndex or 1), 1, 5)
	local rar = math.clamp(math.floor(rarity or 1), 1, 6)
	local key = CLASS_KEYS[ci]
	local designs = DESIGNS[key]

	local id = string.lower(designId or "")
	if not designs[id] then
		id = key .. "_1"
	end
	if rar >= 6 then
		id = key .. "_mythic"
	elseif rar == 5 and id ~= key .. "_mythic" then
		id = key .. "_legendary"
	end

	local rarityColor = WeaponModels.RarityColors[rar]
	local elaborate = id == key .. "_legendary" or id == key .. "_mythic"
	local glow = skin.glow == true
	local glowColor = if glow then (skin.accent or skin.color) elseif rar >= 5 then rarityColor else (skin.accent or rarityColor)

	local model = Instance.new("Model")
	model.Name = WeaponModels.ClassNames[ci] .. "_" .. id

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.3, 0.3, 0.3)
	grip.CFrame = CFrame.new()
	grip.Transparency = 1
	grip.Anchored = false
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = false
	grip.Massless = true
	grip.Parent = model
	model.PrimaryPart = grip

	local ctx: Ctx = {
		model = model,
		grip = grip,
		skin = skin,
		material = resolveMaterial(skin.material),
		accent = skin.accent or BRASS,
		glowColor = glowColor,
		rarityColor = rarityColor,
		inlay = glow or rar >= 5 or elaborate,
	}
	local info = designs[id](ctx)

	-- Invisible emitter anchor over the business end of the weapon.
	local fx = mk(ctx, "FX", Enum.PartType.Block, Vector3.new(0.6, math.max(info.len, 0.6), 0.6), CFrame.new(0, info.mid, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	fx.Transparency = 1

	if glow then
		local light = Instance.new("PointLight")
		light.Name = "GlowLight"
		light.Color = glowColor
		light.Range = 7
		light.Brightness = 1.2
		light.Parent = fx
	end

	if rar >= 3 then
		local hl = Instance.new("Highlight")
		hl.Name = "RarityGlow"
		hl.Adornee = model
		hl.FillTransparency = 1
		hl.OutlineColor = rarityColor
		hl.OutlineTransparency = if rar >= 6 then 0.35 elseif rar == 5 then 0.5 elseif rar == 4 then 0.65 else 0.78
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
	end

	if rar >= 4 then
		local strong = rar >= 5
		emitter(fx, "Sparkles", {
			Color = ColorSequence.new(rarityColor),
			Size = NumberSequence.new(if strong then 0.4 else 0.25, 0),
			Transparency = fade(0, 1),
			Lifetime = NumberRange.new(0.8, 1.4),
			Rate = if rar >= 6 then 26 elseif rar == 5 then 14 else 6,
			Speed = NumberRange.new(0.3, if strong then 1.6 else 0.8),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 0.9,
		})
	end

	if trait then
		addTrait(fx, trait)
	end

	assert(validate(model), "WeaponModels.build produced an invalid model")
	return model
end

return WeaponModels
