--!strict
--[[
	UpgradeService — coin purchases for machine tracks (ExtractorOutput, SmelterSpeed,
	StorageCapacity, FurnaceHeat, AnvilFinish) and gear tracks (Hammer, Gloves, Apron).
	Costs and effects come from Config/Balance; unlocking the next material is
	ProductionService.unlockNextMaterial.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local DataService = require(script.Parent.DataService)

local UpgradeService = {}

UpgradeService.upgraded = Instance.new("BindableEvent") -- (player, track, newLevel)

function UpgradeService.buy(player: Player, track: any): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "NotLoaded"
	end
	local ok, result = Economy.buyUpgrade(data, track)
	if ok then
		DataService.markDirty(player)
		UpgradeService.upgraded:Fire(player, track, result)
	end
	return ok, result
end

-- Coins for the next level of `track`, or false when maxed, unknown or not loaded.
function UpgradeService.cost(player: Player, track: any): number | false
	local data = DataService.get(player)
	local level = if data and type(track) == "string" then Economy.trackLevel(data, track) else nil
	if level == nil then
		return false
	end
	return Balance.upgradeCost(track, level) or false
end

export type TrackInfo = { track: string, name: string, kind: string, level: number, maxLevel: number, cost: number?, look: string? }

-- Shop listing: every track with its current level and next cost (nil when maxed).
function UpgradeService.list(player: Player): { TrackInfo }?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	local out = {}
	for _, names in { Balance.machineTracks, Balance.gearTracks } do
		for _, track in names do
			local def = Balance.tracks[track]
			local level = Economy.trackLevel(data, track) or 0
			table.insert(out, {
				track = track,
				name = def.name,
				kind = def.kind,
				level = level,
				maxLevel = def.maxLevel,
				cost = Balance.upgradeCost(track, level),
				look = Balance.gearLook(track, level),
			})
		end
	end
	return out
end

return UpgradeService
