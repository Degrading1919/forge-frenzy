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
	}
	local public = Plots.publicVisual(p, { VIPWorkshop = true, StarterPack = true }, { orePerSec = 8, capacity = 9999 })
	assert(public.selectedMaterial == 7 and public.evolutionRank == 3)
	assert(public.levels.ExtractorOutput == 4 and public.gear.Hammer == 3 and public.rates.orePerSec == 8)
	assert(public.entitlements.VIPWorkshop and not public.entitlements.TitanExcavator, "profile flag bypassed verified entitlements")
	assert(public.entitlements.StarterPack == nil and public.levels.PrivateTrack == nil and public.gear.PrivateGear == nil)
	local allowed = { selectedMaterial = true, evolutionRank = true, levels = true, gear = true, entitlements = true, rates = true }
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
	assert(public.rates.orePerSec == 1.5)
end

return tests
