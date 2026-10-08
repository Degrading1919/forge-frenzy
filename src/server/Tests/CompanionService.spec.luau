-- Companion inventory, hatching, equipping and bonus tests. Pure: no DataStore or remotes.
-- Player-level tests use a cloned module so they never disturb the running service.

local Services = script.Parent.Parent:WaitForChild("Services")
local Config = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config")
local Companions = require(Config:WaitForChild("Companions"))
local Eggs = require(Config:WaitForChild("Eggs"))
local Logic = require(Services:WaitForChild("CompanionService")).Logic

local function fresh()
	return require(Services:WaitForChild("CompanionService"):Clone())
end

local function profile(overrides: { [string]: any }?)
	local p = { coins = 0, unlockedTier = 1, evolutionRank = 0 }
	for k, v in overrides or {} do
		p[k] = v
	end
	return p
end

local function opts(seed: number?, multi: boolean?)
	return { rng = Random.new(seed or 1), now = 1000, multiHatch = multi == true }
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function copy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = copy(v)
	end
	return out
end

local tests = {}

tests["legacy companion serials preserve owned pets and runtime counters cannot collide"] = function()
	local kind = Eggs.List[1].kinds[1].kind
	local original = { id = "p9", k = kind, ts = 1 }
	local p = profile({ pets = { p9 = original }, equipped = { "p9" } })
	Logic.ensure(p)
	assert(p.petSerial == 9 and p.pets.p9 == original and p.equipped[1] == "p9")
	local ok, pet = Logic.grantKind(p, kind, { now = 1000 })
	assert(ok and pet.id == "p10" and p.pets.p9 == original)
	p.petSerial = 8 -- missing/stale counters are recovered before every hatch/grant
	local ok2, pet2 = Logic.grantKind(p, kind, { now = 1001 })
	assert(ok2 and pet2.id == "p11" and p.pets.p9 == original and p.pets.p10 == pet)
	p.petSerial = math.huge
	Logic.ensure(p)
	assert(p.petSerial == 11, "nonfinite counter must recover from existing IDs")
end

