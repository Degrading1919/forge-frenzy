-- Studio-only real two-client acceptance (v2). Ordinary play and published servers do nothing.
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
		limitations = "Server gameplay calls, real timers and real character positions with two Studio clients; client UI input is checked separately."})
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
task.delay(150, function() finish(false, "Acceptance watchdog timed out") end)

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
	local Workshop = Remotes.svc("WorkshopService")
	assert(Data and Forge and Upgrade and Workshop, "Runtime services unavailable")
	waitUntil(function() return #Players:GetPlayers() >= 2 end, 30, "two Studio clients")
	local players = Players:GetPlayers()
	table.sort(players, function(x, y) return x.UserId < y.UserId end)
	local a, b = players[1], players[2] -- a = thief, b = victim
	-- The driver never seeds or kicks a real Roblox account.
	assert(a.UserId <= 0 and b.UserId <= 0, "Acceptance requires synthetic Studio players")
	local pa, pb = Data.waitFor(a, 30), Data.waitFor(b, 30)
	assert(pa and pb and pa ~= pb and pa.ingots ~= pb.ingots and pa.weapons ~= pb.weapons, "Profiles share mutable state")
	assert(Data.getStatus().storeName == "ForgeFrenzy_Player_v2_StudioPlaytest", "Test storage is not isolated")
	waitUntil(function() return Plots.indexOf(a) > 0 and Plots.indexOf(b) > 0 end, 10, "plot assignments")
	waitUntil(function()
		return a.Character and b.Character and a.Character:FindFirstChild("HumanoidRootPart") and b.Character:FindFirstChild("HumanoidRootPart")
	end, 20, "characters")
	local ia, ib = Plots.indexOf(a), Plots.indexOf(b)
	local plots = workspace.World.Plots
	local plotA, plotB = plots["Plot" .. ia], plots["Plot" .. ib]
	assert(ia ~= ib and plotA:GetAttribute("OwnerUserId") == a.UserId and plotB:GetAttribute("OwnerUserId") == b.UserId, "Plot ownership wrong")
	table.insert(evidence, "Two actual clients: distinct isolated profiles, workshops and ownership")

	backups[a], backups[b] = copy(pa), copy(pb)
	for _, profile in { pa, pb } do
		table.clear(profile)
		for k, v in Economy.newProfile() do profile[k] = v end
		profile.coins = 1e6
		profile.unlockedTier, profile.highestTierEver = 3, 3
		profile.weaponsForged = 40 -- past the new-player shield, Auto Forge unlocked
		profile.pets, profile.equipped, profile.petSerial = {}, {}, 0
		profile.entitlements, profile.receipts, profile.evolutionRank = {}, {}, 0
		Economy.reconcile(profile)
	end
	local function teleport(player, cf)
		player.Character:PivotTo(cf + Vector3.new(0, 3, 0))
		task.wait(0.3)
	end
	local function at(inst)
		return if inst:IsA("Model") then inst:GetPivot() else inst.CFrame
	end
	local function snapshot(p)
		return HttpService:JSONEncode({ coins = p.coins, weapons = p.weapons, showcase = p.showcase, pads = p.pads, levels = p.levels, forged = p.weaponsForged }) -- ingots tick with production
	end

	-- Build pads are physical and per-player.
	local baselineB = snapshot(pb)
	Plots.publish(a)
	waitUntil(function() return plotA.BuildPads:FindFirstChild("Pad_podiums_1") ~= nil end, 5, "buyable pad shown")
	local pad = plotA.BuildPads.Pad_podiums_1
	assert(not Workshop.buyPad(a, "podiums_1"), "Pad bought from far away")
	teleport(a, pad.CFrame)
	assert(Workshop.buyPad(a, "podiums_1"), "Standing on the pad did not build it")
	Plots.publish(a)
	waitUntil(function() return plotA.Showcase:FindFirstChild("Pedestal3") ~= nil end, 5, "built podiums appear")
	assert(plotB.Showcase:FindFirstChild("Pedestal3") == nil, "Another workshop changed")
	assert(Upgrade.buy(a, "ExtractorOutput") and pa.levels.ExtractorOutput == 1, "Upgrade failed")
	assert(snapshot(pb) == baselineB, "Pad/upgrade mutated another profile")
	table.insert(evidence, "Standing on a build pad builds podiums only in the buyer's workshop; upgrades isolated")

	-- Manual forging is station-local; foreign strikes are ignored.
	assert(select(2, Forge.begin(a, 1, "manual")) == "TooFar", "Manual forge allowed from far away")
	teleport(a, at(plotA.Machines.Forge1) * CFrame.new(0, 0, 5))
	local before = pa.weaponsForged
	local begun, info = Forge.begin(a, 1, "manual")
	assert(begun, "Manual forge failed: " .. tostring(info))
	assert(not Forge.strike(b, info.sessionId), "Foreign forge strike accepted")
	local session = Forge.session(a, 1)
	waitUntil(function() return os.clock() >= session.windowStart end, 15, "strike window")
	for _ = 1, 10 do
		assert(Forge.strike(a, info.sessionId), "Valid strike rejected")
		task.wait(0.12)
	end
	waitUntil(function() return pa.weaponsForged > before end, 15, "manual forge completion")
	assert(Economy.weaponCount(pa) == 1 and snapshot(pb) == baselineB, "Manual forge result wrong or leaked")
	table.insert(evidence, "Real timed manual forge at the forge station; result in the backpack; foreign strikes rejected")

	-- Auto forge with Auto Sell on the other client.
	assert(Forge.configure(b, 1, 1, 4, 7), "Configure failed")
	local coinsB = pb.coins
	assert(Forge.begin(b, 1, "free"), "Auto forge failed")
	waitUntil(function() return pb.coins > coinsB end, 20, "auto forge auto-sells")
	assert(Forge.stopAuto(b, 1), "Stop auto failed")
	table.insert(evidence, "Free Auto Forge with Sell All earns cash on the second client and stops on request")

	-- Selling only at the booth.
	local okFar = Remotes.handlers.SellAll(a, nil)
	assert(not okFar, "Sold away from the booth")
	teleport(a, CFrame.new(0, 2, 15))
	local okSell, sold = Remotes.handlers.SellAll(a, nil)
	assert(okSell and sold.coins > 0 and Economy.weaponCount(pa) == 0, "Booth sale failed")
	table.insert(evidence, "Selling refused away from the booth, paid at the central booth")

	-- Display income.
	local rng = Random.new(7)
	local function giveWeapon(p, value)
		local w = ForgeMath.rollWeapon(rng, 3, 2, 1.5, { id = Economy.nextWeaponId(p), ts = os.time() })
		w.v = value
		p.weapons[w.id] = w
		return w
	end
	local trophy = giveWeapon(pb, 5000)
	assert(Economy.setShowcase(pb, 1, trophy.id))
	pb.bank = 0
	Workshop.tickIncome(10)
	assert(pb.bank > 0, "Display weapon earned nothing")
	table.insert(evidence, string.format("Displayed weapon earned $%.1f in 10 s into the collector", pb.bank))

	-- Steal: hold at the victim's podium, carry home, ownership transfers.
	Plots.publish(b)
	local ped = plotB.Showcase.Pedestal1
	teleport(a, at(ped) * CFrame.new(0, 0, 3))
	assert(Workshop.stealBegin(a, ib, 1), "Steal begin refused")
	assert(not Workshop.stealCommit(a, ib, 1), "Steal committed without holding")
	assert(Workshop.stealBegin(a, ib, 1))
	task.wait(2.5)
	local ok, carried = Workshop.stealCommit(a, ib, 1)
	assert(ok and carried, "Steal commit failed: " .. tostring(carried))
	assert(a:GetAttribute("Carrying") ~= nil, "Carry marker not set")
	assert(pb.weapons[trophy.id] ~= nil, "Weapon left the victim before delivery")
	local soldWhileCarried = Economy.sellAll(pb, nil, Workshop.carriedFrom(b))
	assert(not soldWhileCarried and pb.weapons[trophy.id] ~= nil, "Carried weapon could be sold")
	teleport(a, plotA.PlotSpawn.CFrame)
	waitUntil(function() return Workshop.carryOf(a) == nil end, 5, "delivery")
	assert(pb.weapons[trophy.id] == nil and pb.showcase[1] == "", "Victim kept the stolen weapon")
	local stolen = nil
	for _, w in pa.weapons do
		if w.v == 5000 and w.sf then stolen = w end
	end
	assert(stolen ~= nil, "Thief did not receive the weapon")
	table.insert(evidence, "Real steal: 2.5 s hold, carried with marker, transferred only on reaching the thief's workshop")

	-- Tag back: the owner touching the thief returns the weapon.
	local second = giveWeapon(pb, 3000)
	assert(Economy.setShowcase(pb, 2, second.id))
	Workshop._reset()
	local ped2 = plotB.Showcase.Pedestal2
	teleport(a, at(ped2) * CFrame.new(0, 0, 3))
	assert(Workshop.stealBegin(a, ib, 2))
	task.wait(2.5)
	assert(Workshop.stealCommit(a, ib, 2), "Second steal failed")
	teleport(b, a.Character:GetPivot() * CFrame.new(2, -3, 0))
	waitUntil(function() return Workshop.carryOf(a) == nil end, 5, "tag return")
	assert(pb.weapons[second.id] ~= nil and pb.showcase[2] == second.id, "Tagged weapon did not return")
	table.insert(evidence, "Owner tagging the thief returns the weapon to its podium")

	-- Forge Lock: lasers keep others out and block stealing for 30 s.
	assert(not Workshop.lockForge(b), "Locked from far away")
	teleport(b, plotB.LockButton.CFrame * CFrame.new(0, 0, -3))
	assert(Workshop.lockForge(b), "Lock failed")
	waitUntil(function() return (plotB:GetAttribute("LockedUntil") or 0) > workspace:GetServerTimeNow() + 25 end, 2, "lock timer published")
	teleport(a, plotB.PlotSpawn.CFrame)
	waitUntil(function() return not Plots.inPlot(ib, a.Character.HumanoidRootPart.Position) end, 3, "intruder ejected")
	teleport(a, at(ped2) * CFrame.new(0, 0, 3))
	local okLocked, why = Workshop.stealBegin(a, ib, 2)
	assert(not okLocked and (why == "ForgeLocked" or why == "TooFar"), "Steal allowed while locked: " .. tostring(why))
	assert(not Workshop.lockForge(b), "Lock reused during its timer")
	table.insert(evidence, "Forge Lock: 30 s timer published, intruder pushed out, stealing refused, no immediate reuse")

	-- Restore synthetic profiles before departing so acceptance is non-destructive.
	Workshop._reset()
	restore(a)
	restore(b)
	a:Kick("Forge Frenzy isolated multiplayer acceptance completed")
	waitUntil(function() return a.Parent ~= Players and Plots.indexOf(a) == 0 end, 15, "departure cleanup")
	assert(plotA:GetAttribute("OwnerUserId") == 0, "Departed plot remains owned")
	assert(Plots.indexOf(b) == ib and Data.get(b) == pb, "Departure removed the other player's profile or plot")
	table.insert(evidence, "Client departure releases its workshop while the other client keeps theirs")
end)
finish(passed, if passed then nil else tostring(err))
