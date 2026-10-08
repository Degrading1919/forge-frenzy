-- Pet merging (three identical pets of one level become one pet a level higher) and level
-- scaling of bonuses. Pure logic on bare profiles plus the player-level wrappers.

local Services = script.Parent.Parent:WaitForChild("Services")
local Config = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config")
local Companions = require(Config:WaitForChild("Companions"))
local Logic = require(Services:WaitForChild("CompanionService")).Logic

local function profile()
	return { coins = 0, unlockedTier = 1, evolutionRank = 0 }
end

-- Grants `n` plain copies of `kind` (non-unique) and returns their ids in creation order.
local function give(p: any, kind: string, n: number, level: number?): { string }
	local ids = {}
	for _ = 1, n do
		local ok, pet = Logic.grantKind(p, kind, { now = 1 })
		assert(ok)
		if level and level > 1 then
			pet.lv = level
		end
		table.insert(ids, pet.id)
	end
	return ids
end

local function count(p: any): number
	return Logic.petCount(p)
end

local tests = {}

tests["merge constants: three to one, five levels, rising multipliers"] = function()
	assert(Companions.MergeCount == 3 and Companions.MaxLevel == 5)
	assert(#Companions.LevelMultipliers == Companions.MaxLevel)
	assert(Companions.LevelMultipliers[1] == 1, "level 1 is the base bonus")
	for level = 2, Companions.MaxLevel do
		assert(Companions.LevelMultipliers[level] > Companions.LevelMultipliers[level - 1], "level " .. level)
	end
	-- merging must always be worth it: one pet at level n+1 beats the three pets it replaces
	for level = 1, Companions.MaxLevel - 1 do
		assert(Companions.LevelMultipliers[level + 1] > Companions.LevelMultipliers[level], "merge should not lose bonus")
	end
	assert(Companions.levelMultiplier(0) == 1 and Companions.levelMultiplier(99) == Companions.LevelMultipliers[5])
	assert(Companions.levelMultiplier(2.9) == Companions.LevelMultipliers[2], "fractional levels floor")
end

tests["three identical pets merge into one pet one level higher"] = function()
	local p = profile()
	local ids = give(p, "soot_mole", 3)
	assert(Logic.level(p.pets[ids[1]]) == 1)
	local ok, result = Logic.merge(p, ids[1])
	assert(ok, tostring(result))
	assert(result.pet == p.pets[ids[1]] and Logic.level(result.pet) == 2 and #result.consumed == 2)
	assert(count(p) == 1 and p.pets[ids[1]] ~= nil and p.pets[ids[2]] == nil and p.pets[ids[3]] == nil)
	assert(p.pets[ids[1]].k == "soot_mole")
	-- the survivor merges again with two new level-2 pets
	local more = give(p, "soot_mole", 2, 2)
	local ok2, result2 = Logic.merge(p, ids[1])
	assert(ok2 and Logic.level(p.pets[ids[1]]) == 3 and count(p) == 1 and p.pets[more[1]] == nil)
	assert(result2.consumed[1] ~= nil)
end

tests["merge needs MergeCount pets of the same kind and the same level"] = function()
	local p = profile()
	local mole = give(p, "soot_mole", 2)
	local ok, err = Logic.merge(p, mole[1])
	assert(not ok and err == "need more copies" and count(p) == 2, "two copies are not enough")
	give(p, "cinder_mole", 5) -- different kind, same rarity: never partners
	ok, err = Logic.merge(p, mole[1])
	assert(not ok and err == "need more copies" and count(p) == 7)
	give(p, "soot_mole", 5, 2) -- right kind, wrong level
	ok, err = Logic.merge(p, mole[1])
	assert(not ok and err == "need more copies" and count(p) == 12)
	-- a failed merge changes nothing
	for _, id in mole do
		assert(Logic.level(p.pets[id]) == 1)
	end
	ok, err = Logic.merge(p, "p9999")
	assert(not ok and err == "not owned")
	ok, err = Logic.merge(p, 5)
	assert(not ok and err == "not owned")
	ok, err = Logic.merge(p, nil)
	assert(not ok and err == "not owned")
end

tests["partner selection prefers unequipped pets, then the oldest ids"] = function()
	local p = profile()
	local ids = give(p, "soot_mole", 5)
	assert(Logic.equip(p, ids[1]) and Logic.equip(p, ids[2]))
	local partners = Logic.mergePartners(p, ids[5])
	assert(#partners == 2 and partners[1] == ids[3] and partners[2] == ids[4], "unequipped, oldest first")
	local ok, result = Logic.merge(p, ids[5])
	assert(ok and #result.consumed == 2)
	assert(p.pets[ids[3]] == nil and p.pets[ids[4]] == nil and p.pets[ids[1]] ~= nil and p.pets[ids[2]] ~= nil, "equipped pets are spared while others exist")
	assert(#p.equipped == 2)
	-- the kept pet stays equipped
	local q = profile()
	local qids = give(q, "soot_mole", 3)
	assert(Logic.equip(q, qids[1]))
	assert(Logic.merge(q, qids[1]))
	assert(#q.equipped == 1 and q.equipped[1] == qids[1] and Logic.level(q.pets[qids[1]]) == 2)
	-- equipped partners are consumed only when needed, and are removed from the loadout
	local r = profile()
	local rids = give(r, "soot_mole", 3)
	assert(Logic.equip(r, rids[2]) and Logic.equip(r, rids[3]))
	assert(Logic.merge(r, rids[1]))
	assert(#r.equipped == 0 and count(r) == 1, "no dangling equip entries")
	Logic.ensure(r)
	assert(r.petSlots == 2 and #r.equipped == 0)
end

tests["merging stops at the maximum level"] = function()
	local p = profile()
	local top = give(p, "soot_mole", 3, Companions.MaxLevel)
	local ok, err = Logic.merge(p, top[1])
	assert(not ok and err == "max level" and count(p) == 3)
	-- one level below the cap still merges into the cap
	local q = profile()
	local ids = give(q, "soot_mole", 3, Companions.MaxLevel - 1)
	assert(Logic.merge(q, ids[1]) and Logic.level(q.pets[ids[1]]) == Companions.MaxLevel)
	-- a malformed level is read as level 1 and never exceeds the cap
	assert(Logic.level({ lv = "x" }) == 1 and Logic.level({ lv = 0 / 0 }) == 1 and Logic.level({ lv = 99 }) == Companions.MaxLevel)
	assert(Logic.level({ lv = -3 }) == 1 and Logic.level({}) == 1 and Logic.level(nil) == 1)
end

tests["premium companions cannot be merged"] = function()
	local p = profile()
	local dragons = give(p, "golden_forge_dragon", 3)
	local ok, err = Logic.merge(p, dragons[1])
	assert(not ok and err == "premium companions cannot be merged" and count(p) == 3)
	local ok2, err2 = Logic.mergeAll(p)
	assert(not ok2 and err2 == "nothing to merge" and count(p) == 3, "mergeAll skips premium pets")
	local pup = give(p, "apprentice_anvil_pup", 3)
	assert(not Logic.merge(p, pup[1]))
end

tests["bonuses multiply by the pet's level and still respect the family cap"] = function()
	for level = 1, Companions.MaxLevel do
		local p = profile()
		local ids = give(p, "soot_mole", 1, level)
		assert(Logic.equip(p, ids[1]))
		local expected = 0.04 * Companions.LevelMultipliers[level]
		assert(math.abs(Logic.bonuses(p).extract - expected) < 1e-12, "level " .. level)
	end
	-- multi-family pets scale every family
	local q = profile()
	local star = give(q, "starforged_golem", 1, 3)
	Logic.equip(q, star[1])
	local b = Logic.bonuses(q)
	assert(math.abs(b.extract - 0.60 * 2.5) < 1e-12 and math.abs(b.smelt - 0.50 * 2.5) < 1e-12)
	-- big multipliers never exceed the cap
	local r = profile()
	local golems = give(r, "tempest_golem", 2, Companions.MaxLevel)
	r.evolutionRank = 1
	Logic.equip(r, golems[1])
	assert(Logic.bonuses(r).extract == Companions.FamilyCap, "0.8 x 6.5 is capped at +200 percent")
	-- merged pet gives more than the three it replaced
	local s = profile()
	local ids = give(s, "ore_golem", 3)
	s.evolutionRank = 1
	Logic.equip(s, ids[1])
	Logic.equip(s, ids[2])
	Logic.equip(s, ids[3])
	local before = Logic.bonuses(s).extract
	assert(Logic.merge(s, ids[1]))
	Logic.equip(s, ids[1])
	assert(Logic.bonuses(s).extract >= 0.20 * 1.6 - 1e-12 and before > 0)
end

tests["equipBest ranks by level-scaled bonus"] = function()
	local p = profile()
	local weak = give(p, "ore_golem", 1) -- 0.20 extract at level 1
	local strong = give(p, "soot_mole", 1, 5) -- 0.04 x 6.5 = 0.26
	Logic.equipBest(p)
	assert(p.equipped[1] == strong[1] and p.equipped[2] == weak[1], "a maxed common beats a base legendary here")
end

tests["mergeAll merges everything it can, cascading through levels"] = function()
	local p = profile()
	local moles = give(p, "soot_mole", 9)
	local others = give(p, "bellows_bat", 2)
	local ok, merged = Logic.mergeAll(p)
	assert(ok and #merged >= 1)
	assert(count(p) == 1 + 2, "nine moles cascade into one level-3 mole; the two bats are left")
	local survivor
	for _, pet in p.pets do
		if pet.k == "soot_mole" then survivor = pet end
	end
	assert(survivor and Logic.level(survivor) == 3)
	for _, id in others do
		assert(p.pets[id] ~= nil and Logic.level(p.pets[id]) == 1)
	end
	assert(select(2, Logic.mergeAll(p)) == "nothing to merge", "second run finds nothing")
	assert(moles[1] ~= nil)
	-- 27 copies climb to level 4
	local q = profile()
	give(q, "soot_mole", 27)
	assert(Logic.mergeAll(q))
	assert(count(q) == 1)
	for _, pet in q.pets do
		assert(Logic.level(pet) == 4)
	end
	-- 81 copies reach the cap and stop there
	local r = profile()
	give(r, "soot_mole", 81)
	assert(Logic.mergeAll(r))
	assert(count(r) == 1)
	for _, pet in r.pets do
		assert(Logic.level(pet) == Companions.MaxLevel)
	end
	-- 82 leaves the cap pet plus a spare
	local s = profile()
	give(s, "soot_mole", 82)
	assert(Logic.mergeAll(s) and count(s) == 2)
end

tests["mergeAll keeps equipped pets as targets and leaves no dangling equips"] = function()
	local p = profile()
	local ids = give(p, "soot_mole", 6)
	assert(Logic.equip(p, ids[4]) and Logic.equip(p, ids[6]))
	assert(Logic.mergeAll(p))
	assert(count(p) == 2)
	for _, id in p.equipped do
		assert(p.pets[id] ~= nil, "equipped id " .. id .. " no longer exists")
	end
	assert(#p.equipped >= 1, "an equipped pet survives as a merge target")
	Logic.ensure(p)
	for _, pet in p.pets do
		assert(Logic.level(pet) == 2)
	end
end

tests["pet ids are never reused after a merge"] = function()
	local p = profile()
	local ids = give(p, "soot_mole", 3)
	assert(Logic.merge(p, ids[1]))
	local later = give(p, "soot_mole", 1)[1]
	for _, id in ids do
		assert(later ~= id, "id reused after merge")
	end
end

tests["player-level merge wrappers save only on success"] = function()
	local Service = require(Services:WaitForChild("CompanionService"):Clone())
	local data = profile()
	local dirty = 0
	local player = { UserId = 1 }
	Service._inject({
		getProfile = function(who)
			return if who == player then data else nil
		end,
		markDirty = function()
			dirty += 1
		end,
	})
	local ids = give(data, "soot_mole", 3)
	local bad, why = Service.merge({ UserId = 2 }, ids[1])
	assert(not bad and why == "profile not loaded" and dirty == 0)
	bad, why = Service.merge(player, "nope")
	assert(not bad and why == "not owned" and dirty == 0)
	local ok, result = Service.merge(player, ids[1])
	assert(ok and Logic.level(result.pet) == 2 and dirty == 1)
	bad, why = Service.mergeAll(player)
	assert(not bad and why == "nothing to merge" and dirty == 1)
	give(data, "soot_mole", 8, 2)
	ok = Service.mergeAll(player)
	assert(ok and dirty == 2)
	assert(Service.bonuses(player).extract == 0, "nothing equipped")
	assert(Service.equip(player, ids[1]))
	local expected = 0.04 * Companions.levelMultiplier(Logic.level(data.pets[ids[1]]))
	assert(math.abs(Service.bonuses(player).extract - expected) < 1e-12)
end

return tests
