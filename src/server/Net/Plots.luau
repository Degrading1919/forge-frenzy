--!strict
--[[
	World glue for the six workshops (v2, docs/22).

	* Assigns each player a workshop, spawns them there and raises their walk speed.
	* Shows exactly what the owner has built: models/podiums/decor with a `PadId` attribute
	  appear only when that pad is bought; build pads appear only when they can be bought.
	  Hidden objects are parked in ServerStorage.PlotStash so they neither render nor collide.
	* Publishes what other clients render: owner sign, VisualState JSON (line materials,
	  station recipes, upgrade levels), ShowcaseData JSON, lock timers and EquippedPets.
	* Supplies the geometry hooks WorkshopService and ForgeService use for proximity checks.
]]
local Players: any = nil
local Remotes: any = nil
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local Plots = {}
Plots.MAX_PLOTS = 6
Plots.WALK_SPEED = 28
Plots.STATION_RANGE = 16
Plots.BOOTH_RANGE = 24

local owners: { [number]: Player } = {}
local lastShowcase: { [Player]: string } = {}
local lastPets: { [Player]: string } = {}
local lastVisual: { [Player]: string } = {}
local lastPads: { [number]: string } = {}

local MACHINE_TRACKS = { "ExtractorOutput", "SmelterSpeed", "StorageCapacity", "FurnaceHeat", "AnvilFinish" }
local GEAR_TRACKS = { "Hammer", "Gloves", "Apron" }
local VISUAL_PASSES = { "TitanExcavator", "DragonFurnace", "VIPWorkshop" }

local function finite(value: any, fallback: number, max: number): number
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return fallback end
	return math.clamp(value, 0, max)
end

-- Deliberate projection: never replicate the authoritative profile or all entitlements.
-- Verified flags come from MonetizationService (including isolated Studio overlays).
function Plots.publicVisual(profile: any, verified: any, rates: any): any
	local levels, gear, entitlements = {}, {}, {}
	for _, key in MACHINE_TRACKS do levels[key] = math.floor(finite(profile.levels and profile.levels[key], 0, 1000)) end
	for _, key in GEAR_TRACKS do gear[key] = math.floor(finite(profile.gear and profile.gear[key], 0, 1000)) end
	for _, key in VISUAL_PASSES do entitlements[key] = verified and verified[key] == true or false end
	local lines, stations = {}, {}
	for i, line in (if type(profile.lines) == "table" then profile.lines else {}) do
		if i > 3 then break end
		lines[i] = math.clamp(math.floor(finite(line.m, 1, 32)), 1, 32)
	end
	for i, station in (if type(profile.stations) == "table" then profile.stations else {}) do
		if i > 3 then break end
		stations[i] = { m = math.clamp(math.floor(finite(station.m, 1, 32)), 1, 32), c = math.clamp(math.floor(finite(station.c, 1, 5)), 1, 5) }
	end
	return {
		selectedMaterial = math.clamp(math.floor(finite(profile.selectedMaterial, 1, 32)), 1, 32),
		lines = lines,
		stations = stations,
		levels = levels, gear = gear, entitlements = entitlements,
		evolutionRank = math.floor(finite(profile.evolutionRank, 0, 1000000)),
		rates = { orePerSec = finite(rates and rates.orePerSec, 1 / 3, 1e30) },
	}
end

local function plotModel(index: number): Model?
	local world = workspace:FindFirstChild("World")
	local plots = world and world:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot" .. index) :: Model?
end
Plots.model = plotModel

local function stashFor(index: number): Folder
	local stash = ServerStorage:FindFirstChild("PlotStash")
	if not stash then
		stash = Instance.new("Folder")
		stash.Name = "PlotStash"
		stash.Parent = ServerStorage
	end
	local folder = stash:FindFirstChild("Plot" .. index)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Plot" .. index
		folder.Parent = stash
	end
	return folder :: Folder
end

