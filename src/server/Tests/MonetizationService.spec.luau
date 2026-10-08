-- Receipt idempotency, prompt gating, paid-random policy, pass effect caps and dev mode.
-- Never touches MarketplaceService: every test uses pure logic or a cloned, injected module.

local Services = script.Parent.Parent:WaitForChild("Services")
local Config = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config")
local Products = require(Config:WaitForChild("Products"))
local Companions = require(Config:WaitForChild("Companions"))
local CompanionLogic = require(Services:WaitForChild("CompanionService")).Logic
local EvolutionLogic = require(Services:WaitForChild("EvolutionService")).Logic

local function fresh()
	local Service = require(Services:WaitForChild("MonetizationService"):Clone())
	Service._inject({ companionLogic = CompanionLogic, evolutionLogic = EvolutionLogic })
	return Service
end

-- Products with real ids only exist after the owner creates them; build a test copy.
local function withId(key: string, id: number)
	local product = table.clone(Products.ByKey[key])
	product.id = id
	return product
end

local tests = {}

tests["store ships with LIVE off"] = function()
	assert(Products.LIVE == false, "Products.LIVE must stay false until the owner approves")
end

tests["catalog grants reference real premium companions"] = function()
	for _, product in Products.List do
		local companion = product.grants and product.grants.companion
		if companion then
			local kind = Companions.ById[companion]
			assert(kind and kind.premium, product.key .. " grants a non-premium or unknown companion")
		end
	end
end

tests["no product unlocks a material tier or raises luck past the free cap"] = function()
	for _, product in Products.List do
		for family in product.effects or {} do
			assert(family ~= "unlockedTier" and family ~= "luck", product.key .. " sells a progression gate")
		end
	end
end

tests["canPrompt refuses when not live, unconfigured, restricted or owned"] = function()
	local Logic = fresh().Logic
	local pass = withId("PremiumAutoForge", 111)
	assert(not Logic.canPrompt(pass, false, false, false))
	assert(not Logic.canPrompt(Products.ByKey.PremiumAutoForge, true, false, false)) -- id 0
	local ok, why = Logic.canPrompt(pass, true, true, false)
	assert(not ok and why == "not available in your region")
	assert(not Logic.canPrompt(pass, true, false, true))
	assert(Logic.canPrompt(pass, true, false, false))
	-- Non-random items are unaffected by the paid-random restriction.
	assert(Logic.canPrompt(withId("TitanExcavator", 222), true, true, false))
	assert(not Logic.canPrompt(nil, true, false, false))
end

tests["player prompt never fires while LIVE is false"] = function()
	local Service = fresh()
	local prompted = false
	Service._inject({
		marketplace = {
			PromptGamePassPurchase = function()
				prompted = true
			end,
			PromptProductPurchase = function()
				prompted = true
			end,
		},
		paidRandomRestricted = function()
			return false
		end,
	})
	for _, product in Products.List do
		assert(not Service.prompt({ UserId = 1 }, product.key))
	end
	assert(not prompted)
end

tests["receipts apply exactly once"] = function()
	local Logic = fresh().Logic
	local starter = withId("StarterPack", 9001)
	Products.ProductById[9001] = starter
	local p = { coins = 10 }
	local first = Logic.applyReceipt(p, "purchase-1", 9001, 100)
	local second = Logic.applyReceipt(p, "purchase-1", 9001, 101)
	Products.ProductById[9001] = nil
	assert(first == "granted" and second == "duplicate")
	assert(p.coins == 10 + starter.grants.coins)
	assert(CompanionLogic.petCount(p) == 1)
end

tests["purchased coins do not touch lifetime coins"] = function()
	local Logic = fresh().Logic
	Products.ProductById[9002] = withId("StarterPack", 9002)
	local p = { coins = 0, lifetimeCoins = 5 }
	Logic.applyReceipt(p, "x", 9002, 1)
	Products.ProductById[9002] = nil
	assert(p.lifetimeCoins == 5)
end

tests["unknown products are not marked processed"] = function()
	local Logic = fresh().Logic
	local p = { coins = 0 }
	assert(Logic.applyReceipt(p, "purchase-2", 424242, 1) == "unknown")
	assert(p.receipts["purchase-2"] == nil and p.coins == 0)
end

tests["protected evolution product adds one charge per purchase"] = function()
	local Logic = fresh().Logic
	Products.ProductById[9003] = withId("ProtectedEvolution", 9003)
	local p = {}
	Logic.applyReceipt(p, "a", 9003, 1)
	Logic.applyReceipt(p, "b", 9003, 2)
	Logic.applyReceipt(p, "b", 9003, 3)
	Products.ProductById[9003] = nil
	assert(p.evolveCharges == 2)
