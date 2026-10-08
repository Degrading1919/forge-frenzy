--!nonstrict
-- Anvil presentation during forging: heated blank, sparks, hammer, quench steam, reveal.
local RunService = game:GetService("RunService")

local Common = require(script.Parent.WorldUtil.Common)
local Sfx = require(script.Parent.WorldUtil.Sfx)
local WeaponDisplay = require(script.Parent.WorldUtil.WeaponDisplay)
local Net = require(script.Parent.Parent.Net)

local WorldForge = { Priority = 0 }

local RESULT_TIME = 6
local conn = nil
local S = {
	heating = false,
	blank = nil,
	cool = nil, -- time quench started
	hammer = nil,
	hammerT = nil,
	flash = 0,
	result = nil,
	lastResultId = nil,
	lastResultAt = 0,
}

local function refs()
	local anvil = Common.myMachine("Anvil")
	if not anvil then
		return nil
	end
	local face = anvil:FindFirstChild("Face")
	local trough = anvil:FindFirstChild("Trough")
	local r = {
		weaponSpot = face and face:FindFirstChild("WeaponSpot"),
		sparkSpot = face and face:FindFirstChild("SparkSpot"),
		steamSpot = trough and trough:FindFirstChild("SteamSpot"),
	}
	if not r.weaponSpot then
		return nil
	end
	return r
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
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.LightEmission = 1
	if kind == "Sparks" then
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

local function spotCF(att)
	return CFrame.new(att.WorldPosition)
end

local function destroyBlank()
	if S.blank then
		S.blank:Destroy()
		S.blank = nil
	end
	S.cool = nil
end

local function ensureLoop() end -- forward decl, set below

local function startHeat()
	if S.heating then
		return
	end
	local r = refs()
	if not r then
		return
	end
	S.heating = true
	destroyBlank()
	local bar = Instance.new("Part")
	bar.Name = "HeatBlank"
	bar.Size = Vector3.new(3.2, 0.28, 0.7)
	bar.Material = Enum.Material.Neon
	bar.Color = Color3.fromRGB(255, 120, 30)
	bar.Anchored = true
	bar.CanCollide = false
	bar.CanQuery = false
	bar.CanTouch = false
	bar.CFrame = spotCF(r.weaponSpot) * CFrame.new(0, 0.2, 0)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = 14
	light.Brightness = 2
	light.Parent = bar
	bar.Parent = Common.fxFolder()
	S.blank = bar
	Sfx.play("heat", r.weaponSpot)
	ensureLoop()
end

local function doHit()
	local r = refs()
	if not r then
		return
	end
	if not S.heating then
		startHeat()
	end
	Sfx.play("hammer_hit", r.sparkSpot or r.weaponSpot)
	if Common.vfx() then
		local e = emitter(r.sparkSpot, "Sparks")
		if e then
			e:Emit(18)
		end
	end
	S.flash = 1
	S.hammerT = 0
	if not S.hammer then
		local m = Instance.new("Model")
		m.Name = "ForgeHammer"
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.35, 3.2, 0.35)
		handle.Color = Color3.fromRGB(110, 75, 45)
		handle.Material = Enum.Material.Wood
		handle.Parent = m
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(1.5, 0.9, 0.9)
		head.Color = Color3.fromRGB(150, 155, 165)
		head.Material = Enum.Material.Metal
		head.Parent = m
		Common.inert(m)
		m.Parent = Common.fxFolder()
		S.hammer = m
	end
	ensureLoop()
end

local function doQuench()
	local r = refs()
	if not r then
		return
	end
	if S.blank then
		S.cool = os.clock()
	end
	Sfx.play("quench", r.steamSpot or r.weaponSpot)
	if Common.vfx() then
		local e = emitter(r.steamSpot, "Steam")
		if e then
			e:Emit(35)
		end
	end
	ensureLoop()
end

local function endHeat()
	S.heating = false
	destroyBlank()
end

local function clearResult()
	if S.result then
		S.result.root:Destroy()
		S.result = nil
	end
end

local function showResult(w)
	if type(w) ~= "table" or not w.c then
		return
	end
	local now = os.clock()
	if w.id and w.id == S.lastResultId and now - S.lastResultAt < 4 then
		return
	end
	if not w.id and now - S.lastResultAt < 1 then
		return
	end
	S.lastResultId, S.lastResultAt = w.id, now
	local r = refs()
	if not r then
		return
	end
	endHeat()
	clearResult()

	local rarity = w.r or 1
	local color = Common.rarityColor(rarity)
	local base = r.weaponSpot.WorldPosition
	local root = Instance.new("Folder")
	root.Name = "ForgeReveal"
	local anchor = Instance.new("Part")
	anchor.Name = "RevealAnchor"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = base + Vector3.new(0, 7, 0)
	anchor.Parent = root
	local aAtt = Instance.new("Attachment")
	aAtt.Parent = anchor
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10 + rarity * 5
	light.Brightness = 2 + rarity * 0.5
	light.Parent = anchor

	local inst, fix = WeaponDisplay.build(w, 5)
	inst.Parent = root
	local res = { root = root, inst = inst, fix = fix, base = anchor.Position, t0 = now, light = light }

	if Common.vfx() then
		local beam = Instance.new("Beam")
		beam.Attachment0 = r.weaponSpot
		beam.Attachment1 = aAtt
		beam.Color = ColorSequence.new(color)
		beam.LightEmission = 1
		beam.Width0 = 1.4
		beam.Width1 = 0.3
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new(0.45)
		beam.Parent = root
		res.beam = beam
		if rarity >= 5 then
			local pillarBase = Instance.new("Part")
			pillarBase.Name = "PillarBase"
			pillarBase.Size = Vector3.one
			pillarBase.Transparency = 1
			pillarBase.Anchored = true
			pillarBase.CanCollide = false
			pillarBase.CanQuery = false
			pillarBase.Position = base
			pillarBase.Parent = root
			local p0 = Instance.new("Attachment")
			p0.Parent = pillarBase
			local p1 = Instance.new("Attachment")
			p1.Position = Vector3.new(0, 400, 0)
			p1.Parent = pillarBase
			local pillar = Instance.new("Beam")
			pillar.Attachment0 = p0
			pillar.Attachment1 = p1
			pillar.Color = ColorSequence.new(color)
			pillar.LightEmission = 1
			pillar.Width0 = 7
			pillar.Width1 = 7
			pillar.FaceCamera = true
			pillar.Segments = 1
			pillar.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.9) })
			pillar.Parent = root
			res.pillar = pillar
		end
	end
	root.Parent = Common.fxFolder()
	S.result = res
	if rarity >= 5 then
		Sfx.play("reveal_legendary", r.weaponSpot)
	elseif rarity >= 3 then
		Sfx.play("reveal_rare", r.weaponSpot)
	else
		Sfx.play("reveal_common", r.weaponSpot)
	end
	ensureLoop()