local function setSign(index: number, text: string)
	local plot = plotModel(index)
	local label = plot and plot:FindFirstChild("SignBoard") and plot.SignBoard:FindFirstChild("OwnerGui") and plot.SignBoard.OwnerGui:FindFirstChild("OwnerText")
	if label then
		(label :: TextLabel).Text = text
	end
end

function Plots.indexOf(player: Player): number
	for i, p in owners do
		if p == player then
			return i
		end
	end
	return 0
end

function Plots.ownerOf(index: number): Player?
	return owners[index]
end

-- Every PadId-tagged object of a plot, wherever it currently is (plot or stash).
local function padObjects(index: number): { Instance }
	local out = {}
	local plot = plotModel(index)
	for _, root in { plot, stashFor(index) } do
		if root then
			for _, inst in root:GetDescendants() do
				if inst:GetAttribute("PadId") and (inst:IsA("Model") or inst:IsA("BasePart")) and not (inst.Parent and inst.Parent:GetAttribute("PadId")) then
					table.insert(out, inst)
				end
			end
		end
	end
	return out
end

-- Remembers where a stashable object lives so it can be put back.
local homes: { [Instance]: Instance } = {}

local function setShown(inst: Instance, index: number, shown: boolean)
	if not homes[inst] then
		homes[inst] = inst.Parent :: Instance
	end
	local target = if shown then homes[inst] else stashFor(index)
	if inst.Parent ~= target then
		inst.Parent = target
	end
end

--[[
	Shows built objects and buyable pads for the plot's owner (or the default starter workshop
	when unowned). Build pads (BasePart "Pad_*") show when buyable; built objects (Models) show
	when their pad is owned.
]]
function Plots.applyPads(index: number, profile: any?)
	local BuildPads = require(game:GetService("ReplicatedStorage").Shared.Config.BuildPads) :: any
	local pads = if profile and type(profile.pads) == "table" then profile.pads else {}
	local highest = if profile then math.max(profile.unlockedTier or 1, profile.highestTierEver or 1) else 1
	local key = HttpService:JSONEncode(pads) .. ":" .. highest .. ":" .. tostring(profile ~= nil)
	if lastPads[index] == key then
		return
	end
	lastPads[index] = key
	for _, inst in padObjects(index) do
		local padId = inst:GetAttribute("PadId")
		local pad = BuildPads.ById[padId]
		local isPad = inst:IsA("BasePart") and inst.Name:sub(1, 4) == "Pad_"
		if isPad then
			setShown(inst, index, profile ~= nil and pad ~= nil and BuildPads.available(pad, pads, highest))
		else
			setShown(inst, index, pads[padId] == true)
		end
	end
end

local function spawnAtPlot(player: Player, character: Model)
	local index = Plots.indexOf(player)
	local plot = plotModel(index)
	local spawn = plot and plot:FindFirstChild("PlotSpawn") :: BasePart?
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		player:SetAttribute("BaseWalkSpeed", Plots.WALK_SPEED)
		humanoid.WalkSpeed = Plots.WALK_SPEED
		humanoid.JumpPower = 55
	end
	if spawn then
		task.defer(function()
			if character.Parent then
				character:PivotTo(spawn.CFrame * CFrame.new(0, 4, 0))
			end
		end)
	end
end

local function assign(player: Player)
	if Plots.indexOf(player) > 0 then return true end
	for i = 1, Plots.MAX_PLOTS do
		if not owners[i] and plotModel(i) then
			owners[i] = player
			local plot = plotModel(i) :: Model
			plot:SetAttribute("OwnerUserId", player.UserId)
			plot:SetAttribute("VisualState", "")
			setSign(i, player.DisplayName .. "'s Forge")
			player:SetAttribute("PlotIndex", i)
			Remotes.session(player).plotIndex = i
			Remotes.markDirty(player)
			lastPads[i] = nil
			return true
		end
	end
	player:SetAttribute("PlotIndex", 0)
	player:Kick("This server is full: all workshops are occupied. Please join another Forge Frenzy server.")
	return false
end

