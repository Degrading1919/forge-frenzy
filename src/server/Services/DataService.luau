--!strict
-- INTERIM STUB (Studio thread). In-memory profiles only, so the companions/evolution services can be
-- exercised in Studio before the core economy PR lands. Replace wholesale with the real
-- session-locked DataService from that PR; do not build on this file.
local Players = game:GetService("Players")

local DataService = {}
DataService.profileChanged = Instance.new("BindableEvent")

local profiles: { [Player]: any } = {}

local function default(): any
	return {
		coins = 0, lifetimeCoins = 0, weaponsForged = 0, highestWeaponValue = 0,
		selectedMaterial = 1, unlockedTier = 1,
		ore = {}, ingots = { [1] = 5 }, levels = {}, gear = {},
		weapons = {}, pending = nil, showcase = {}, journal = {},
		lastSeen = os.time(),
	}
end

function DataService.get(player: Player): any?
	return profiles[player]
end

function DataService.waitFor(player: Player): any?
	while player.Parent and not profiles[player] do
		task.wait()
	end
	return profiles[player]
end

function DataService.markDirty(player: Player)
	if profiles[player] then
		DataService.profileChanged:Fire(player, profiles[player])
	end
end

function DataService.start()
	local function add(player: Player)
		profiles[player] = default()
		DataService.markDirty(player)
	end
	Players.PlayerAdded:Connect(add)
	for _, p in Players:GetPlayers() do
		add(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		profiles[p] = nil
	end)
end

return DataService
