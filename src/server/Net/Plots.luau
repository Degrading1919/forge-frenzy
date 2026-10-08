--!strict
-- Assigns each player one of the six workshop plots, spawns them there, and publishes what other
-- clients render: plot owner sign, ShowcaseData (JSON of displayed weapons), and the player's
-- PlotIndex / EquippedPets attributes.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Remotes = require(script.Parent.Remotes)

local Plots = {}

local owners: { [number]: Player } = {}
local lastShowcase: { [Player]: string } = {}
local lastPets: { [Player]: string } = {}

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
	for i = 1, 6 do
		if not owners[i] and plotModel(i) then
			owners[i] = player
			local plot = plotModel(i) :: Model
			plot:SetAttribute("OwnerUserId", player.UserId)
			setSign(i, player.DisplayName .. "'s Workshop")
			player:SetAttribute("PlotIndex", i)
			Remotes.session(player).plotIndex = i
			Remotes.markDirty(player)
			return
		end
	end
	-- More players than plots (server MaxPlayers should be 6); they can still use the hub.
	player:SetAttribute("PlotIndex", 0)
end

local function release(player: Player)
	local i = Plots.indexOf(player)
	if i > 0 then
		owners[i] = nil
		local plot = plotModel(i)
		if plot then
			plot:SetAttribute("OwnerUserId", 0)
			local data = plot:FindFirstChild("ShowcaseData") :: StringValue?
			if data then
				data.Value = "[]"
			end
		end
		setSign(i, "Unclaimed Workshop")
	end
	lastShowcase[player] = nil
	lastPets[player] = nil
end

-- Publishes showcase + equipped pets for one player when they change.
local function publish(player: Player)
	local Data = Remotes.svc("DataService")
	local p = Data and Data.get(player)
	if not p then
		return
	end
	local index = Plots.indexOf(player)
	local plot = plotModel(index)
	if plot then
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
	local function onPlayer(player: Player)
		assign(player)
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