local function release(player: Player)
	local i = Plots.indexOf(player)
	if i > 0 then
		owners[i] = nil
		local plot = plotModel(i)
		if plot then
			plot:SetAttribute("OwnerUserId", 0)
			plot:SetAttribute("VisualState", "")
			plot:SetAttribute("LockedUntil", 0)
			local data = plot:FindFirstChild("ShowcaseData") :: StringValue?
			if data then
				data.Value = "[]"
			end
		end
		setSign(i, "Free Workshop")
		lastPads[i] = nil
		Plots.applyPads(i, nil)
	end
	lastShowcase[player] = nil
	lastPets[player] = nil
	lastVisual[player] = nil
end

-- Publishes showcase + equipped pets + build state for one player when they change.
local function publish(player: Player)
	local Data = Remotes.svc("DataService")
	local p = Data and Data.get(player)
	if not p then
		return
	end
	local index = Plots.indexOf(player)
	local plot = plotModel(index)
	if plot then
		Plots.applyPads(index, p)
		local Monet = Remotes.svc("MonetizationService")
		local Production = Remotes.svc("ProductionService")
		local verified = Monet and Monet.ownedKeys and Monet.ownedKeys(player) or {}
		local rates = Production and Production.rates and Production.rates(player) or {}
		local visual = Plots.publicVisual(p, verified, rates)
		visual.ownerUserId = player.UserId
		local visualJson = HttpService:JSONEncode(visual)
		if lastVisual[player] ~= visualJson then
			lastVisual[player] = visualJson
			plot:SetAttribute("VisualState", visualJson)
			setSign(index, player.DisplayName .. "'s Forge" .. (if visual.evolutionRank > 0 then (" ★" .. visual.evolutionRank) else ""))
		end
		local Workshop = Remotes.svc("WorkshopService")
		local carried = if Workshop then Workshop.carriedFrom(player) else {}
		local Economy = require(game:GetService("ReplicatedStorage").Shared.Economy) :: any
		local Evolution = Remotes.svc("ForgeService")
		local mult = if Evolution and Evolution.cashMultiplier then Evolution.cashMultiplier(player) else 1
		local entries = {}
		for i = 1, 8 do
			local id = p.showcase and p.showcase[i]
			local w = id and id ~= "" and p.weapons and p.weapons[id]
			entries[i] = if w then { c = w.c, d = w.d, r = w.r, t = w.t, m = w.m, q = w.q, v = w.v, inc = Economy.displayIncome(p, w, mult), gone = carried[id] == true } else ""
		end
		local json = HttpService:JSONEncode({ slots = entries, unlocked = Economy.showcaseSlots(p), shield = (p.weaponsForged or 0) < (Workshop and Workshop.Logic.SHIELD_FORGES or 0) })
		if lastShowcase[player] ~= json then
			lastShowcase[player] = json
			local data = plot:FindFirstChild("ShowcaseData") :: StringValue?
			if not data then
				local sv = Instance.new("StringValue")
				sv.Name = "ShowcaseData"
				sv.Parent = plot
				data = sv
			end
			(data :: StringValue).Value = json
		end
	end
	local kinds = {}
	for _, id in p.equipped or {} do
		local pet = p.pets and p.pets[id]
		if pet then
			table.insert(kinds, (pet.kind or pet.k) .. ":" .. tostring(pet.lv or 1))
		end
	end
	local str = table.concat(kinds, ",")
	if lastPets[player] ~= str then
		lastPets[player] = str
		player:SetAttribute("EquippedPets", str)
	end
end
Plots.publish = publish

local function find(index: number, path: { string }): Instance?
	local node: Instance? = plotModel(index)
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function positionOf(inst: Instance?): Vector3?
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

-- Geometry hooks -----------------------------------------------------------------------------

local function inPlot(index: number, position: Vector3): boolean
	local bounds = find(index, { "Bounds" }) :: BasePart?
	if not bounds then
		return false
	end
	local rel = bounds.CFrame:PointToObjectSpace(position)
	local half = bounds.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z and rel.Y <= half.Y and rel.Y >= -half.Y - 2
