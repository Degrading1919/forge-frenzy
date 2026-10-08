--!strict
-- Assigns each player one of the six workshop plots, spawns them there, and publishes what other
-- clients render: plot owner sign, ShowcaseData (JSON of displayed weapons), and the player's
-- PlotIndex / EquippedPets attributes.
local Players: any = nil
local Remotes: any = nil

local Plots = {}
Plots.MAX_PLOTS = 6

local owners: { [number]: Player } = {}
local lastShowcase: { [Player]: string } = {}
local lastPets: { [Player]: string } = {}
local lastVisual: { [Player]: string } = {}

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
	return {
		selectedMaterial = math.clamp(math.floor(finite(profile.selectedMaterial, 1, 32)), 1, 32),
		levels = levels, gear = gear, entitlements = entitlements,
		evolutionRank = math.floor(finite(profile.evolutionRank, 0, 1000000)),
		rates = { orePerSec = finite(rates and rates.orePerSec, 1.5, 1e30) },
	}
end

local function plotModel(index: number): Model?
	local world = workspace:FindFirstChild("World")
	local plots = world and world:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot" .. index) :: Model?
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

local function spawnAtPlot(player: Player, character: Model)
	local index = Plots.indexOf(player)
	local plot = plotModel(index)
	local spawn = plot and plot:FindFirstChild("PlotSpawn") :: BasePart?
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
			setSign(i, player.DisplayName .. "'s Workshop")
			player:SetAttribute("PlotIndex", i)
			Remotes.session(player).plotIndex = i
			Remotes.markDirty(player)
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
			local data = plot:FindFirstChild("ShowcaseData") :: StringValue?
			if data then
				data.Value = "[]"
			end
		end
		setSign(i, "Unclaimed Workshop")
	end
	lastShowcase[player] = nil
	lastPets[player] = nil
	lastVisual[player] = nil
end

-- Publishes showcase + equipped pets for one player when they change.
local function publish(player: Player)
	local HttpService = game:GetService("HttpService")
	local Data = Remotes.svc("DataService")
	local p = Data and Data.get(player)
	if not p then
		return
	end
	local index = Plots.indexOf(player)
	local plot = plotModel(index)
	if plot then
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
			setSign(index, player.DisplayName .. "'s Workshop" .. (visual.evolutionRank > 0 and (" · Rank " .. visual.evolutionRank) or ""))
		end
		local entries = {}
		for i = 1, 6 do
			local id = p.showcase and p.showcase[i]
			local w = id and id ~= "" and p.weapons and p.weapons[id]
			entries[i] = w and { c = w.c, d = w.d, r = w.r, t = w.t, m = w.m, q = w.q, v = w.v } or ""
		end
		local json = HttpService:JSONEncode(entries)
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
			table.insert(kinds, pet.kind or pet.k)
		end
	end
	local str = table.concat(kinds, ",")
	if lastPets[player] ~= str then
		lastPets[player] = str
		player:SetAttribute("EquippedPets", str)
	end
end

function Plots.start()
	Players = game:GetService("Players")
	Remotes = require(script.Parent.Remotes)
	local function onPlayer(player: Player)
		if not assign(player) then return end
		player.CharacterAdded:Connect(function(character)
			spawnAtPlot(player, character)
		end)
		if player.Character then
			spawnAtPlot(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(release)

	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(publish, player)
			if not ok then
				warn("[Plots] publish", err)
			end
		end
	end
end

return Plots
