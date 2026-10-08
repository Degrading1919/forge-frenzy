-- Public workshop projection must never leak private profile fields or trust client flags.
local Plots = require(script.Parent.Parent.Net.Plots)
local tests = {}

tests["public workshop state is an explicit privacy projection"] = function()
	local p = {
		coins = 123456, receipts = { private = true }, weapons = { secret = true }, pets = { secret = true },
		ingots = { [1] = 99 }, selectedMaterial = 7, evolutionRank = 3,
		levels = { ExtractorOutput = 4, SmelterSpeed = 2, PrivateTrack = 999 },
		gear = { Hammer = 3, PrivateGear = 999 },
		entitlements = { TitanExcavator = true, StarterPack = true },
		lines = { { m = 3, ore = 5 }, { m = 99 }, { m = 2 }, { m = 1 } },
		stations = { { m = 4, c = 2, keep = 7 }, { m = 1, c = 9 } },
	}
	local public = Plots.publicVisual(p, { VIPWorkshop = true, StarterPack = true }, { orePerSec = 8, capacity = 9999 })
	assert(public.selectedMaterial == 7 and public.evolutionRank == 3)
	assert(public.levels.ExtractorOutput == 4 and public.gear.Hammer == 3 and public.rates.orePerSec == 8)
	assert(public.entitlements.VIPWorkshop and not public.entitlements.TitanExcavator, "profile flag bypassed verified entitlements")
	assert(public.entitlements.StarterPack == nil and public.levels.PrivateTrack == nil and public.gear.PrivateGear == nil)
	-- v2 publishes each ore line's material and each station's recipe (clamped, max 3 each).
	assert(#public.lines == 3 and public.lines[1] == 3 and public.lines[2] == 32 and public.lines[3] == 2, "line materials clamped, capped at 3")
	assert(public.stations[1].m == 4 and public.stations[1].c == 2 and public.stations[1].keep == nil, "station recipe only")
	assert(public.stations[2].c == 5, "class clamped")
	local allowed = { selectedMaterial = true, evolutionRank = true, levels = true, gear = true, entitlements = true, rates = true, lines = true, stations = true }
	for key in public do assert(allowed[key], "private field leaked: " .. key) end
	assert(public.rates.capacity == nil and public.coins == nil and public.ingots == nil)
	public.levels.ExtractorOutput = 90
	public.gear.Hammer = 90
	assert(p.levels.ExtractorOutput == 4 and p.gear.Hammer == 3, "public projection aliases authoritative tables")
end

tests["malformed public visual numbers fail safely"] = function()
	local public = Plots.publicVisual({ selectedMaterial = math.huge, evolutionRank = -5,
		levels = { ExtractorOutput = 0 / 0, StorageCapacity = -10 }, gear = { Hammer = "bad" } }, nil,
		{ orePerSec = math.huge })
	assert(public.selectedMaterial == 1 and public.evolutionRank == 0)
	assert(public.levels.ExtractorOutput == 0 and public.levels.StorageCapacity == 0 and public.gear.Hammer == 0)
	assert(math.abs(public.rates.orePerSec - 1 / 3) < 1e-9, "malformed rate falls back to the base rate")
	assert(#public.lines == 0 and #public.stations == 0, "missing lines/stations project as empty")
end

return tests
