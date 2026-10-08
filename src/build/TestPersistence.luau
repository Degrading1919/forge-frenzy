-- Isolated ProfileStore acceptance, run inside Studio without touching production keys.
-- return require(game.ServerStorage.Build.TestPersistence)() -- APIs if enabled, else Mock
-- true forces Mock. Mock verifies same-session rejoin only, never cross-play durability.
return function(forceMock: boolean?)
	assert(game:GetService("RunService"):IsStudio(), "Acceptance helper is Studio-only")
	local root = game:GetService("ServerScriptService"):WaitForChild("Server")
	local library = require(root:WaitForChild("Packages"):WaitForChild("ProfileStore"))
	local Economy = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Economy"))
	local ForgeMath = require(game:GetService("ReplicatedStorage").Shared.ForgeMath)
	local HttpService = game:GetService("HttpService")
	local started = os.clock()
	while library.DataStoreState == "NotReady" and os.clock() - started < 20 do task.wait(0.05) end
	assert(library.DataStoreState ~= "NotReady", "API detection timed out")
	local mock = forceMock == true or library.DataStoreState ~= "Access"
	local name = "ForgeFrenzy_IsolatedAcceptance_v1"
	local store = library.New(name, Economy.newProfile())
	if mock then store = store.Mock end
	local key = "Acceptance_" .. HttpService:GenerateGUID(false)
	local function waitUntil(predicate, label)
		local deadline = os.clock() + 20
		repeat
			if predicate() then return end
			assert(os.clock() < deadline, "Timed out: " .. label)
			task.wait(0.05)
		until false
	end
	local first = store:StartSessionAsync(key, {Cancel = function() return os.clock() - started > 30 end})
	assert(first, "Could not open isolated profile")
	local data = first.Data
	data.coins, data.lifetimeCoins, data.weaponsForged = 12345, 45678, 12
	data.selectedMaterial, data.unlockedTier = 2, 2
	data.ingots[2] = 17
	data.weapons = {["acceptance-weapon"] = ForgeMath.rollWeapon(Random.new(177), 1, 1, 1.5, {id = "acceptance-weapon", ts = os.time()})}
	data.pets = {["acceptance-pet"] = {id = "acceptance-pet", k = "ember_sprite", ts = os.time()}}
	data.equipped = {"acceptance-pet"}
	data.entitlements = {VIPWorkshop = true}
	data.evolutionRank = 3
	data.receipts = {acceptance_receipt = os.time()}
	data.acceptanceMarker = key
	local profileService = require(root.Services.DataService:Clone())
	local fakePlayer = {UserId = -91001}
	profileService._setForTest(fakePlayer, data, first)
	assert(profileService.saveNow(fakePlayer, 20, function(saved) return saved.acceptanceMarker == key end), "Manual save unconfirmed")
	data.acceptanceFinal = true
	profileService._releaseForTest(fakePlayer)
	waitUntil(function() return first.LastSavedData.acceptanceFinal == true end, "final release save")
	assert(not first:IsActive(), "First session still active")
	local second = store:StartSessionAsync(key, {Cancel = function() return os.clock() - started > 60 end})
	assert(second and second:IsActive(), "Rejoin did not obtain session")
	local saved = second.Data
	local ok, err = pcall(function()
		assert(saved.coins == 12345 and saved.lifetimeCoins == 45678 and saved.weaponsForged == 12, "Economy lost")
		assert(saved.selectedMaterial == 2 and saved.unlockedTier == 2 and saved.ingots[2] == 17, "Material state lost")
		assert(saved.weapons["acceptance-weapon"].id == "acceptance-weapon" and saved.pets["acceptance-pet"].id == "acceptance-pet", "Collection lost")
		assert(saved.equipped[1] == "acceptance-pet" and saved.entitlements.VIPWorkshop and saved.evolutionRank == 3, "Permanent progress lost")
		assert(saved.receipts.acceptance_receipt and saved.acceptanceFinal, "Transaction/release state lost")
	end)
	second:EndSession()
	assert(ok, err)
	return {passed = true, mode = if mock then "StudioMock" else "StudioPersistent",
		persistent = not mock, apiState = library.DataStoreState, storeName = name, key = key,
		verified = {"confirmed manual save", "final release save", "session release/rejoin", "economy", "materials", "collections", "permanent progress", "receipt marker"},
		limitations = if mock then "Mock is memory in this play session; cross-play persistence not verified." else "Fresh isolated key only; production data unchanged."}
end