end

local function active()
	return S.blank or S.hammer or S.result or S.flash > 0
end

local function step(dt)
	local now = os.clock()
	-- blank pulse / cooling
	if S.blank then
		if not S.blank.Parent then
			S.blank = nil
		else
			local light = S.blank:FindFirstChildOfClass("PointLight")
			local hot = Color3.fromRGB(255, 120, 30):Lerp(Color3.fromRGB(255, 215, 110), 0.5 + 0.5 * math.sin(now * 8))
			if S.cool then
				local k = math.clamp((now - S.cool) / 0.8, 0, 1)
				S.blank.Color = hot:Lerp(Color3.fromRGB(110, 115, 125), k)
				S.blank.Material = k > 0.7 and Enum.Material.Metal or Enum.Material.Neon
				if light then
					light.Brightness = 2 * (1 - k)
				end
			else
				S.blank.Color = hot
				if light then
					light.Brightness = 1.5 + 1.2 * math.sin(now * 8) + S.flash * 3
				end
			end
		end
	end
	if S.flash > 0 then
		S.flash = math.max(0, S.flash - dt * 6)
	end
	-- hammer swing
	if S.hammer and S.hammerT then
		S.hammerT += dt
		local ht = S.hammerT
		local raise
		if ht < 0.1 then
			raise = 1 - ht / 0.1
		elseif ht < 0.4 then
			raise = ((ht - 0.1) / 0.3) * 0.7
		else
			raise = 0.7
		end
		local r = refs()
		if r and S.hammer.Parent then
			local pivot = r.weaponSpot.WorldPosition + Vector3.new(0.6, 0.45 + 2.2 * raise, 0)
			local cf = CFrame.new(pivot) * CFrame.Angles(0, 0, -0.9 * raise)
			local handle = S.hammer:FindFirstChild("Handle")
			local head = S.hammer:FindFirstChild("Head")
			if handle then
				handle.CFrame = cf * CFrame.new(0.2, 1.6, 0)
			end
			if head then
				head.CFrame = cf
			end
		end
		if ht > 1.6 then
			S.hammer:Destroy()
			S.hammer, S.hammerT = nil, nil
		end
	end
	-- result display
	local res = S.result
	if res then
		local age = now - res.t0
		if age >= RESULT_TIME or not res.root.Parent then
			clearResult()
		else
			local bob = math.sin(age * 2.5) * 0.35
			res.inst:PivotTo(CFrame.new(res.base + Vector3.new(0, bob, 0)) * CFrame.Angles(0, age * 1.6, 0) * res.fix)
			local fade = math.clamp((RESULT_TIME - age) / 1, 0, 1)
			res.light.Brightness = (2.5 + 1.5 * math.sin(age * 5)) * fade
			if res.beam then
				res.beam.Transparency = NumberSequence.new(1 - 0.55 * fade)
			end
			if res.pillar then
				res.pillar.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1 - 0.6 * fade),
					NumberSequenceKeypoint.new(1, 1),
				})
			end
		end
	end
	if not active() and conn then
		conn:Disconnect()
		conn = nil
	end
end

ensureLoop = function()
	if not conn then
		conn = RunService.RenderStepped:Connect(step)
	end
end

local function weaponOf(p)
	if type(p) ~= "table" then
		return nil
	end
	return p.weapon or p
end

local function bindSignals()
	local okSig, Signals = pcall(function()
		local ui = Common.Client:WaitForChild("UI", 10)
		local mod = ui and ui:WaitForChild("ForgeSignals", 10)
		return mod and require(mod)
	end)
	if okSig and type(Signals) == "table" then
		if Signals.Started then
			Signals.Started.Event:Connect(function()
				startHeat()
			end)
		end
		if Signals.Hit then
			Signals.Hit.Event:Connect(function()
				doHit()
			end)
		end
		if Signals.Result then
			Signals.Result.Event:Connect(function(p)
				showResult(weaponOf(p))
			end)
		end
		if Signals.Quench then
			Signals.Quench.Event:Connect(doQuench)
		end
	end
end

function WorldForge.start()
	task.spawn(bindSignals)
	Net.on("ForgePhase", function(p)
		if type(p) ~= "table" then
			return
		end
		if p.phase == "heat" then
			startHeat()
		elseif p.phase == "quench" then
			doQuench()
		elseif p.phase == "cancelled" then
			endHeat()
		end
	end)
	Net.on("ForgeResult", function(p)
		showResult(weaponOf(p))
	end)
end

return WorldForge
