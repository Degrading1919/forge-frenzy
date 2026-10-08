-- Workshop economy rules (v2): build pads, ore line / forge refit, display income and the
-- collector bank, and forge station configuration. Pure; runs in Studio and under Lune.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local Balance = require(Shared.Config.Balance)
local Materials = require(Shared.Config.Materials)
local BuildPads = require(Shared.Config.BuildPads)
local Eggs = require(Shared.Config.Eggs)

local function near(a: number, b: number, eps: number, label: string)
	assert(math.abs(a - b) <= eps, `{label}: expected {b}, got {a}`)
end

local function weapon(id: string, v: number, m: number?): any
	return { id = id, m = m or 1, c = 1, q = 1, r = 1, d = "x", v = v, ts = 0 }
end

local tests = {}

-- Pads ---------------------------------------------------------------------------------------------

tests["pad table is consistent: unique ids, real prerequisites, positive finite prices"] = function()
	local seen = {}
	for _, pad in BuildPads.List do
		assert(not seen[pad.id], "duplicate " .. pad.id)
		seen[pad.id] = true
		assert(BuildPads.ById[pad.id] == pad)
		assert(pad.cost > 0 and pad.cost == pad.cost and pad.cost < math.huge and pad.cost <= Balance.maxCoins, pad.id .. " cost")
		assert(pad.tier >= 1 and pad.tier <= #Materials and Materials[pad.costTier] ~= nil, pad.id .. " tier")
		assert(table.find({ "podiums", "line", "forge", "decor" }, pad.kind), pad.id .. " kind")
		if pad.requires then
			local required = BuildPads.ById[pad.requires]
			assert(required and required.kind == pad.kind, pad.id .. " prerequisite must exist and be the same kind")
			assert(required.tier <= pad.tier, pad.id .. " prerequisite appears later than the pad")
		end
	end
	assert(BuildPads.MaxLines == 3 and BuildPads.MaxForges == 3)
	for _, egg in Eggs.List do
		assert(egg.coinCost > 0 and egg.coinCost == egg.coinCost and egg.coinCost < math.huge, egg.id .. " price")
	end
end

tests["pad availability follows tier and prerequisite"] = function()
	local line2, line3, podiums2 = BuildPads.ById.line_2, BuildPads.ById.line_3, BuildPads.ById.podiums_2
	assert(not BuildPads.available(line2, {}, line2.tier - 1), "tier not reached")
	assert(BuildPads.available(line2, {}, line2.tier))
	assert(not BuildPads.available(line2, { line_2 = true }, 32), "already built pads are not offered")
	assert(not BuildPads.available(line3, {}, 32), "line 3 needs line 2")
	assert(BuildPads.available(line3, { line_2 = true }, line3.tier))
	assert(not BuildPads.available(podiums2, { line_2 = true }, 32), "a different pad is not a prerequisite")
	assert(BuildPads.available(podiums2, { podiums_1 = true }, podiums2.tier))
	assert(not BuildPads.available(podiums2, nil, 32), "nil pads: prerequisite unmet")
end

tests["buying a pad charges its price and builds permanently"] = function()
	local p = Economy.newProfile()
	local pad = BuildPads.ById.podiums_1
	local ok, err = Economy.buyPad(p, "nope")
	assert(not ok and err == "InvalidPad")
	ok, err = Economy.buyPad(p, 5 :: any)
	assert(not ok and err == "InvalidPad")
	p.coins = pad.cost * 10
	ok, err = Economy.buyPad(p, pad.id)
	assert(not ok and err == "PadLocked", "Tin not unlocked yet")
	assert(p.coins == pad.cost * 10 and not p.pads[pad.id], "a refused buy changes nothing")
	p.unlockedTier = pad.tier
	p.coins = pad.cost - 1
	ok, err = Economy.buyPad(p, pad.id)
	assert(not ok and err == "NotEnoughCoins" and not p.pads[pad.id])
	p.coins = pad.cost
	ok, err = Economy.buyPad(p, pad.id)
	assert(ok and err == pad and p.pads.podiums_1 == true and p.coins == 0, "price charged exactly")
	assert(Economy.showcaseSlots(p) == 4)
	p.coins = 1e12
	ok, err = Economy.buyPad(p, pad.id)
	assert(not ok and err == "AlreadyBuilt" and p.coins == 1e12, "no double charge")
	ok, err = Economy.buyPad(p, "podiums_3")
	assert(not ok and err == "PadLocked", "podiums_3 needs podiums_2")
end

tests["line and forge pads grow the workshop and keep existing settings"] = function()
	local p = Economy.newProfile()
	p.unlockedTier = 9
	p.lines[1].m = 3
	p.stations[1].m = 3
	p.stations[1].c = 2
	p.stations[1].keep = 6
	p.coins = 1e12
	assert(Economy.lineCount(p) == 1 and Economy.forgeCount(p) == 1)
	assert(Economy.buyPad(p, "line_2"))
	assert(#p.lines == 2 and Economy.lineCount(p) == 2)
	assert(p.lines[1].m == 3, "line 1 kept its material")
	assert(p.lines[2].m == 9 and p.lines[2].ore == 0, "new line starts on the best unlocked material")
	assert(Economy.buyPad(p, "forge_2"))
	assert(#p.stations == 2 and p.stations[1].c == 2 and p.stations[1].keep == 6 and p.stations[1].m == 3, "station 1 untouched")
	assert(p.stations[2].m == 9 and p.stations[2].c == Economy.STARTER_CLASS and p.stations[2].keep == 4)
	assert(Economy.buyPad(p, "line_3") and Economy.buyPad(p, "forge_3"))
	assert(#p.lines == 3 and #p.stations == 3)
	-- decor pads change no counts
	assert(Economy.buyPad(p, "decor_banners"))
	assert(#p.lines == 3 and #p.stations == 3 and Economy.showcaseSlots(p) == 2)
	-- the podium pads add two slots each, up to eight
	p.unlockedTier = 12
	assert(Economy.buyPad(p, "podiums_1") and Economy.buyPad(p, "podiums_2") and Economy.buyPad(p, "podiums_3"))
	assert(Economy.showcaseSlots(p) == Balance.inventory.showcaseSlots)
end

tests["pads are permanent: reset fields refit to the kept pads and highestTierEver keeps access"] = function()
	local p = Economy.newProfile()
	p.pads = { line_2 = true, forge_2 = true, podiums_1 = true }
	p.unlockedTier = 9
	Economy.reconcile(p)
	assert(#p.lines == 2 and #p.stations == 2)
	-- simulate the resets an evolution performs
	local fresh = Economy.newProfile()
	p.unlockedTier = 1
	p.lines = {}
	p.stations = {}
	p.coins = 0
	p.bank = 0
	p.ingots = fresh.ingots
	Economy.reconcile(p)
	assert(#p.lines == 2 and #p.stations == 2, "ore lines and forges re-fit to the pads that were kept")
	assert(p.lines[1].m == 1 and p.lines[2].m == 1 and p.stations[2].m == 1, "all on Copper after the reset")
	assert(p.pads.line_2 and p.pads.forge_2 and p.pads.podiums_1, "pads survive")
	assert(Economy.showcaseSlots(p) == 4)
	-- after the reset the tier gate uses the best tier ever reached
	p.highestTierEver = 9
	p.coins = BuildPads.ById.line_3.cost
	assert(Economy.buyPad(p, "line_3"), "evolved players can still buy pads for tiers they once reached")
	assert(#p.lines == 3)
	-- unknown / non-true pad flags are scrubbed on load
	p.pads.ghost = true
	p.pads.forge_3 = "yes" :: any
	Economy.reconcile(p)
	assert(p.pads.ghost == nil and p.pads.forge_3 == nil)
end

tests["fewer pads than lines/stations shrinks the workshop safely"] = function()
	local p = Economy.newProfile()
	p.lines = { { m = 1, ore = 0, po = 0, ps = 0 }, { m = 1, ore = 0, po = 0, ps = 0 }, { m = 1, ore = 0, po = 0, ps = 0 } }
	p.stations = { { m = 1, c = 4, keep = 4 }, { m = 1, c = 4, keep = 4 } }
	Economy.reconcile(p)
	assert(#p.lines == 1 and #p.stations == 1, "no pad, no extra line or forge")
end

-- Display income ---------------------------------------------------------------------------------

tests["display income is a fraction of value and capped at the current tier's best weapon"] = function()
	local p = Economy.newProfile()
	local small = weapon("s", 1000)
	near(Economy.displayIncome(p, small), 1000 * Balance.display.incomePerSecond, 1e-12, "plain income")
	-- a weapon worth far more than anything Copper can forge only earns up to the cap
	local trophy = weapon("t", 1e12, 20)
	local cap = ForgeMath.maxValue(1) * Balance.display.incomePerSecond
	near(Economy.displayIncome(p, trophy), cap, 1e-9, "tier 1 cap")
	p.unlockedTier = 5
	near(Economy.displayIncome(p, trophy), ForgeMath.maxValue(5) * Balance.display.incomePerSecond, 1e-6, "cap follows the unlocked tier")
	near(Economy.displayIncome(p, trophy, 2), ForgeMath.maxValue(5, 2) * Balance.display.incomePerSecond, 1e-6, "cash multiplier raises the cap")
	assert(Economy.displayIncome(p, small, 3) == 1000 * Balance.display.incomePerSecond, "income uses the stored value; the multiplier only lifts the cap")
	assert(Balance.display.incomePerSecond > 0 and Balance.display.bankCapSec == 3600)
end

tests["only built podiums earn, and skipped (carried) weapons earn nothing"] = function()
	local p = Economy.newProfile()
	p.unlockedTier = 32 -- far above these values, so the tier cap is out of the way
	p.weapons.a = weapon("a", 10000)
	p.weapons.b = weapon("b", 20000)
	p.weapons.c = weapon("c", 40000)
	p.showcase[1], p.showcase[2], p.showcase[3] = "a", "b", "c" -- slot 3 is not built (raw write)
	near(Economy.displayIncomeTotal(p), (10000 + 20000) * Balance.display.incomePerSecond, 1e-9, "unbuilt podium earns nothing")
	near(Economy.displayIncomeTotal(p, nil, { b = true }), 10000 * Balance.display.incomePerSecond, 1e-9, "carried weapon skipped")
	p.pads.podiums_1 = true
	near(Economy.displayIncomeTotal(p), (10000 + 20000 + 40000) * Balance.display.incomePerSecond, 1e-9, "built podium earns")
	assert(Economy.displayIncomeTotal(Economy.newProfile()) == 0)
end

tests["the collector fills over time, caps at an hour and never loses cash"] = function()
	local p = Economy.newProfile()
	p.unlockedTier = 32
	p.weapons.a = weapon("a", 100000)
	assert(Economy.setShowcase(p, 1, "a"))
	local perSec = Economy.displayIncomeTotal(p)
	near(perSec, 100000 * Balance.display.incomePerSecond, 1e-9, "100k * rate")
	local added = Economy.accrueDisplay(p, 10)
	near(added, perSec * 10, 1e-9, "10 seconds")
	near(p.bank, perSec * 10, 1e-9, "bank")
	near(Economy.accrueDisplay(p, 10, nil, 0.5), perSec * 5, 1e-9, "offline efficiency halves it")
	assert(Economy.accrueDisplay(p, -5) == 0 and Economy.accrueDisplay(p, 0 / 0) == 0 and Economy.accrueDisplay(p, 0) == 0)
	-- days of idling stops at exactly one hour of income
	Economy.accrueDisplay(p, 3 * 86400)
	near(p.bank, perSec * Balance.display.bankCapSec, 1e-6, "bank cap")
	local full = p.bank
	assert(Economy.accrueDisplay(p, 3600) == 0 and p.bank == full, "full collector accrues nothing")
	-- a bank above the cap (older save, richer weapon sold since) is never reduced
	p.bank = full * 3
	assert(Economy.accrueDisplay(p, 3600) == 0 and p.bank == full * 3, "over-cap bank is preserved")
	-- empty podiums earn nothing
	local empty = Economy.newProfile()
	assert(Economy.accrueDisplay(empty, 1000) == 0 and empty.bank == 0)
end

tests["collecting pays the bank once, floors it and adds lifetime earnings"] = function()
	local p = Economy.newProfile()
	p.bank = 0.9
	local ok, err = Economy.collectBank(p)
	assert(not ok and err == "NothingToCollect" and p.bank == 0.9, "less than a whole coin is kept")
	p.bank = 1234.7
	p.coins = 50
	local lifetime = p.lifetimeCoins
	local paid
	ok, paid = Economy.collectBank(p)
	assert(ok and paid == 1234 and p.coins == 50 + 1234 and p.bank == 0)
	assert(p.lifetimeCoins == lifetime + 1234, "collected cash counts as earned")
	ok, err = Economy.collectBank(p)
	assert(not ok and err == "NothingToCollect" and p.coins == 1284, "second collect pays nothing")
	p.coins = Balance.maxCoins - 1
	p.bank = 1e6
	assert(Economy.collectBank(p) and p.coins == Balance.maxCoins)
end

-- Stations ---------------------------------------------------------------------------------------

tests["configureStation validates every input and changes nothing on failure"] = function()
	local p = Economy.newProfile()
	p.unlockedTier = 3
	local before = { m = p.stations[1].m, c = p.stations[1].c, keep = p.stations[1].keep }
	local function unchanged()
		local s = p.stations[1]
		assert(s.m == before.m and s.c == before.c and s.keep == before.keep, "failed configure mutated the station")
	end
	local cases = {
		{ { 2, 3, 1, 4 }, "InvalidStation" }, -- station 2 not built
		{ { 0, 3, 1, 4 }, "InvalidStation" },
		{ { "1", 3, 1, 4 }, "InvalidStation" },
		{ { 1, 0, 1, 4 }, "InvalidMaterial" },
		{ { 1, 33, 1, 4 }, "InvalidMaterial" },
		{ { 1, 2.5, 1, 4 }, "InvalidMaterial" },
		{ { 1, "2", 1, 4 }, "InvalidMaterial" },
		{ { 1, 4, 1, 4 }, "MaterialLocked" },
		{ { 1, 3, 0, 4 }, "InvalidClass" },
		{ { 1, 3, 6, 4 }, "InvalidClass" },
		{ { 1, 3, 1.5, 4 }, "InvalidClass" },
		{ { 1, 3, 1, 0 }, "InvalidSetting" },
		{ { 1, 3, 1, 8 }, "InvalidSetting" },
		{ { 1, 3, 1, 2.5 }, "InvalidSetting" },
		{ { 1, 3, 1, "4" }, "InvalidSetting" },
		{ { 1, 3, 1, nil }, "InvalidSetting" },
	}
	for i, case in cases do
		local a = case[1]
		local ok, err = Economy.configureStation(p, a[1], a[2], a[3], a[4])
		assert(not ok and err == case[2], `case {i}: expected {case[2]}, got {tostring(err)}`)
		unchanged()
	end
	for keep = 1, 7 do
		local ok, station = Economy.configureStation(p, 1, 3, 2, keep)
		assert(ok and station == p.stations[1] and station.m == 3 and station.c == 2 and station.keep == keep)
	end
end

tests["each forge station keeps its own recipe"] = function()
	local p = Economy.newProfile()
	p.unlockedTier = 6
	p.pads.forge_2 = true
	Economy.reconcile(p)
	assert(Economy.configureStation(p, 1, 2, 3, 1))
	assert(Economy.configureStation(p, 2, 6, 2, 7))
	assert(p.stations[1].m == 2 and p.stations[1].c == 3 and p.stations[1].keep == 1)
	assert(p.stations[2].m == 6 and p.stations[2].c == 2 and p.stations[2].keep == 7)
	p.ingots[2], p.ingots[6] = 3, 5
	assert(Economy.canForge(p, p.stations[1].m, p.stations[1].c), "3 Tin ingots make an Axe")
	assert(Economy.canForge(p, p.stations[2].m, p.stations[2].c), "5 Silver ingots make a Greatsword")
	p.ingots[6] = 4
	local ok, err = Economy.canForge(p, p.stations[2].m, p.stations[2].c)
	assert(not ok and err == "NoMaterial", "Greatsword needs five")
end

return tests
