--!strict
-- Client <-> server contract. The server creates ReplicatedStorage.Remotes at boot:
--   Remotes.Action  (RemoteFunction)  client -> server: Action:InvokeServer(name, ...) -> (ok: boolean, result: any)
--   Remotes.Strike  (RemoteEvent)     client -> server: Strike:FireServer(sessionId)  (one per hammer hit)
--   Remotes.Push    (RemoteEvent)     server -> client: Push.OnClientEvent(kind, payload)
-- Clients only express intent; every rule is enforced on the server.

local Protocol = {}

Protocol.Actions = {
	ForgeStart = "ForgeStart", -- (classIndex, materialIndex, mode: "manual"|"free"|"premium") -> { sessionId, heatSec, windowSec, revealSec }
	ForgeResolve = "ForgeResolve", -- (action: "sell"|"keep") -> { coins? , weaponId? }
	ForgeStopAuto = "ForgeStopAuto", -- ()
	SelectMaterial = "SelectMaterial", -- (materialIndex)
	UnlockMaterial = "UnlockMaterial", -- () unlock next extractor tier
	BuyUpgrade = "BuyUpgrade", -- (track) machine or gear track name
	SellWeapon = "SellWeapon", -- (weaponId) sell a kept weapon
	SetShowcase = "SetShowcase", -- (slot 1..6, weaponId | nil)
	Hatch = "Hatch", -- (eggId, count) -> { pets }
	EquipPet = "EquipPet", -- (petId)
	UnequipPet = "UnequipPet", -- (petId)
	EquipBestPets = "EquipBestPets", -- () equip strongest owned companions
	ReleasePet = "ReleasePet", -- (petId) permanently release a non-premium companion
	EvolutionStatus = "EvolutionStatus", -- () -> status table
	Evolve = "Evolve", -- (protected: boolean) -> newRank
	Leaderboards = "Leaderboards", -- () -> { [metric] = {{ userId, name, value }} }
	Purchase = "Purchase", -- (productKey) prompts a real purchase only when Products.LIVE
	DevGrant = "DevGrant", -- (productKey) Studio-only test entitlement
	SetSetting = "SetSetting", -- (key, value) e.g. "autoSellBelow" (rarity index), "music", "vfx"
	TutorialStep = "TutorialStep", -- (stepIndex) records onboarding progress
	Rates = "Rates", -- () -> { orePerSec, ingotPerSec, capacity, heatSec, revealSec, luckModes }
}

Protocol.Push = {
	Profile = "Profile", -- full replicated profile snapshot (see Net.server snapshot())
	ForgeResult = "ForgeResult", -- { weapon, luck, strikes, auto: boolean }
	ForgePhase = "ForgePhase", -- { sessionId, phase: "heat"|"strike"|"quench"|"done"|"cancelled" }
	Toast = "Toast", -- { text, kind: "info"|"good"|"bad" }
	Announce = "Announce", -- { text, rarity } server-wide rare forge announcement (rate limited)
	Hatched = "Hatched", -- { pets = { Pet } }
	Evolved = "Evolved", -- { rank, protected }
}

return Protocol