tests["every egg's odds sum to 100 and reference earnable kinds"] = function()
	assert(#Eggs.List >= 1, "no eggs")
	for _, egg in Eggs.List do
		local odds = Eggs.odds(egg.id)
		local total = 0
		for _, row in odds do
			total += row.percent
			local kind = Companions.ById[row.kind]
			assert(kind and not kind.premium, egg.id .. " has premium or unknown kind " .. row.kind)
		end
		assert(math.abs(total - 100) < 1e-9, egg.id .. " odds sum " .. total)
	end
end

tests["egg tiers and costs increase together"] = function()
	for i = 2, #Eggs.List do
		assert(Eggs.List[i].unlockTier > Eggs.List[i - 1].unlockTier, "unlock tiers not increasing")
		assert(Eggs.List[i].coinCost > Eggs.List[i - 1].coinCost, "costs not increasing")
	end
end

tests["seeded hatch distribution matches weights"] = function()
	local egg = Eggs.ById.hearth
	local counts = {}
	local rng = Random.new(12345)
	local n = 200000
	for _ = 1, n do
		local kind = Logic.pickKind(egg, rng:NextNumber())
		counts[kind] = (counts[kind] or 0) + 1
	end
	for _, row in Eggs.odds("hearth") do
		local expected = row.percent / 100 * n
		local got = counts[row.kind] or 0
		local sd = math.sqrt(n * (row.percent / 100) * (1 - row.percent / 100))
		assert(math.abs(got - expected) < 5 * sd, `{row.kind}: got {got}, expected {expected}`)
	end
end

tests["pickKind covers the full roll range"] = function()
	local egg = Eggs.ById.hearth
	assert(Logic.pickKind(egg, 0) == egg.kinds[1].kind)
	assert(Logic.pickKind(egg, 0.999999999) == egg.kinds[#egg.kinds].kind)
end

tests["hatch charges exactly the egg cost and adds a pet"] = function()
	local p = profile({ coins = 5000, unlockedTier = 3 })
	local ok, pets = Logic.hatch(p, "hearth", 1, opts())
	assert(ok, pets)
	assert(#pets == 1 and p.pets[pets[1].id] ~= nil)
	assert(p.coins == 5000 - Eggs.ById.hearth.coinCost)
end

tests["failed hatches change nothing"] = function()
	local cases = {
		{ profile({ coins = 100, unlockedTier = 3 }), "hearth", 1, false }, -- too poor
		{ profile({ coins = 1e9, unlockedTier = 2 }), "hearth", 1, false }, -- locked
		{ profile({ coins = 1e9, unlockedTier = 3 }), "hearth", 3, false }, -- no multi pass
		{ profile({ coins = 1e9, unlockedTier = 3 }), "hearth", 2, true }, -- bad count
		{ profile({ coins = 1e9, unlockedTier = 3 }), "nope", 1, false }, -- unknown egg
		{ profile({ coins = 0 / 0, unlockedTier = 3 }), "hearth", 1, false }, -- NaN coins
		{ profile({ coins = "9999", unlockedTier = 3 }), "hearth", 1, false }, -- bad type
		{ profile({ coins = 1e9, unlockedTier = 3 }), { "hearth" }, 1, false }, -- bad payload
	}
	for i, case in cases do
		Logic.ensure(case[1])
		local before = copy(case[1])
		local ok = Logic.hatch(case[1], case[2], case[3], opts(1, case[4]))
		assert(not ok, "case " .. i .. " should fail")
		-- NaN ~= NaN, so compare everything except coins for the NaN case
		if i ~= 6 then
			assert(deepEqual(before, case[1]), "case " .. i .. " mutated the profile")
		end
	end
end

tests["evolved players keep egg access through highestTierEver"] = function()
	local p = profile({ coins = 5000, unlockedTier = 1, highestTierEver = 9 })
	assert(Logic.hatch(p, "ember", 1, opts()) == false) -- too poor for ember, but not locked
	local ok, why = Logic.hatch(p, "hearth", 1, opts())
	assert(ok, why)
end

tests["multi-hatch opens 3 or 5 and charges each egg"] = function()
	local p = profile({ coins = 1e6, unlockedTier = 3 })
	local ok, pets = Logic.hatch(p, "hearth", 5, opts(7, true))
	assert(ok and #pets == 5)
	assert(p.coins == 1e6 - 5 * Eggs.ById.hearth.coinCost)
	local ok3, pets3 = Logic.hatch(p, "hearth", 3, opts(8, true))
	assert(ok3 and #pets3 == 3)
end

tests["inventory cap blocks hatching"] = function()
	local p = profile({ coins = 1e12, unlockedTier = 3 })
	for _ = 1, Companions.InventoryCapacity do
		assert(Logic.hatch(p, "hearth", 1, opts()))
	end
	local ok, why = Logic.hatch(p, "hearth", 1, opts())
	assert(not ok and why == "inventory full")
end

tests["pet ids are unique and never reused after release"] = function()
	local p = profile({ coins = 1e9, unlockedTier = 3 })
	local _, a = Logic.hatch(p, "hearth", 1, opts())
	assert(Logic.release(p, a[1].id))
	local _, b = Logic.hatch(p, "hearth", 1, opts())
	assert(a[1].id ~= b[1].id)
end

tests["two slots by default, third after first evolution"] = function()
	local p = profile({ coins = 1e9, unlockedTier = 3 })
	local _, pets = Logic.hatch(p, "hearth", 1, opts())
	local _, more = Logic.hatch(p, "hearth", 1, opts(2))
	local _, last = Logic.hatch(p, "hearth", 1, opts(3))
	assert(Logic.equip(p, pets[1].id))
	assert(Logic.equip(p, more[1].id))
	local ok, why = Logic.equip(p, last[1].id)
	assert(not ok and why == "no free slot")
	p.evolutionRank = 1
	assert(Logic.equip(p, last[1].id))
	assert(#p.equipped == 3 and p.petSlots == 3)
end

tests["equip rejects unknown, duplicate and non-string ids"] = function()
	local p = profile({ coins = 1e9, unlockedTier = 3 })
	local _, pets = Logic.hatch(p, "hearth", 1, opts())
	assert(not Logic.equip(p, "p999"))
	assert(not Logic.equip(p, 5))
	assert(Logic.equip(p, pets[1].id))
	assert(not Logic.equip(p, pets[1].id))
	assert(#p.equipped == 1)
end

tests["release unequips and premium companions cannot be released"] = function()
	local p = profile({ coins = 1e9, unlockedTier = 3 })
	local _, pets = Logic.hatch(p, "hearth", 1, opts())
	Logic.equip(p, pets[1].id)
	assert(Logic.release(p, pets[1].id))
	assert(#p.equipped == 0 and p.pets[pets[1].id] == nil)
	local _, dragon = Logic.grantKind(p, "golden_forge_dragon", { unique = true })
	local ok = Logic.release(p, dragon.id)
	assert(not ok and p.pets[dragon.id] ~= nil)
end

tests["unique grants are idempotent"] = function()
	local p = profile()
	local _, a = Logic.grantKind(p, "golden_forge_dragon", { unique = true })
	local _, b = Logic.grantKind(p, "golden_forge_dragon", { unique = true })
	assert(a.id == b.id and Logic.petCount(p) == 1)
end

tests["bonuses sum per family and cap at +200%"] = function()
	local p = profile()
	for _ = 1, 3 do
		Logic.grantKind(p, "tempest_golem") -- +80% extract each
	end
	p.evolutionRank = 1
	Logic.equipBest(p)
	local b = Logic.bonuses(p)
	assert(b.extract == Companions.FamilyCap, "extract " .. b.extract)
	assert(b.smelt == 0 and b.prep == 0 and b.storage == 0)

	local q = profile()
	Logic.grantKind(q, "soot_mole")
	Logic.grantKind(q, "golden_forge_dragon")
	Logic.equipBest(q)
	local c = Logic.bonuses(q)
	assert(math.abs(c.extract - 1.04) < 1e-9 and math.abs(c.smelt - 0.2) < 1e-9)
end

tests["unequipped companions give nothing"] = function()
	local p = profile()
	Logic.grantKind(p, "ore_golem")
	local b = Logic.bonuses(p)
	assert(b.extract == 0)
end

tests["ensure drops dangling and duplicate equips"] = function()
	local p = profile({ pets = { p1 = { id = "p1", k = "soot_mole", ts = 0 } }, equipped = { "p1", "p1", "ghost" }, petSerial = 1 })
	Logic.ensure(p)
	assert(#p.equipped == 1 and p.equipped[1] == "p1")
end

tests["dev grants are stripped outside Studio"] = function()
	local p = profile()
	local _, dev = Logic.grantKind(p, "golden_forge_dragon", { unique = true, src = "dev" })
	local _, real = Logic.grantKind(p, "soot_mole")
	Logic.equip(p, dev.id)
	assert(Logic.stripDevGrants(p) == 1)
	assert(p.pets[dev.id] == nil and p.pets[real.id] ~= nil and #p.equipped == 0)
end

tests["player hatch is rate limited and needs a loaded profile"] = function()
	local Service = fresh()
	local data = profile({ coins = 1e9, unlockedTier = 3 })
	local t = 0
	local player = { UserId = 1 }
	Service._inject({
		getProfile = function(pl)
			return if pl == player then data else nil
		end,
		clock = function()
			return t
		end,
		now = function()
			return 1000
		end,
		rng = Random.new(5),
	})
	assert(Service.hatch(player, "hearth", 1))
	local ok, why = Service.hatch(player, "hearth", 1)
	assert(not ok and why == "hatching too fast")
	t += Companions.HatchCooldownSec
	assert(Service.hatch(player, "hearth", 1))
	assert(not Service.hatch({ UserId = 2 }, "hearth", 1))
end

tests["player multi-hatch checks the MultiHatch pass"] = function()
	local Service = fresh()
	local data = profile({ coins = 1e9, unlockedTier = 3 })
	local owns = false
	local t = 0
	Service._inject({
		paidRandomAllowed = function() return true end,
		getProfile = function()
			return data
		end,
		ownsPass = function(_, key)
			return key == "MultiHatch" and owns
		end,
		clock = function()
			t += 10
			return t
		end,
		rng = Random.new(9),
	})
	assert(not Service.hatch({}, "hearth", 5))
	owns = true
	local ok, pets = Service.hatch({}, "hearth", 5)
	assert(ok and #pets == 5)
end

tests["restricted multi-hatch cannot spend coins but free single hatch works"] = function()
	local Service = fresh()
	local data = profile({ coins = 1e9, unlockedTier = 3 })
	Service._inject({ getProfile = function() return data end, ownsPass = function() return true end,
		paidRandomAllowed = function() return false end, rng = Random.new(9) })
	local before = data.coins
	local ok, why = Service.hatch({}, "hearth", 5)
	assert(not ok and why == "PaidRandomRestricted" and data.coins == before)
	assert(Service.hatch({}, "hearth", 1))
end

return tests