end

tests["receipt ledger is pruned only for old entries"] = function()
	local Logic = fresh().Logic
	Products.ProductById[9004] = withId("ProtectedEvolution", 9004)
	local p = {}
	for i = 1, 260 do
		Logic.applyReceipt(p, "r" .. i, 9004, i)
	end
	local recentCount = 0
	for _ in p.receipts do
		recentCount += 1
	end
	assert(recentCount == 260, "young receipts must never be pruned")
	local later = 100 * 24 * 3600
	Logic.applyReceipt(p, "late", 9004, later)
	local count = 0
	for _ in p.receipts do
		count += 1
	end
	Products.ProductById[9004] = nil
	assert(count == 200, "expected pruning to 200, got " .. count)
	assert(p.receipts.late ~= nil and p.receipts.r260 ~= nil and p.receipts.r1 == nil)
end

tests["processReceipt waits for a successful save before acknowledging"] = function()
	local Service = fresh()
	Products.ProductById[9005] = withId("StarterPack", 9005)
	local data = { coins = 0 }
	local saveWorks = false
	Service._inject({
		getProfile = function()
			return data
		end,
		saveNow = function()
			return saveWorks
		end,
	})
	local info = { PlayerId = 1, PurchaseId = "p-1", ProductId = 9005 }
	assert(Service.processReceipt(info, { UserId = 1 }) == "NotProcessedYet")
	saveWorks = true
	assert(Service.processReceipt(info, { UserId = 1 }) == "PurchaseGranted")
	Products.ProductById[9005] = nil
	assert(data.coins == 2500, "retry must not double-grant, coins = " .. data.coins)
	assert(Service.processReceipt(info, nil) == "NotProcessedYet")
end

tests["pass effects are summed and capped"] = function()
	local Logic = fresh().Logic
	local e = Logic.effects({ TitanExcavator = true, DragonFurnace = true, VIPWorkshop = true, MultiForge = true })
	assert(e.extract == 1.0 and e.prep == 0.5 and e.smelt == 0.25 and e.forgeSlots == 1)
	local none = Logic.effects({})
	assert(none.extract == 0 and none.forgeSlots == 0)
end

tests["recording a companion pass is idempotent"] = function()
	local Logic = fresh().Logic
	local p = {}
	Logic.recordPass(p, "GoldenForgeDragon", 1)
	Logic.recordPass(p, "GoldenForgeDragon", 2)
	assert(p.entitlements.GoldenForgeDragon == true and CompanionLogic.petCount(p) == 1)
	Logic.recordPass(p, "StarterPack", 3) -- a product, not a pass: ignored
	assert(p.entitlements.StarterPack == nil)
end

tests["grantDev works only in Studio and never saves pass ownership"] = function()
	local Service = fresh()
	local data = {}
	local studio = false
	Service._inject({
		getProfile = function()
			return data
		end,
		isStudio = function()
			return studio
		end,
	})
	local player = { UserId = 1 }
	assert(not Service.grantDev(player, "PremiumAutoForge"))
	assert(not Service.owns(player, "PremiumAutoForge"))
	studio = true
	assert(Service.grantDev(player, "PremiumAutoForge"))
	assert(Service.owns(player, "PremiumAutoForge"))
	assert(data.entitlements.PremiumAutoForge == nil, "dev pass leaked into saved profile")
	Service.revokeDev(player, "PremiumAutoForge")
	assert(not Service.owns(player, "PremiumAutoForge"))
	assert(Service.grantDev(player, "GoldenForgeDragon"))
	local dragon
	for _, pet in data.pets do
		dragon = pet
	end
	assert(dragon and dragon.src == "dev", "dev companion must be tagged for stripping")
end

tests["paid-random gate fails closed by default"] = function()
	local Service = fresh()
	assert(not Service.canOfferPaidRandom({ UserId = 1 }))
	Service._inject({
		paidRandomRestricted = function()
			return false
		end,
	})
	assert(Service.canOfferPaidRandom({ UserId = 1 }))
end

tests["owns reads verified entitlements from the profile"] = function()
	local Service = fresh()
	local data = { entitlements = { TitanExcavator = true } }
	Service._inject({
		getProfile = function()
			return { Data = data }
		end,
	})
	assert(Service.owns({}, "TitanExcavator") and not Service.owns({}, "VIPWorkshop"))
	assert(Service.bonuses({}).extract == 1.0)
end

return tests
