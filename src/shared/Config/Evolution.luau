--!strict
--[[
	Blacksmith Evolution (rebirth). Status: PROPOSED FOR PROTOTYPE (docs/06, docs/13).

	Eligibility at current rank r (one predicate for both normal and protected paths):
	  * forged since last evolution  >= 150 + 50r
	  * fresh tier since last evolution >= min(32, 4 + 2r)
	"Fresh tier" only counts progress made after the last evolution, so a protected
	evolution that keeps a high extractor cannot qualify again immediately. It is the larger of:
	  - the extractor tier, if it was unlocked above the tier held right after the last evolve;
	  - the tier whose cumulative unlock cost the player has *earned* in coins since the last
	    evolve (purchased coins never count, retained coins never count).
]]

local Evolution = {}

Evolution.Name = "Blacksmith Evolution"

function Evolution.forgeRequirement(rank: number): number
	return 150 + 50 * rank
end

function Evolution.tierRequirement(rank: number): number
	return math.min(32, 4 + 2 * rank)
end

-- Permanent rewards per rank (additive fractions).
Evolution.ProductionPerRank = 0.15
Evolution.PrepPerRank = 0.03

-- Profile fields a normal evolution resets (owned by the core economy thread). The value each
-- returns to comes from Shared.Economy.newProfile() when present; `value` is the fallback.
-- Tables are deep-copied on reset. The preview and the reset both read this
-- list, so what the player is shown is exactly what happens.
Evolution.Resets = {
	{ field = "coins", label = "Coins", value = 0 },
	{ field = "ore", label = "Raw ore", value = {} },
	{ field = "ingots", label = "Ingots", value = {} },
	{ field = "progress", label = "Partly mined ore and partly smelted ingots", value = { ore = 0, smelt = 0 } },
	{ field = "unlockedTier", label = "Extractor tier (materials stay in your catalog)", value = 1 },
	{ field = "levels", label = "Machine upgrade levels", value = {} },
	{ field = "selectedMaterial", label = "Selected material (back to Copper)", value = 1 },
}

Evolution.Keeps = {
	"Weapon collection, showcase and discovery journal",
	"Companions and equipped companions",
	"Game passes and purchases",
	"Blacksmith gear",
	"Lifetime stats and leaderboard records",
	"Evolution rank and all evolution bonuses",
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
