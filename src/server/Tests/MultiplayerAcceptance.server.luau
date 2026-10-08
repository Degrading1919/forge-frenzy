-- Studio-only real two-client acceptance. Ordinary play and published servers do nothing.
-- From plugin/MCP edit context:
-- StudioTestService:ExecuteMultiplayerTestAsync(2, {forgeFrenzyAcceptance = true})
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end
local TestService = game:GetService("StudioTestService")
local okArgs, args = pcall(TestService.GetTestArgs, TestService)
if not okArgs or type(args) ~= "table" or args.forgeFrenzyAcceptance ~= true then return end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local started, ended = os.clock(), false
local evidence, backups = {}, {}
local Data: any = nil
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = copy(v) end
	return out
end
local function restore(player)
	local original = backups[player]
	local current = Data and Data.get(player)
	if current and original then
		table.clear(current)
		for k, v in original do current[k] = copy(v) end
		current.lastSeen = os.time()
		Data.markDirty(player)
		assert(Data.saveNow(player, 15), "Could not confirm restored synthetic player's profile")
		backups[player] = nil
	end
end
local function finish(passed, message)
	if ended then return end
	ended = true
	local restoreErrors = {}
	for player in backups do
		local restored, err = pcall(restore, player)
		if not restored then table.insert(restoreErrors, tostring(err)); passed = false end
	end
	TestService:EndTest({passed = passed, error = message, restoreErrors = restoreErrors,
		checks = evidence, elapsedSec = os.clock() - started,
		mode = Data and Data.getStatus().mode or "NotLoaded",
		limitations = "Server gameplay calls and actual timers with two real Studio clients; visual/input acceptance is separate."})
end
local function waitUntil(predicate, seconds, label)
	local deadline = os.clock() + seconds
	repeat
		if predicate() then return end
		assert(os.clock() < deadline, "Timed out: " .. label)
		task.wait(0.05)
	until false
end
-- A failed startup must still terminate the remote test instead of hanging Studio.
task.delay(90, function() finish(false, "Acceptance watchdog timed out") end)

