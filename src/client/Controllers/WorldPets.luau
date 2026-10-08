--!nonstrict
-- Client-side companions following every player (data: Player attribute EquippedPets, comma-separated kind ids).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Common = require(script.Parent.WorldUtil.Common)

local WorldPets = { Priority = 0 }

local MAX_PETS = 3
local CULL = 200
local OFFSETS = { Vector3.new(-3.2, -0.6, 4), Vector3.new(3.2, -0.6, 4), Vector3.new(0, 0.4, 7) }

local tracked = {} -- [player] = { kinds, pets = { {inst, pos, dir} }, shown }
local t = 0

local function companionDef(kind)
	local C = Common.config("Companions")
	if not C then
		return nil
	end
	return (C.ById and C.ById[kind]) or C[kind]
end

local function buildPet(kind)
	local def = companionDef(kind)
	local inst = nil
	local PM = Common.shared({ "Visuals", "PetModels" })
	if PM and PM.build and def then
		local ok, r = pcall(PM.build, def.modelKind, def.color, def.rarity)
		if ok and typeof(r) == "Instance" then
			inst = r
		end
	end
	if not inst then
		local p = Instance.new("Part")
		p.Name = "PetFallback"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(1.4, 1.4, 1.4)
		p.Material = Enum.Material.Neon
		p.Color = def and def.color or Color3.fromRGB(255, 200, 120)
		local l = Instance.new("PointLight")
		l.Color = p.Color
		l.Range = 8
		l.Parent = p
		inst = p
	end
	Common.inert(inst)
	return inst
end

local function destroyPets(tr)
	for _, p in tr.pets do
		p.inst:Destroy()
	end
	tr.pets = {}
	tr.shown = false
end

local function setKinds(player, str)
	local tr = tracked[player]
	if not tr then
		return
	end
	str = str or ""
	if tr.kinds == str then
		return
	end
	tr.kinds = str
	destroyPets(tr)
	local n = 0
	for kind in string.gmatch(str, "[^,%s]+") do
		n += 1
		if n > MAX_PETS then
			break
		end
		table.insert(tr.pets, { inst = buildPet(kind), pos = nil, dir = Vector3.new(0, 0, -1) })
	end
end

local function track(player)
	if tracked[player] then
		return
	end
	tracked[player] = { kinds = nil, pets = {}, shown = false }
	player:GetAttributeChangedSignal("EquippedPets"):Connect(function()
		setKinds(player, player:GetAttribute("EquippedPets"))
	end)
	setKinds(player, player:GetAttribute("EquippedPets"))
end

local function untrack(player)
	local tr = tracked[player]
	if tr then
		destroyPets(tr)
		tracked[player] = nil
	end
end

local function hide(tr)
	if tr.shown then
		for _, p in tr.pets do
			p.inst.Parent = nil
			p.pos = nil
		end
		tr.shown = false
	end
end

local function step(dt)
	t += dt
	local camPos = Common.camPos()
	if not camPos then
		return
	end
	local alpha = 1 - math.exp(-dt * 6)
	for player, tr in tracked do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if #tr.pets == 0 then
			continue
		end
		if not hrp or (hrp.Position - camPos).Magnitude > CULL then
			hide(tr)
			continue
		end
		if not tr.shown then
			local f = Common.fxFolder()
			for _, p in tr.pets do
				p.inst.Parent = f
			end
			tr.shown = true
		end
		local rootCF = hrp.CFrame
		for i, p in tr.pets do
			local target = (rootCF * CFrame.new(OFFSETS[i])).Position + Vector3.new(0, math.sin(t * 3 + i * 1.7) * 0.4, 0)
			if not p.pos then
				p.pos = target
			end
			local prev = p.pos
			p.pos = prev:Lerp(target, alpha)
			local move = Vector3.new(p.pos.X - prev.X, 0, p.pos.Z - prev.Z)
			local want
			if move.Magnitude > 0.02 then
				want = move.Unit
			else
				want = Vector3.new(rootCF.LookVector.X, 0, rootCF.LookVector.Z)
				if want.Magnitude < 0.01 then
					want = p.dir
				else
					want = want.Unit
				end
			end
			p.dir = p.dir:Lerp(want, math.min(1, dt * 8))
			if p.dir.Magnitude < 0.01 then
				p.dir = want
			end
			p.inst:PivotTo(CFrame.lookAt(p.pos, p.pos + p.dir))
		end
	end
end

function WorldPets.start()
	for _, pl in Players:GetPlayers() do
		track(pl)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	RunService.RenderStepped:Connect(step)
end

return WorldPets