end
Plots.inPlot = inPlot

local function forgeModel(index: number, station: number): Model?
	return find(index, { "Machines", "Forge" .. station }) :: Model?
end

function Plots.nearStation(player: Player, station: number): boolean
	local index = Plots.indexOf(player)
	local forge = forgeModel(index, station)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not forge or not root then
		return false
	end
	return (root.Position - forge:GetPivot().Position).Magnitude <= Plots.STATION_RANGE
end

function Plots.nearBooth(player: Player): boolean
	local world = workspace:FindFirstChild("World")
	local booth = world and world:FindFirstChild("Hub") and world.Hub:FindFirstChild("SellBooth")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not booth or not root then
		return false
	end
	local center = (booth :: Model):GetPivot().Position
	local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
	return flat.Magnitude <= Plots.BOOTH_RANGE
end

function Plots.wireWorkshop()
	local Workshop = Remotes.svc("WorkshopService")
	if Workshop then
		Workshop.world = {
			plotOf = Plots.indexOf,
			ownerOf = Plots.ownerOf,
			inPlot = inPlot,
			podiumPosition = function(index: number, slot: number): Vector3?
				return positionOf(find(index, { "Showcase", "Pedestal" .. slot }))
			end,
			padPosition = function(index: number, padId: string): Vector3?
				return positionOf(find(index, { "BuildPads", "Pad_" .. padId }))
			end,
			collectorPosition = function(index: number): Vector3?
				return positionOf(find(index, { "Collector" }))
			end,
			lockButtonPosition = function(index: number): Vector3?
				return positionOf(find(index, { "LockButton" }))
			end,
			eject = function(index: number, character: Model)
				local point = find(index, { "EjectPoint" }) :: BasePart?
				if point and character then
					character:PivotTo(point.CFrame * CFrame.new(0, 3, 0))
				end
			end,
		}
		Workshop.changed.Event:Connect(function(kind: string, payload: any)
			if kind == "lock" then
				local plot = plotModel(payload.plot)
				if plot then
					plot:SetAttribute("LockedUntil", payload.lockedUntil)
					plot:SetAttribute("NextLockAt", payload.nextLockAt)
				end
			elseif kind == "carry" then
				for _, player in { payload.thief, payload.victim } do
					if typeof(player) == "Instance" then
						lastShowcase[player] = nil
						pcall(publish, player)
						Remotes.markDirty(player)
					end
				end
				Remotes.pushAll("Steal", {
					thief = if typeof(payload.thief) == "Instance" then payload.thief.UserId else 0,
					victim = if typeof(payload.victim) == "Instance" then payload.victim.UserId else 0,
					slot = payload.slot,
					outcome = payload.outcome,
					deadline = payload.deadline,
				})
			elseif kind == "pads" then
				local index = Plots.indexOf(payload.player)
				lastPads[index] = nil
				pcall(publish, payload.player)
			end
		end)
		Workshop.notify.Event:Connect(function(player: any, text: string, kind: string)
			if typeof(player) == "Instance" then
				Remotes.toast(player, text, kind)
			end
		end)
	end
	local Forge = Remotes.svc("ForgeService")
	if Forge then
		Forge.nearStation = Plots.nearStation
	end
end

function Plots.start()
	Players = game:GetService("Players")
	Remotes = require(script.Parent.Remotes)
	Plots.wireWorkshop()
	for i = 1, Plots.MAX_PLOTS do
		Plots.applyPads(i, nil)
	end
	local function onPlayer(player: Player)
		if not assign(player) then return end
		player.CharacterAdded:Connect(function(character)
			spawnAtPlot(player, character)
		end)
		if player.Character then
			task.spawn(spawnAtPlot, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(release)

	while true do
		task.wait(0.5)
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(publish, player)
			if not ok then
				warn("[Plots] publish", err)
			end
		end
	end
end

return Plots