local passed, err = pcall(function()
	local root = script.Parent.Parent
	local Remotes = require(root:WaitForChild("Net"):WaitForChild("Remotes"))
	local Plots = require(root.Net.Plots)
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local Economy = require(Shared.Economy)
	local ForgeMath = require(Shared.ForgeMath)
	Data = Remotes.svc("DataService")
	local Forge = Remotes.svc("ForgeService")
	local Upgrade = Remotes.svc("UpgradeService")
	local Pet = Remotes.svc("CompanionService")
	assert(Data and Forge and Upgrade and Pet, "Runtime services unavailable")
	waitUntil(function() return #Players:GetPlayers() >= 2 end, 30, "two Studio clients")
	local players = Players:GetPlayers()
	table.sort(players, function(a, b) return a.UserId < b.UserId end)
	local a, b = players[1], players[2]
	-- The driver never seeds or kicks a real Roblox account.
	assert(a.UserId <= 0 and b.UserId <= 0, "Acceptance requires synthetic Studio players")
	local pa, pb = Data.waitFor(a, 30), Data.waitFor(b, 30)
	assert(pa and pb and pa ~= pb and pa.ingots ~= pb.ingots and pa.weapons ~= pb.weapons, "Profiles share mutable state")
	local status = Data.getStatus()
	assert(status.storeName == "ForgeFrenzy_Player_v1_StudioPlaytest", "Test storage is not isolated")
	waitUntil(function() return Plots.indexOf(a) > 0 and Plots.indexOf(b) > 0 end, 10, "plot assignments")
	local ia, ib = Plots.indexOf(a), Plots.indexOf(b)
	assert(ia ~= ib and a:GetAttribute("PlotIndex") == ia and b:GetAttribute("PlotIndex") == ib, "Players share plots")
	local plots = workspace.World.Plots
	assert(plots["Plot" .. ia]:GetAttribute("OwnerUserId") == a.UserId and plots["Plot" .. ib]:GetAttribute("OwnerUserId") == b.UserId, "Plot ownership wrong")
	table.insert(evidence, "Two actual clients: distinct isolated profiles, plots, and ownership attributes")

	backups[a], backups[b] = copy(pa), copy(pb)
	for _, profile in {pa, pb} do
		table.clear(profile)
		for k, v in Economy.newProfile() do profile[k] = v end
		profile.coins = 100000
		profile.unlockedTier, profile.highestTierEver = 3, 3
		profile.pets, profile.equipped, profile.petSerial = {}, {}, 0
		profile.entitlements, profile.receipts, profile.evolutionRank = {}, {}, 0
	end
	local ratesB = Economy.rates(pb)
	pb.ingots[1], pb.ore[1] = ratesB.capacity, ratesB.oreCapacity
	local foreignWeapon = ForgeMath.rollWeapon(Random.new(37), 1, 1, 1.5, {id = "foreign-b-weapon", ts = os.time()})
	pb.weapons[foreignWeapon.id], pb.pending = foreignWeapon, copy(foreignWeapon)
	pb.pets["foreign-b-pet"] = {id = "foreign-b-pet", k = "soot_mole", ts = os.time()}
	local function otherSnapshot()
		return HttpService:JSONEncode({coins = pb.coins, ingots = pb.ingots, pending = pb.pending,
			weaponsForged = pb.weaponsForged, levels = pb.levels, pets = pb.pets, equipped = pb.equipped})
	end
	local baseline = otherSnapshot()
	assert(Upgrade.buy(a, "ExtractorOutput"), "Actual upgrade failed")
	assert(pa.levels.ExtractorOutput == 1 and otherSnapshot() == baseline, "Upgrade mutated another player's profile")
	local hatchOk, hatch = Pet.hatch(a, "hearth", 1)
	assert(hatchOk and #hatch == 1 and Pet.equip(a, hatch[1].id), "Actual hatch/equip failed")
	assert(otherSnapshot() == baseline, "Companions mutated another player's profile")
	table.insert(evidence, "Actual upgrade and single free egg hatch/equip affect only the acting player")
	assert(not Forge.sellKept(a, foreignWeapon.id), "Foreign weapon sold")
	assert(not Forge.setShowcase(a, 1, foreignWeapon.id), "Foreign weapon showcased")
	assert(not Pet.equip(a, "foreign-b-pet") and not Pet.release(a, "foreign-b-pet"), "Foreign companion mutated")
	assert(otherSnapshot() == baseline, "Foreign-id requests changed another profile")
	table.insert(evidence, "Foreign weapon sale/showcase and companion equip/release rejected")

	local beforeForge = pa.weaponsForged
	local begun, info = Forge.start(a, 1, 1, "manual")
	assert(begun, "Actual manual forge failed: " .. tostring(info))
	assert(not Forge.strike(b, info.sessionId), "Foreign forge strike accepted")
	local session = Forge.session(a)
	waitUntil(function() return os.clock() >= session.windowStart end, 15, "actual strike window")
	for _ = 1, 8 do
		assert(Forge.strike(a, info.sessionId), "Valid timed server strike rejected")
		task.wait(0.15)
	end
	waitUntil(function() return pa.weaponsForged > beforeForge end, 15, "scheduled forge completion")
	assert(pa.pending and pa.pending.m == 1 and pa.pending.c == 1, "Wrong material/class in actual result")
	assert(otherSnapshot() == baseline, "Forge changed another player's coins, ingots, pending, collection, or upgrades")
	assert(Forge.resolve(a, "keep") and pa.pending == nil, "Keep result failed")
	table.insert(evidence, "Real timed manual forge and keep settle independently; foreign strikes rejected")

	-- Restore synthetic profiles before departing so acceptance is non-destructive.
	restore(a)
	restore(b)
	a:Kick("Forge Frenzy isolated multiplayer acceptance completed")
	waitUntil(function() return a.Parent ~= Players and Plots.indexOf(a) == 0 end, 15, "departure cleanup")
	local departedPlot = plots["Plot" .. ia]
	assert(departedPlot:GetAttribute("OwnerUserId") == 0, "Departed plot remains owned")
	local showcase = departedPlot:FindFirstChild("ShowcaseData")
	assert(not showcase or showcase.Value == "[]", "Departed showcase remains visible")
	assert(Plots.indexOf(b) == ib and Data.get(b) == pb, "Departure removed the other player's profile or plot")
	table.insert(evidence, "Actual client departure releases plot/showcase while the other client retains its profile/plot")
end)
finish(passed, if passed then nil else tostring(err))
