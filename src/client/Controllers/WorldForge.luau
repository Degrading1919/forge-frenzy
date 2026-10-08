--!nonstrict
--[[
	Forge station presentation in the world (v2): for every forge in your workshop, a glowing
	blank heats on the anvil, a hammer bangs and sparks fly while it strikes (your taps, or a
	steady rhythm on Auto), steam bursts at the quench, and the finished weapon pops up just
	above the anvil (owner feedback: previews floated too high) with a rarity-colored glow.
]]
local RunService = game:GetService("RunService")

local Common = require(script.Parent.WorldUtil.Common)
local Sfx = require(script.Parent.WorldUtil.Sfx)
local WeaponDisplay = require(script.Parent.WorldUtil.WeaponDisplay)
local Net = require(script.Parent.Parent.Net)
local ForgeSignals = require(script.Parent.Parent.UI.ForgeSignals)
local ForgeGame = require(script.Parent.Parent.UI.ForgeGame)

local WorldForge = { Priority = 0 }

local RESULT_TIME = 3.5
local stations = {} -- [index] = state

local function refs(index)
	local forge = Common.myMachine("Forge" .. index)
	if not forge then
		return nil
	end
	local anvil = forge:FindFirstChild("Anvil")
	local tank = forge:FindFirstChild("Tank")
	if not anvil then
		return nil
	end
	return {
		weaponSpot = anvil:FindFirstChild("WeaponSpot"),
		sparkSpot = anvil:FindFirstChild("SparkSpot"),
		steamSpot = tank and tank:FindFirstChild("SteamSpot"),
		fire = forge:FindFirstChild("FireMouth"),
	}
end

local function stateOf(index)
	local s = stations[index]
	if not s then
		s = { phase = "idle", blank = nil, hammer = nil, hammerT = nil, result = nil, lastAutoHit = 0 }
		stations[index] = s
	end
	return s
end

local function emitter(att, kind)
	if not att then
		return nil
	end
	local e = att:FindFirstChild("Forge" .. kind)
	if e then
		return e
	end
	e = Instance.new("ParticleEmitter")
	e.Name = "Forge" .. kind
	e.Enabled = false
	e.Rate = 0
	e.LightEmission = 1
	if kind == "Sparks" then
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Lifetime = NumberRange.new(0.35, 0.8)
		e.Speed = NumberRange.new(14, 28)
		e.SpreadAngle = Vector2.new(70, 70)
		e.Acceleration = Vector3.new(0, -45, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		e.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 110, 30))
	else
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.LightEmission = 0.1
		e.Lifetime = NumberRange.new(1.2, 2.2)
		e.Speed = NumberRange.new(5, 9)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Acceleration = Vector3.new(0, 3, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		e.Color = ColorSequence.new(Color3.fromRGB(235, 240, 245))
	end
	e.Parent = att
	return e
end

local function clearBlank(s)
	if s.blank then
		s.blank:Destroy()
		s.blank = nil
	end
end

local function startHeat(index)
	local r = refs(index)
	local s = stateOf(index)
	if not r or not r.weaponSpot then
		return
	end
	clearBlank(s)
	local bar = Instance.new("Part")
	bar.Name = "HeatBlank"
	bar.Size = Vector3.new(2.6, 0.26, 0.6)
	bar.Material = Enum.Material.Neon
	bar.Color = Color3.fromRGB(255, 120, 30)
	bar.Anchored = true
	bar.CanCollide = false
	bar.CanQuery = false
	bar.CanTouch = false
	bar.CFrame = CFrame.new(r.weaponSpot.WorldPosition) * CFrame.new(0, -0.7, 0)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = 12
	light.Brightness = 2
	light.Parent = bar
	bar.Parent = Common.fxFolder()
	s.blank = bar
end

local function hammerHit(index, loud)
	local r = refs(index)
	local s = stateOf(index)
	if not r then
		return
	end
	if loud then
		Sfx.play("hammer_hit", r.sparkSpot or r.weaponSpot)
	end
	if Common.vfx() then
		local e = emitter(r.sparkSpot, "Sparks")
		if e then
			e:Emit(if loud then 18 else 8)
		end
	end
	s.hammerT = 0
	if not s.hammer then
		local m = Instance.new("Model")
		m.Name = "ForgeHammer"
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.35, 3, 0.35)
		handle.Color = Color3.fromRGB(110, 75, 45)
		handle.Material = Enum.Material.Wood
		handle.Parent = m
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1.4, 0.85, 0.85)
		head.Color = Color3.fromRGB(150, 155, 165)
		head.Material = Enum.Material.Metal
		head.Parent = m
		Common.inert(m)
		m.Parent = Common.fxFolder()
		s.hammer = m
	end
end

