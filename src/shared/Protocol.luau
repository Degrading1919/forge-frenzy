--!strict
-- Client <-> server contract (v2, docs/22). The server creates ReplicatedStorage.Remotes at boot:
--   Remotes.Action  (RemoteFunction)  client -> server: Action:InvokeServer(name, ...) -> (ok: boolean, result: any)
--   Remotes.Strike  (RemoteEvent)     client -> server: Strike:FireServer(sessionId)  (one per hammer hit)
--   Remotes.Push    (RemoteEvent)     server -> client: Push.OnClientEvent(kind, payload)
-- Clients only express intent; every rule (including "you must be standing at the booth /
-- forge / pad") is enforced on the server.

local Protocol = {}

Protocol.Actions = {
	-- Forge stations
	ForgeBegin = "ForgeBegin", -- (station, mode: "manual"|"free"|"premium") -> { sessionId, heatSec, windowSec, revealSec } | { waiting }
	ForgeStop = "ForgeStop", -- (station?) stops Auto Forge on a station (all when nil)
	ForgeConfigure = "ForgeConfigure", -- (station, materialIndex, classIndex, keepFrom) stops that station's auto first
	-- Ore lines and materials
	LineMaterial = "LineMaterial", -- (line, materialIndex)
	UnlockMaterial = "UnlockMaterial", -- (materialIndex, line?) buys the next material
	BuyUpgrade = "BuyUpgrade", -- (track)
	BuyPad = "BuyPad", -- (padId) must stand on the pad
	-- Weapons
	SellAll = "SellAll", -- (keepFrom?) at the sell booth; keeps displayed weapons
	SellWeapons = "SellWeapons", -- ({ weaponId }) at the sell booth
	SetShowcase = "SetShowcase", -- (slot 1..8, weaponId | nil)
	ToggleShowcase = "ToggleShowcase", -- (weaponId) first free podium / take down
	CollectCash = "CollectCash", -- () at the cash collector
	-- Social
	LockForge = "LockForge", -- () at the lock button
	StealBegin = "StealBegin", -- (plotIndex, slot) started holding the steal prompt
	StealCommit = "StealCommit", -- (plotIndex, slot) finished holding
	StealCancel = "StealCancel", -- ()
	-- Pets
	Hatch = "Hatch", -- (eggId, count) -> { pets }
	EquipPet = "EquipPet", -- (petId)
	UnequipPet = "UnequipPet", -- (petId)
	EquipBestPets = "EquipBestPets", -- ()
	ReleasePet = "ReleasePet", -- (petId)
	MergePet = "MergePet", -- (petId) three identical pets -> one level higher
	MergeAll = "MergeAll", -- ()
	-- Evolution / meta
	EvolutionStatus = "EvolutionStatus", -- () -> status table
	Evolve = "Evolve", -- (protected: boolean) -> newRank
	Leaderboards = "Leaderboards", -- () -> { [metric] = {{ userId, name, value }} }
	Purchase = "Purchase", -- (productKey) prompts a real purchase only when Products.LIVE
	DevGrant = "DevGrant", -- (productKey) Studio-only test entitlement
	SetSetting = "SetSetting", -- (key, value) e.g. "music", "sfx", "vfx"
	TutorialStep = "TutorialStep", -- (stepIndex) records onboarding progress
	Rates = "Rates", -- () -> rates
}

Protocol.Push = {
	Profile = "Profile", -- full replicated profile snapshot (Net/Remotes snapshot())
	ForgeResult = "ForgeResult", -- { station, results = { { weapon, sold, coins } }, luck, strikes, auto }
	ForgePhase = "ForgePhase", -- { station, sessionId, phase, endsAt, mode, auto, reason? }
	Toast = "Toast", -- { text, kind: "info"|"good"|"bad" }
	Announce = "Announce", -- { text, rarity } server-wide rare forge announcement (rate limited)
	Hatched = "Hatched", -- { pets = { Pet } }
	Evolved = "Evolved", -- { rank, protected }
	Sold = "Sold", -- { coins, count }
	Built = "Built", -- { padId }
	Merged = "Merged", -- { pets }
	Steal = "Steal", -- { thief, victim (userIds), slot, outcome, deadline? } broadcast
	Unlocked = "Unlocked", -- { material }
}

return Protocol
