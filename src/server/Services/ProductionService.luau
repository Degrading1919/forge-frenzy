--!strict
--[[
	ProductionService — automatic extraction and smelting for every loaded player.

	Ticks once per second: each player's selected ore is extracted and smelted into ingots,
	stalling at storage caps (Economy.settle). Offline time since the last save is settled on
	join, capped by Balance.production.maxOfflineAccrualSec.

	Bonus hooks: bonuses(player) sums CompanionService.bonuses, EvolutionService.bonuses
	(`production` feeds extract and smelt, `prep` feeds prep) and Balance.premiumBonuses for
	every key MonetizationService.owns. Missing services contribute nothing, so this works
	before those modules land.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local Materials = require(Shared:WaitForChild("Config"):WaitForChild("Materials"))
local DataService = require(script.Parent.DataService)

local ProductionService = {}

ProductionService.TICK_SEC = 1
ProductionService.materialUnlocked = Instance.new("BindableEvent") -- (player, materialIndex)

local optional: { [string]: any } = {}

-- Requires a sibling service if it exists; nil otherwise. Cached once found.
local function service(name: string): any
	if optional[name] then
		return optional[name]
	end
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		optional[name] = result
		return result
	end
	return nil
end
ProductionService._service = service

local function safeCall(target: any, method: string, ...: any): any
	if target and type(target[method]) == "function" then
		local ok, result = pcall(target[method], ...)
		if ok then
			return result
		end
		warn(`[ProductionService] {method} failed:`, result)
	end
	return nil
end

-- Combined workshop bonuses for a player (fractions, capped per family when applied).
function ProductionService.bonuses(player: Player): Economy.Bonuses
	local sources: { any } = {}
	table.insert(sources, safeCall(service("CompanionService"), "bonuses", player))
	local evolution = safeCall(service("EvolutionService"), "bonuses", player)
	if type(evolution) == "table" then
		local production = tonumber(evolution.production) or 0
		table.insert(sources, { extract = production, smelt = production, prep = tonumber(evolution.prep) or 0 })
	end
	local monetization = service("MonetizationService")
	if monetization then
		for key, bonus in Balance.premiumBonuses do
			if safeCall(monetization, "owns", player, key) == true then
				table.insert(sources, bonus)
			end
		end
	end
	return Economy.combineBonuses(sources)
end

function ProductionService.rates(player: Player): Economy.Rates?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	return Economy.rates(data, ProductionService.bonuses(player))
end

function ProductionService.selectMaterial(player: Player, index: any): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	local ok, result = Economy.selectMaterial(data, index)
	if ok then
		DataService.markDirty(player)
	end
	return ok, result
end

function ProductionService.unlockNextMaterial(player: Player): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	local ok, result = Economy.unlockNextMaterial(data)
	if ok then
		DataService.markDirty(player)
		ProductionService.materialUnlocked:Fire(player, result)
	end
	return ok, result
end

-- Coins needed for the next extractor tier, or false at the last tier.
function ProductionService.unlockCost(player: Player): number | false
	local data = DataService.get(player)
	local nextMat = if data then Materials[data.unlockedTier + 1] else nil
	return if nextMat then nextMat.unlockCost else false
end

-- Called by DataService right after a profile loads.
function ProductionService.settleOffline(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	return Economy.settleOffline(data, os.time(), Economy.rates(data, ProductionService.bonuses(player)))
end

-- Advances one player by dt seconds. Returns ore and ingots produced.
function ProductionService.tickPlayer(player: Player, dt: number): (number, number)
	local data = DataService.get(player)
	if not data then
		return 0, 0
	end
	local ore, ingots = Economy.settle(data, dt, Economy.rates(data, ProductionService.bonuses(player)))
	data.lastSeen = os.time()
	if ore > 0 or ingots > 0 then
		DataService.markDirty(player)
	end
	return ore, ingots
end

function ProductionService.start()
	local Players = game:GetService("Players")
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(ProductionService.TICK_SEC)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(ProductionService.tickPlayer, player, dt)
				if not ok then
					warn("[ProductionService] tick failed:", err)
				end
			end
		end
	end)
end

return ProductionService