local function quench(index)
	local r = refs(index)
	local s = stateOf(index)
	if not r then
		return
	end
	clearBlank(s)
	if s.hammer then
		s.hammer:Destroy()
		s.hammer = nil
	end
	if Common.vfx() then
		local e = emitter(r.steamSpot, "Steam")
		if e then
			e:Emit(20)
		end
	end
end

local function clearResult(s)
	if s.result then
		s.result.root:Destroy()
		s.result = nil
	end
end

local function showResult(index, w, loud)
	local r = refs(index)
	local s = stateOf(index)
	if not r or not r.weaponSpot or type(w) ~= "table" then
		return
	end
	clearResult(s)
	local rarity = w.r or 1
	local color = Common.rarityColor(rarity)
	local base = r.weaponSpot.WorldPosition
	local root = Instance.new("Folder")
	root.Name = "ForgeResult" .. index
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = base + Vector3.new(0, 1.4, 0)
	anchor.Parent = root
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8 + rarity * 3
	light.Brightness = 1.5 + rarity * 0.4
	light.Parent = anchor
	local inst, fix = WeaponDisplay.build(w, 3)
	inst.Parent = root
	if Common.vfx() and rarity >= 5 then
		local p0 = Instance.new("Attachment")
		p0.Parent = anchor
		local p1 = Instance.new("Attachment")
		p1.Position = Vector3.new(0, 300, 0)
		p1.Parent = anchor
		local pillar = Instance.new("Beam")
		pillar.Attachment0 = p0
		pillar.Attachment1 = p1
		pillar.Color = ColorSequence.new(color)
		pillar.LightEmission = 1
		pillar.Width0 = 5
		pillar.Width1 = 5
		pillar.FaceCamera = true
		pillar.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.9) })
		pillar.Parent = anchor
	end
	root.Parent = Common.fxFolder()
	s.result = { root = root, inst = inst, fix = fix, base = anchor.Position, t0 = os.clock() }
	if loud then
		if rarity >= 5 then
			Sfx.play("reveal_legendary", r.weaponSpot)
		elseif rarity >= 3 then
			Sfx.play("reveal_rare", r.weaponSpot)
		else
			Sfx.play("reveal_common", r.weaponSpot)
		end
	end
end

local function step(dt)
	local now = os.clock()
	for index, s in stations do
		if s.blank then
			local glow = 0.5 + 0.5 * math.sin(now * 6)
			s.blank.Color = Color3.fromRGB(255, 100 + glow * 80, 20 + glow * 40)
		end
		-- Auto forges hammer on a steady rhythm during their strike phase.
		if s.phase == "strike" and s.auto and now - s.lastAutoHit > 0.45 then
			s.lastAutoHit = now
			hammerHit(index, false)
		end
		if s.hammer then
			local r = refs(index)
			if r and r.weaponSpot then
				s.hammerT = (s.hammerT or 0) + dt
				local swing = math.clamp(s.hammerT / 0.18, 0, 1)
				local angle = math.rad(-70 + 70 * (1 - (1 - swing) ^ 2))
				local pivot = CFrame.new(r.weaponSpot.WorldPosition + Vector3.new(1.6, 0.4, 0))
				local cf = pivot * CFrame.Angles(0, 0, angle) * CFrame.new(-1.2, 1.4, 0)
				s.hammer.Handle.CFrame = cf
				s.hammer.Head.CFrame = cf * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
		if s.result then
			local t = now - s.result.t0
			if t > RESULT_TIME then
				clearResult(s)
			else
				local bob = math.sin(t * 3) * 0.15
				local rise = math.min(1, t / 0.25)
				s.result.inst:PivotTo(CFrame.new(s.result.base + Vector3.new(0, bob + rise * 0.6, 0)) * CFrame.Angles(0, t * 2, 0) * s.result.fix)
			end
		end
	end
end

function WorldForge.start()
	Net.on("ForgePhase", function(info)
		if type(info) ~= "table" or not info.station then
			return
		end
		local s = stateOf(info.station)
		s.phase = info.phase
		s.auto = info.mode ~= "manual"
		if info.phase == "heat" then
			startHeat(info.station)
		elseif info.phase == "strike" then
			if not s.blank then startHeat(info.station) end
		elseif info.phase == "quench" then
			quench(info.station)
		elseif info.phase == "cancelled" or info.phase == "stopped" or info.phase == "waiting" then
			clearBlank(s)
			if s.hammer then
				s.hammer:Destroy()
				s.hammer = nil
			end
		end
	end)
	Net.on("ForgeResult", function(payload)
		if type(payload) ~= "table" or not payload.station then
			return
		end
		local first = payload.results and payload.results[1]
		if first and first.weapon then
			showResult(payload.station, first.weapon, not payload.auto or first.weapon.r >= 4)
		end
	end)
	ForgeSignals.Hit:Connect(function()
		local index = ForgeGame.station() or 1
		hammerHit(index, true)
	end)
	RunService.Heartbeat:Connect(step)
end

return WorldForge
