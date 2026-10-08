--!strict
--[[
	Evolution (rebirth). Status: v2 after the owner playtest (docs/21 §15, docs/22).

	Eligibility at current rank r (one predicate for both normal and protected paths):
	  * forged since last evolution  >= BaseForges + ForgesPerRank * r
	  * fresh tier since last evolution >= min(32, BaseTier + TierPerRank * r)
	"Fresh tier" only counts progress made after the last evolution, so a protected
	evolution that keeps a high extractor cannot qualify again immediately. It is the larger of:
	  - the extractor tier, if it was unlocked above the tier held right after the last evolve;
	  - the tier whose cumulative unlock cost the player has *earned* in coins since the last
	    evolve (purchased coins never count, retained coins never count).
]]

local Evolution = {}

Evolution.Name = "Evolution"

-- Requirements (v2, docs/22): forge a batch of weapons and reach a fresh material tier.
Evolution.BaseForges = 120
Evolution.ForgesPerRank = 60
Evolution.BaseTier = 6
Evolution.TierPerRank = 2

function Evolution.forgeRequirement(rank: number): number
	return Evolution.BaseForges + Evolution.ForgesPerRank * rank
end

function Evolution.tierRequirement(rank: number): number
	return math.min(32, Evolution.BaseTier + Evolution.TierPerRank * rank)
end

-- Permanent rewards per rank. Cash multiplies every weapon's value (and so display income);
-- production feeds the capped ore/smelt families; prep shortens heat.
Evolution.CashPerRank = 0.5
Evolution.ProductionPerRank = 0.1
Evolution.PrepPerRank = 0.03

function Evolution.cashMultiplier(rank: number): number
	return 1 + Evolution.CashPerRank * math.max(0, rank)
end

-- Profile fields a normal evolution resets. The value each returns to comes from
-- Shared.Economy.newProfile() when present; `value` is the fallback. Tables are deep-copied.
-- The preview and the reset both read this list, so what the player is shown is exactly what
-- happens. Build pads, displays, weapons, pets and gear are kept (Evolution.Keeps).
Evolution.Resets = {
	{ field = "coins", label = "Cash", value = 0 },
	{ field = "ingots", label = "Ingots", value = {} },
	{ field = "unlockedTier", label = "Materials (back to Copper)", value = 1 },
	{ field = "levels", label = "Machine upgrades", value = {} },
	{ field = "lines", label = "Ore line materials", value = {} },
	{ field = "stations", label = "Forge recipes", value = {} },
	{ field = "selectedMaterial", label = "Selected material", value = 1 },
	{ field = "bank", label = "Uncollected display cash", value = 0 },
}

-- Short labels for the KEEP column of the evolution screen.
Evolution.Keeps = {
	"Weapons & displays",
	"Workshop buildings",
	"Pets",
	"Tools (gear)",
	"Passes",
}

--[[
	Fallback extractor unlock costs (design/balance-v0.json) used only when
	Config.Materials is not available yet. Index t = cost to unlock tier t.
]]
Evolution.FallbackUnlockCosts = {
	0, 414, 870, 1836, 3754, 7451, 14764, 28990,
	56213, 108432, 207949, 396554, 752817, 1423811, 2683440, 5042013,
	9447043, 17656485, 32925235, 61270839, 113803947, 211011360, 390624215, 722053933,
	1332858017, 2457219103, 4524672333, 8322380636, 15291703042, 28069832629, 51478371750, 94326545693,
}

return Evolution
