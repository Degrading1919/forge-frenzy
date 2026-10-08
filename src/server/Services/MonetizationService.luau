--!strict
--[[
	MonetizationService: game pass ownership, developer product receipts, Studio-only dev
	entitlements and the paid-random-item policy gate.

	Safety rules (docs/07, CLAUDE.md):
	  * Never prompts a purchase while Config.Products.LIVE is false, or for an id of 0.
	  * Never trusts the client: ownership comes from MarketplaceService on the server,
	    receipts are applied once per PurchaseId, recorded in the profile.
	  * Paid-random items (Premium Auto Forge, Multi-Hatch) are not offered when PolicyService
	    restricts paid random items for that player, or when the policy lookup fails.
	  * grantDev only works in Studio, and its pass grants live in a session-only overlay
	    that is never saved.
	  * Roblox API calls are pcall-wrapped so Studio without API access does not error.

	Profile fields owned here:
	  entitlements  { [passKey]: true }          verified pass ownership (cache)
	  receipts      { [purchaseId]: unixTime }   processed dev product receipts
	Writes on purchase: coins (StarterPack), evolveCharges, pets (via CompanionService.Logic).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Products = require(Config:WaitForChild("Products"))

local MonetizationService = {}
local Logic = {}
MonetizationService.Logic = Logic

local deps: { [string]: any } = {
	getProfile = function(_player: any): any
		return nil
	end,
	markDirty = function(_player: any) end,
	saveNow = nil, -- optional (player) -> boolean; used before acknowledging a receipt
	isStudio = function(): boolean
		return false
	end,
	now = os.time,
	paidRandomRestricted = function(_player: any): boolean
		return true -- fail closed until PolicyService answers
	end,
	companionLogic = nil, -- CompanionService.Logic
	evolutionLogic = nil, -- EvolutionService.Logic
	marketplace = nil, -- MarketplaceService
	requestPolicy = nil,
}

-- Session-only state, keyed weakly by player; never written to the profile.
local devPasses: { [any]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local policyCache: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function dataOf(player: any): any
	local profile = deps.getProfile(player)
	if type(profile) ~= "table" then
		return nil
	end
	return if type(profile.Data) == "table" then profile.Data else profile
end

--------------------------------------------------------------------------------
-- Pure profile logic
--------------------------------------------------------------------------------

function Logic.ensure(profile: any)
	if type(profile.entitlements) ~= "table" then
		profile.entitlements = {}
	end
	if type(profile.receipts) ~= "table" then
		profile.receipts = {}
	end
end

-- Hand out what a product/pass grants. `src` = "dev" marks Studio test grants.
function Logic.applyGrants(profile: any, product: Products.Product, now: number, src: string?)
	local grants = product.grants
	if grants == nil then
		return
	end
	if grants.coins then
		-- Purchased coins are spendable only: not lifetimeCoins, so they never count toward
		-- leaderboards or evolution progress.
		profile.coins = (profile.coins or 0) + grants.coins
	end
	if grants.evolveCharges and deps.evolutionLogic then
		deps.evolutionLogic.addCharges(profile, grants.evolveCharges)
	end
	if grants.companion and deps.companionLogic then
		deps.companionLogic.grantKind(profile, grants.companion, { unique = product.kind == "pass", now = now, src = src })
	end
end

--[[
	Apply a developer product receipt exactly once.
	Returns "granted" (newly applied), "duplicate" (already applied) or "unknown".
]]
function Logic.applyReceipt(profile: any, purchaseId: string, productId: number, now: number): string
	Logic.ensure(profile)
	if profile.receipts[purchaseId] ~= nil then
		return "duplicate"
	end
	local product = Products.ProductById[productId]
	if product == nil then
		return "unknown"
	end
	Logic.applyGrants(profile, product, now)
	profile.receipts[purchaseId] = now
	-- Keep the ledger: Roblox may retry an old receipt; age is not proof it was acknowledged.
	return "granted"
end

-- Record a verified pass and run its one-time grants (idempotent; safe on every join).
function Logic.recordPass(profile: any, key: string, now: number)
	Logic.ensure(profile)
	local product = Products.ByKey[key]
	if product == nil or product.kind ~= "pass" then
		return
	end
	profile.entitlements[key] = true
	Logic.applyGrants(profile, product, now)
end

-- A successful platform lookup is authoritative even when it says false. Revoking a pass
-- disables its ongoing effects only; previously granted companions and saved progress stay.
function Logic.reconcilePass(profile: any, key: string, owned: boolean, now: number?)
	Logic.ensure(profile)
	local product = Products.ByKey[key]
	if product == nil or product.kind ~= "pass" then return end
	if owned == true then
		Logic.recordPass(profile, key, now or deps.now())
	else
		profile.entitlements[key] = nil
	end
end

-- Summed pass effects for a set of owned keys, capped per family by Products.EffectCap.
function Logic.effects(owned: { [string]: boolean })
	local out = { extract = 0, smelt = 0, prep = 0, storage = 0, forgeSlots = 0 }
	for key in owned do
		local product = Products.ByKey[key]
		if product and product.effects then
			for family, value in product.effects do
				out[family] = (out[family] or 0) + value
			end
		end
	end
	for family, value in out do
		local cap = Products.EffectCap[family]
		if cap then
			out[family] = math.min(value, cap)
		end
	end
	return out
end

--[[
	Whether a purchase may be prompted. Pure so it can be tested:
	  live        Products.LIVE
	  restricted  PolicyService says paid random items are restricted (or lookup failed)
	  owned       the player already owns this pass
]]
function Logic.canPrompt(product: Products.Product?, live: boolean, restricted: boolean, owned: boolean): (boolean, string?)
	if product == nil then
		return false, "unknown product"
	end
	if not live then
		return false, "store not live"
	end
	if product.id == 0 then
		return false, "product not configured"
	end
	if product.paidRandom and restricted then
		return false, "not available in your region"
	end
	if product.kind == "pass" and owned then
		return false, "already owned"
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- Player-level API
--------------------------------------------------------------------------------

function MonetizationService.owns(player: any, key: string): boolean
	local overlay = devPasses[player]
	if overlay and overlay[key] then
		return true
	end
	local profile = dataOf(player)
	return profile ~= nil and type(profile.entitlements) == "table" and profile.entitlements[key] == true
end

function MonetizationService.ownedKeys(player: any): { [string]: boolean }
	local out = {}
	local profile = dataOf(player)
	if profile and type(profile.entitlements) == "table" then
		for key, value in profile.entitlements do
			if value == true then
				out[key] = true
			end
		end
	end
	for key in devPasses[player] or {} do
		out[key] = true
	end
	return out
end

-- Pass effects in companion bonus families plus forgeSlots, for ProductionService/ForgeService.
function MonetizationService.bonuses(player: any)
	return Logic.effects(MonetizationService.ownedKeys(player))
end

function MonetizationService.canOfferPaidRandom(player: any): boolean
	-- Test passes are session overlays on an isolated Studio profile, never real purchases.
	if deps.isStudio() and next(devPasses[player] or {}) ~= nil then
		return true
	end
	return not deps.paidRandomRestricted(player)
end

function MonetizationService.canPrompt(player: any, key: string): (boolean, string?)
	local product = Products.ByKey[key]
	local restricted = product ~= nil and product.paidRandom == true and deps.paidRandomRestricted(player)
	return Logic.canPrompt(product, Products.LIVE, restricted, MonetizationService.owns(player, key))
end

function MonetizationService.prompt(player: any, key: string): (boolean, any)
	local ok, why = MonetizationService.canPrompt(player, key)
	if not ok then
		return false, why
	end
	local product = Products.ByKey[key]
	local market = deps.marketplace
	if market == nil then
		return false, "marketplace unavailable"
	end
	local called, err = pcall(function()
		if product.kind == "pass" then
			market:PromptGamePassPurchase(player, product.id)
		else
			market:PromptProductPurchase(player, product.id)
		end
	end)
	if not called then
		return false, tostring(err)
	end
	return true, key
end

-- Studio-only test entitlement. Passes go into the unsaved overlay; product grants and
-- companions are tagged src="dev" and stripped on load outside Studio.
function MonetizationService.grantDev(player: any, key: string): (boolean, any)
	if not deps.isStudio() then
		return false, "dev grants are Studio-only"
	end
	local product = Products.ByKey[key]
	if product == nil then
		return false, "unknown product"
	end
	local profile = dataOf(player)
	if profile == nil then
		return false, "profile not loaded"
	end
	Logic.ensure(profile)
	if product.kind == "pass" then
		devPasses[player] = devPasses[player] or {}
		devPasses[player][key] = true
	end
	Logic.applyGrants(profile, product, deps.now(), "dev")
	deps.markDirty(player)
	return true, key
end

function MonetizationService.revokeDev(player: any, key: string): (boolean, any)
	local overlay = devPasses[player]
	if overlay then
		overlay[key] = nil
	end
	return true, key
end

-- ProcessReceipt body; returns "PurchaseGranted" or "NotProcessedYet" (mapped to the enum).
function MonetizationService.processReceipt(receiptInfo: any, player: any): string
	if player == nil or type(receiptInfo) ~= "table"
		or receiptInfo.PlayerId ~= player.UserId or type(receiptInfo.PurchaseId) ~= "string"
		or receiptInfo.PurchaseId == "" or type(receiptInfo.ProductId) ~= "number" then
		return "NotProcessedYet"
	end
	local profile = dataOf(player)
	if profile == nil then
		return "NotProcessedYet"
	end
	local result = Logic.applyReceipt(profile, tostring(receiptInfo.PurchaseId), receiptInfo.ProductId, deps.now())
	if result == "unknown" then
		warn(`[Monetization] unknown product id {receiptInfo.ProductId}`)
		return "NotProcessedYet"
	end
	deps.markDirty(player)
	if deps.saveNow then
		-- Acknowledge only once the receipt id is durably saved; a retry is a no-op thanks to
		-- the ledger, so returning NotProcessedYet here can never double-grant.
		local purchaseId = receiptInfo.PurchaseId
		local ok, saved = pcall(deps.saveNow, player, 15, function(savedData)
			return type(savedData.receipts) == "table" and savedData.receipts[purchaseId] ~= nil
		end)
		if not ok or saved ~= true or dataOf(player) ~= profile then
			return "NotProcessedYet"
		end
	else
		return "NotProcessedYet"
	end
	return "PurchaseGranted"
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function MonetizationService._inject(overrides: { [string]: any })
	for key, value in overrides do
		deps[key] = value
	end
	table.clear(devPasses)
	table.clear(policyCache)
end

function MonetizationService.init()
	local services = script.Parent
	local DataService = require(services:WaitForChild("DataService")) :: any
	local RunService = game:GetService("RunService")
	local PolicyService = game:GetService("PolicyService")
	deps.marketplace = game:GetService("MarketplaceService")
	deps.getProfile = function(player)
		return DataService.get(player)
	end
	deps.markDirty = function(player)
		DataService.markDirty(player)
	end
	-- Optional explicit save hook, if the DataService exposes one.
	local save = DataService.saveNow or DataService.save
	if type(save) == "function" then
		deps.saveNow = function(player, timeoutSec, predicate)
			return save(player, timeoutSec, predicate)
		end
	end
	deps.isStudio = function()
		return RunService:IsStudio()
	end
	deps.paidRandomRestricted = function(player)
		return policyCache[player] ~= false -- synchronous and fail closed during lookup
	end
	deps.requestPolicy = function(player)
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if not ok or type(info) ~= "table" then
			return true
		end
		local restricted = info.ArePaidRandomItemsRestricted ~= false
		policyCache[player] = restricted
		return restricted
	end
	local companion = services:FindFirstChild("CompanionService")
	if companion then
		deps.companionLogic = (require(companion) :: any).Logic
	end
	local evolution = services:FindFirstChild("EvolutionService")
	if evolution then
		deps.evolutionLogic = (require(evolution) :: any).Logic
	end
end

function MonetizationService.start()
	local Players = game:GetService("Players")
	local market = deps.marketplace
	local DataService = require(script.Parent:WaitForChild("DataService")) :: any

	-- Verify passes with Roblox on join; ids of 0 are skipped.
	local function verifyPasses(player: Player)
		if deps.requestPolicy then deps.requestPolicy(player) end
		local profile = DataService.waitFor(player)
		local data = if profile and type(profile.Data) == "table" then profile.Data else profile
		if data == nil then
			return
		end
		Logic.ensure(data)
		for _, product in Products.List do
			if product.kind == "pass" then
				if product.id ~= 0 then
					local ok, owns = pcall(market.UserOwnsGamePassAsync, market, player.UserId, product.id)
					if dataOf(player) ~= data then return end
					if ok then
						Logic.reconcilePass(data, product.key, owns == true, deps.now())
					end
				elseif data.entitlements[product.key] then
					-- Re-run idempotent grants (e.g. a premium companion that went missing).
					Logic.recordPass(data, product.key, deps.now())
				end
			end
		end
		DataService.markDirty(player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(verifyPasses, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(verifyPasses, player)
	end

	market.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local product = Products.PassById[passId]
		if not purchased or product == nil then
			return
		end
		local data = dataOf(player)
		local ok, owns = pcall(market.UserOwnsGamePassAsync, market, player.UserId, passId)
		if data and dataOf(player) == data and ok then
			Logic.reconcilePass(data, product.key, owns == true, deps.now())
			DataService.markDirty(player)
		end
	end)

	market.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		local decision = MonetizationService.processReceipt(receiptInfo, player)
		return Enum.ProductPurchaseDecision[decision]
	end
end

return MonetizationService
