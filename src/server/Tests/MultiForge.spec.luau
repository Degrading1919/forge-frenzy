-- Forge throughput, paid policy, and stale-session regression tests. No real APIs/purchases.
local Services = script.Parent.Parent.Services
local Forge = require(Services.ForgeService)
local Data = require(Services.DataService)
local Production = require(Services.ProductionService)
local Shared = game:GetService("ReplicatedStorage").Shared
local Economy = require(Shared.Economy)
local ForgeMath = require(Shared.ForgeMath)
local Balance = require(Shared.Config.Balance)
local Evolution = require(Services.EvolutionService)
local Players = game:GetService("Players")

local function fixture(fn)
	local player = { UserId = -7351, Name = "BatchSmith", Parent = Players }
	local p = Economy.newProfile()
	p.ingots[1] = 10
	p.settings = { autoKeepFrom = 0 } -- tests that inspect ownership explicitly keep auto extras
	local state = { now = 1000, allowed = true, owned = { MultiForge = true }, timers = {} }
	local saved = { clock = Forge.clock, delay = Forge.delay, rng = Forge.rng, service = Production._service }
	Forge.clock = function() return state.now end
	Forge.delay = function(_, callback) table.insert(state.timers, callback) end
	Forge.rng = Random.new(1948)
	Production._service = function(name)
		if name == "MonetizationService" then
			return {
				owns = function(_, key) return state.owned[key] == true end,
				canOfferPaidRandom = function()
					if state.policyHook then state.policyHook() end
					return state.allowed
				end,
			}
		end
		return nil
	end
	Data._setForTest(player, p)
	local ok, err = pcall(fn, player, p, state)
	Forge.clock, Forge.delay, Forge.rng = saved.clock, saved.delay, saved.rng
	Production._service = saved.service
	Data._setForTest(player, nil)
	if not ok then error(err, 0) end
end

local tests = {}

