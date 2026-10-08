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
task.delay(240, function() finish(false, "Acceptance watchdog timed out") end)

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
	-- Moves a character like a running carrier (about 20 studs/s in 4-stud steps), so the
	-- server's carry movement check sees ordinary travel rather than a teleport.
	local function walkTo(player, cf)
		local root = player.Character.HumanoidRootPart
		local target = cf.Position + Vector3.new(0, 3, 0)
		for _ = 1, 400 do
			local offset = target - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude <= 4 then
				player.Character:PivotTo(CFrame.new(target))
				break
			end
			player.Character:PivotTo(CFrame.new(root.Position + flat.Unit * 4 + Vector3.new(0, target.Y - root.Position.Y, 0)))
			task.wait(0.2)
		end
		task.wait(0.3)
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
	local begunSteal, holdInfo = Workshop.stealBegin(a, ib, 1)
	assert(begunSteal and holdInfo.holdSec == 2.5, "A $5K weapon should take 2.5 s, got " .. tostring(holdInfo and holdInfo.holdSec))
	local showcaseJson = HttpService:JSONDecode(plotB.ShowcaseData.Value)
	assert(showcaseJson.slots[1].h == 2.5, "Prompt hold time not published for clients")
	assert(not Workshop.stealCommit(a, ib, 1), "Steal committed without holding")
	assert(Workshop.stealBegin(a, ib, 1))
	task.wait(2.5)
	local ok, carried = Workshop.stealCommit(a, ib, 1)
	assert(ok and carried, "Steal commit failed: " .. tostring(carried))
	assert(a:GetAttribute("Carrying") ~= nil, "Carry marker not set")
	assert(pb.weapons[trophy.id] ~= nil, "Weapon left the victim before delivery")
	local soldWhileCarried = Economy.sellAll(pb, nil, Workshop.carriedFrom(b))
	assert(not soldWhileCarried and pb.weapons[trophy.id] ~= nil, "Carried weapon could be sold")
	local carryStart = os.clock()
	walkTo(a, plotA.PlotSpawn.CFrame)
	waitUntil(function() return Workshop.carryOf(a) == nil end, 5, "delivery")
	local stolen = nil
	waitUntil(function()
		for _, w in pa.weapons do
			if w.v == 5000 and w.sf then stolen = w end
		end
		return stolen ~= nil
	end, 20, "durable delivery (victim save, then thief save)")
	assert(pb.weapons[trophy.id] == nil and pb.showcase[1] == "", "Victim kept the stolen weapon")
	waitUntil(function() return next(pb.outbox or {}) == nil end, 20, "outbox acknowledged after the thief's save")
	assert(stolen.st == 1, "Stolen weapon not marked")
	table.insert(evidence, string.format("Real steal: 2.5 s value-based hold, carried home on foot in %.1f s, saved victim-first then thief; outbox cleared", os.clock() - carryStart))

	-- A teleport home with a carried weapon is refused and the weapon flies back.
	local third = giveWeapon(pb, 4000)
	assert(Economy.setShowcase(pb, 1, third.id))
	Workshop._reset()
	Plots.publish(b)
	teleport(a, at(ped) * CFrame.new(0, 0, 3))
	assert(Workshop.stealBegin(a, ib, 1))
	task.wait(Workshop.Logic.holdSec(third))
	assert(Workshop.stealCommit(a, ib, 1), "Teleport-test steal failed")
	teleport(a, plotA.PlotSpawn.CFrame)
	waitUntil(function() return Workshop.carryOf(a) == nil end, 5, "teleport rejection")
	task.wait(0.5)
	assert(pb.weapons[third.id] ~= nil and pb.showcase[1] == third.id, "Teleporting home delivered the weapon")
	table.insert(evidence, "Teleporting home mid-carry: carry rejected, weapon back on its podium")

	-- The displayed weapon cannot be swapped during a hold.
	Workshop._reset()
	local decoy = giveWeapon(pb, 50)
	teleport(a, at(ped) * CFrame.new(0, 0, 3))
	assert(Workshop.stealBegin(a, ib, 1))
	assert(Economy.setShowcase(pb, 1, decoy.id))
	task.wait(Workshop.Logic.holdSec(third))
	local swapped, swapWhy = Workshop.stealCommit(a, ib, 1)
	assert(not swapped and (swapWhy == "NoIntent" or swapWhy == "Moved"), "Swapped weapon could be stolen: " .. tostring(swapWhy))
	assert(pb.weapons[decoy.id] and pb.weapons[third.id] and Workshop.carryOf(a) == nil, "Swap test moved a weapon")
	assert(Economy.setShowcase(pb, 1, ""))
	table.insert(evidence, "Swapping the displayed weapon mid-hold cancels the steal (" .. tostring(swapWhy) .. ")")

	-- Cross-tier cash-out: a stolen endgame weapon pays like the thief's best metal.
	local bigId = Economy.nextWeaponId(pa)
	local big = ForgeMath.rollWeapon(rng, 20, 2, 5, { id = bigId, ts = os.time(), mult = 7 })
	big.st, big.sf = 1, "Someone"
	pa.weapons[bigId] = big
	teleport(a, CFrame.new(0, 2, 15))
	local coinsBefore = pa.coins
	local okBig, soldBig = Remotes.handlers.SellWeapons(a, { bigId })
	local expected = Economy.usableValue(pa, big, Forge.cashMultiplier(a))
	assert(okBig and soldBig.coins == expected and soldBig.coins < big.v / 1000, "Endgame stolen weapon sold for its full value")
	assert(pa.coins - coinsBefore == soldBig.coins)
	table.insert(evidence, string.format("Stolen tier-20 weapon worth $%s sold for $%s by a tier-3 thief", ForgeMath.formatCoins(big.v), ForgeMath.formatCoins(soldBig.coins)))

	-- Tag back: the owner touching the thief returns the weapon.
	local second = giveWeapon(pb, 3000)
	assert(Economy.setShowcase(pb, 2, second.id))
	Workshop._reset()
	local ped2 = plotB.Showcase.Pedestal2
	teleport(a, at(ped2) * CFrame.new(0, 0, 3))
	assert(Workshop.stealBegin(a, ib, 2))
	task.wait(Workshop.Logic.holdSec(second))
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

	-- Station actions are refused away from the station and accepted at it.
	local H = Remotes.handlers
	teleport(a, CFrame.new(0, 2, 15)) -- the hub
	local farConfig, farWhy = H.ForgeConfigure(a, 1, 1, 4, 4)
	assert(not farConfig, "Forge configured from the hub")
	assert(not H.ForgeBegin(a, 1, "free"), "Auto Forge started from the hub")
	assert(not H.LineMaterial(a, 1, 1), "Ore line changed from the hub")
	assert(not H.UnlockMaterial(a, 4, 1), "Material bought from the hub")
	assert(not H.BuyUpgrade(a, "SmelterSpeed"), "Ore upgrade bought from the hub")
	assert(not H.BuyUpgrade(a, "Hammer"), "Tool upgrade bought from the hub")
	teleport(a, at(plotA.Machines.Forge1) * CFrame.new(0, 0, 5))
	assert(H.ForgeConfigure(a, 1, 1, 4, 4), "Configure refused at the forge")
	assert(H.ForgeBegin(a, 1, "free"), "Auto Forge refused at the forge")
	assert(not H.Hatch(a, "hearth", 1), "Egg hatched from a workshop")
	assert(not H.Evolve(a, false), "Evolved away from the altar")
	teleport(a, CFrame.new(0, 2, 15))
	task.wait(0.5)
	assert(Forge.status(a)[1] and Forge.status(a)[1].auto, "Running Auto Forge stopped when the player walked away")
	assert(H.ForgeStop(a, 1), "Stop refused")
	table.insert(evidence, "Forge, ore, upgrade, hatch and evolve actions refused away from their stations (" .. tostring(farWhy) .. "); Auto Forge keeps running after walking away")

	-- Forge Lock state belongs to the owner: a departing owner's lock does not pass on.
	Workshop._reset()
	teleport(a, plotA.LockButton.CFrame * CFrame.new(0, 0, -3))
	assert(Workshop.lockForge(a), "Thief's own lock failed")
	waitUntil(function() return (plotA:GetAttribute("LockedUntil") or 0) > workspace:GetServerTimeNow() end, 2, "own lock published")

	-- Restore synthetic profiles before departing so acceptance is non-destructive.
	restore(a)
	restore(b)
	a:Kick("Forge Frenzy isolated multiplayer acceptance completed")
	waitUntil(function() return a.Parent ~= Players and Plots.indexOf(a) == 0 end, 15, "departure cleanup")
	assert(plotA:GetAttribute("OwnerUserId") == 0, "Departed plot remains owned")
	local inherited = Workshop.lockState(ia)
	assert(inherited.lockedUntil == 0 and inherited.nextLockAt == 0, "Lock survived the workshop changing hands")
	waitUntil(function() return (plotA:GetAttribute("LockedUntil") or 0) == 0 end, 2, "lock attribute cleared")
	table.insert(evidence, "Owner left mid-lock: the workshop's lock and cooldown are cleared for the next owner")
	assert(Plots.indexOf(b) == ib and Data.get(b) == pb, "Departure removed the other player's profile or plot")
	table.insert(evidence, "Client departure releases its workshop while the other client keeps theirs")
end)
finish(passed, if passed then nil else tostring(err))