tests["MultiForge preserves main reveal, rolls independently, and counts every forge"] = function()
	fixture(function(player, p, state)
		local expected = Economy.newProfile()
		expected.ingots[1] = 10
		local rng = Random.new(1948)
		local _, first = Economy.completeForge(expected, 1, 3, 1.5, rng, 0)
		local _, second = Economy.completeForge(expected, 1, 3, 1.5, rng, 0)
		local event
		local connection = Forge.completed.Event:Connect(function(_, weapon, luck, auto, strikes, extras)
			event = { weapon = weapon, luck = luck, auto = auto, strikes = strikes, extras = extras }
		end)
		assert(Forge.begin(player, 3, 1, "free"))
		Forge._completeNow(player)
		task.wait()
		connection:Disconnect()
		assert(p.pending.id == "w1" and p.weapons.w2 ~= nil and p.weapons.w1 == nil, "primary must stay pending, extra must be kept")
		assert(p.ingots[1] == 8 and p.weaponsForged == 2, "one charge/counter increment per roll")
		assert(p.pending.v == first.v and p.pending.r == first.r and p.weapons.w2.v == second.v and p.weapons.w2.r == second.r, "must consume independent RNG draws")
		assert(event and event.weapon.id == p.pending.id and event.weapon.v == p.pending.v and #event.extras == 1 and event.extras[1].id == p.weapons.w2.id and event.extras[1].v == p.weapons.w2.v and event.luck == 1.5)
		assert(Evolution.Logic.progress(p).forged == 2, "extra rolls must count toward evolution")
		Forge._completeNow(player)
		assert(p.weaponsForged == 2 and p.ingots[1] == 8, "completion replay duplicated rewards")
		local totalValue = p.pending.v + p.weapons.w2.v
		assert(Forge.resolve(player, "sell"))
		assert(Forge.sellWeapons(player, { "w2", "w2" }))
		assert(not Forge.resolve(player, "sell") and not Forge.sellKept(player, "w2"))
		assert(p.coins == totalValue and p.weaponsSold == 2, "batch sales must be idempotent")
	end)
end

tests["MultiForge manual uses one server strike performance for both independent rolls"] = function()
	fixture(function(player, p, state)
		assert(Forge.begin(player, 1, 1, "manual"))
		local session = Forge.session(player)
		for i = 0, 29 do
			state.now = session.windowStart + i * 0.2
			assert(Forge.strike(player, session.id))
		end
		local luck
		local connection = Forge.completed.Event:Connect(function(_, _, value) luck = value end)
		Forge._completeNow(player)
		task.wait()
		connection:Disconnect()
		assert(luck == 2.5 and p.weaponsForged == 2 and p.ingots[1] == 8)
	end)
end

tests["MultiForge falls back to one when only one ingot or inventory slot remains"] = function()
	fixture(function(player, p)
		p.ingots[1] = 1
		assert(Forge.begin(player, 1, 1, "free"))
		Forge._completeNow(player)
		assert(p.weaponsForged == 1 and p.ingots[1] == 0)
	end)
	fixture(function(player, p)
		for i = 1, Balance.inventory.maxWeapons - 1 do
			p.weapons["old" .. i] = { id = "old" .. i, v = 12 }
		end
		assert(Forge.begin(player, 1, 1, "free"))
		Forge._completeNow(player)
		assert(p.weaponsForged == 1 and p.ingots[1] == 9)
		assert(Economy.weaponCount(p) + (if p.pending then 1 else 0) == Balance.inventory.maxWeapons)
	end)
end

tests["MultiForge filters each result and preserves prior pending weapons"] = function()
	fixture(function(player, p, state)
		state.owned.CollectionMagnet = true
		p.pending = { id = "previous", m = 1, c = 1, q = 1, r = 6, d = "x", v = 100, ts = 0 }
		p.settings = { autoSellBelow = 7 }
		assert(Forge.begin(player, 1, 1, "free"))
		Forge._completeNow(player)
		assert(p.pending == nil and p.weapons.previous ~= nil and Economy.weaponCount(p) == 1)
		assert(p.weaponsForged == 2 and p.weaponsSold == 2 and p.coins > 0 and p.ingots[1] == 8)
	end)
end

tests["saved manual auto-sell preferences are ignored without CollectionMagnet"] = function()
	fixture(function(player, p)
		p.settings = { autoSellBelow = 7 }
		assert(Forge.begin(player, 1, 1, "manual"))
		Forge._completeNow(player)
		assert(p.pending ~= nil and p.weapons.w2 ~= nil and p.weaponsSold == 0 and p.coins == 0)
		assert(p.settings.autoSellBelow == 7, "unowned preference must be preserved for ownership restoration")
	end)
	fixture(function(player, p, state)
		p.settings = { autoSellBelow = 7 }
		state.owned.CollectionMagnet = true
		assert(Forge.begin(player, 1, 1, "manual"))
		state.owned.CollectionMagnet = nil
		Forge._completeNow(player)
		assert(p.pending ~= nil and p.weapons.w2 ~= nil and p.weaponsSold == 0, "revocation during session must disable filter")
	end)
end

tests["automatic extra rolls obey the default Epic keep threshold while manual keeps extras"] = function()
	fixture(function(player, p)
		p.settings = nil
		assert(Forge.begin(player, 1, 1, "free"))
		Forge._completeNow(player)
		assert(p.pending ~= nil and p.weaponsForged == 2 and p.ingots[1] == 8)
		if p.weapons.w2 then
			assert(p.weapons.w2.r >= 4 and p.weaponsSold == 0)
		else
			assert(p.weaponsSold == 1 and p.coins > 0, "low-rarity auto extra should sell")
		end
	end)
	fixture(function(player, p)
		p.settings = nil
		assert(Forge.begin(player, 1, 1, "manual"))
		Forge._completeNow(player)
		assert(p.pending ~= nil and p.weapons.w2 ~= nil and p.weaponsSold == 0, "manual extras must remain owned")
	end)
end

tests["premium luck requires current ownership and paid policy at start and completion"] = function()
	fixture(function(player, p, state)
		assert(select(2, Forge.begin(player, 1, 1, "premium")) == "NotOwned")
		state.owned.PremiumAutoForge = true
		state.allowed = false
		assert(select(2, Forge.begin(player, 1, 1, "premium")) == "PaidRandomRestricted")
		state.allowed = true
		assert(Forge.begin(player, 1, 1, "premium"))
		state.allowed = false
		Forge._completeNow(player)
		assert(p.weaponsForged == 0 and p.ingots[1] == 10 and not Forge.session(player).auto, "restriction must cancel paid completion without charging")
		state.allowed = true
		assert(Forge.begin(player, 1, 1, "premium"))
		state.owned.PremiumAutoForge = nil
		Forge._completeNow(player)
		assert(p.weaponsForged == 0 and p.ingots[1] == 10, "revoked pass must not retain premium luck")
	end)
end

tests["restricted or revoked MultiForge retains free one-roll gameplay"] = function()
	fixture(function(player, p, state)
		state.allowed = false
		assert(Forge.begin(player, 1, 1, "free"))
		Forge._completeNow(player)
		assert(p.weaponsForged == 1 and p.ingots[1] == 9)
	end)
	fixture(function(player, p, state)
		assert(Forge.begin(player, 1, 1, "free"))
		state.owned.MultiForge = nil
		Forge._completeNow(player)
		assert(p.weaponsForged == 1 and p.ingots[1] == 9)
	end)
end

tests["evolution and reloaded profiles cancel stale sessions without consuming new materials"] = function()
	fixture(function(player, p)
		assert(Forge.begin(player, 1, 1, "free"))
		p.evolutionRank = 1
		Forge._completeNow(player)
		assert(p.weaponsForged == 0 and p.ingots[1] == 10 and not Forge.session(player).auto)
	end)
	fixture(function(player, p)
		assert(Forge.begin(player, 1, 1, "free"))
		local replacement = Economy.newProfile()
		Data._setForTest(player, replacement)
		Forge._completeNow(player)
		assert(replacement.weaponsForged == 0 and replacement.ingots[1] == Economy.STARTER_INGOTS and p.ingots[1] == 10)
	end)
end

tests["locked material cannot be forged from stale ingots and failures are free"] = function()
	fixture(function(player, p)
		p.ingots[2] = 20
		assert(select(2, Forge.begin(player, 1, 2, "free")) == "MaterialLocked")
		assert(p.ingots[2] == 20 and p.weaponsForged == 0)
		assert(select(2, Economy.completeForgeBatch(p, 1, 1, 1.5, Random.new(5), 0, 3)) == "InvalidRequest")
		assert(p.ingots[1] == 10 and p.weaponsForged == 0)
	end)
end

tests["two players have independent sessions, materials, rolls, and pending results"] = function()
	fixture(function(player, p)
		local other = { UserId = -7352, Name = "OtherSmith", Parent = Players }
		local otherProfile = Economy.newProfile()
		Data._setForTest(other, otherProfile)
		local ok, err = pcall(function()
			assert(Forge.begin(player, 1, 1, "manual"))
			assert(Forge.begin(other, 4, 1, "manual"))
			local a, b = Forge.session(player), Forge.session(other)
			assert(a.id ~= b.id)
			assert(select(2, Forge.strike(other, a.id)) == "NoSession", "another player's session id accepted")
			Forge._completeNow(player)
			assert(p.weaponsForged == 2 and p.ingots[1] == 8)
			assert(otherProfile.weaponsForged == 0 and otherProfile.pending == nil and otherProfile.ingots[1] == Economy.STARTER_INGOTS)
			Forge._completeNow(other)
			assert(otherProfile.weaponsForged == 2 and otherProfile.ingots[1] == Economy.STARTER_INGOTS - 2)
			assert(otherProfile.pending.c == 4 and p.pending.c == 1, "ownership/class crossed profiles")
			assert(Forge.resolve(other, "keep") and otherProfile.pending == nil and p.pending ~= nil, "another player's resolve changed primary")
		end)
		Data._setForTest(other, nil)
		if not ok then error(err, 0) end
	end)
end

tests["stop auto finishes one batch and queued timer replays never restart or duplicate it"] = function()
	fixture(function(player, p, state)
		assert(Forge.begin(player, 1, 1, "free"))
		assert(Forge.stopAuto(player))
		Forge._completeNow(player)
		state.now += 20
		for _, callback in state.timers do callback() end
		assert(p.weaponsForged == 2 and p.ingots[1] == 8 and Forge.session(player).done, "stopped loop restarted or replay duplicated batch")
	end)
end

tests["policy-hook interleaving cannot open a second session or complete across evolution"] = function()
	fixture(function(player, p, state)
		assert(Forge.begin(player, 1, 1, "free"))
		local attempted = false
		state.policyHook = function()
			state.policyHook = nil
			local ok, why = Forge.begin(player, 1, 1, "free")
			assert(not ok and why == "Busy", "yielding completion opened second forge")
			attempted = true
			p.evolutionRank = 1
		end
		Forge._completeNow(player)
		assert(attempted and p.weaponsForged == 0 and p.ingots[1] == 10, "stale completion spent materials after policy yield")
	end)
end

return tests
