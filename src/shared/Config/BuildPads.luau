--!strict
--[[
	Build pads — the tycoon build-out of a workshop (docs/21 §8, docs/22).

	A new player starts with one ore line, one forge and two display podiums. Stepping on a
	glowing pad in the workshop buys it with cash and physically builds what it names. Pads are
	permanent: they survive evolution, because the workshop is the player's home and a reset
	that knocked buildings down would feel punishing to younger players.

	Fields:
	  id        stable key stored in profile.pads
	  name      short label on the pad
	  kind      "podiums" (two more display slots) | "line" (another ore line) |
	            "forge" (another forge station) | "decor" (pure decoration)
	  tier      material tier that must be unlocked before the pad appears
	  costTier / costFactor  price = costFactor * unlock price of material `costTier`
	  requires  pad that must be built first (the pad stays hidden until then)

	The world model names each built object with a matching `PadId` attribute.
]]

local Materials = require(script.Parent.Materials)

export type Pad = {
	id: string,
	name: string,
	kind: "podiums" | "line" | "forge" | "decor",
	tier: number,
	costTier: number,
	costFactor: number,
	requires: string?,
	cost: number,
}

local function roundPrice(cost: number): number
	if cost < 1000 then
		return math.floor(cost + 0.5)
	end
	local magnitude = 10 ^ (math.floor(math.log10(cost)) - 2)
	return math.floor(cost / magnitude + 0.5) * magnitude
end

local list = {
	{ id = "podiums_1", name = "Display Podiums", kind = "podiums", tier = 2, costTier = 2, costFactor = 0.5 },
	{ id = "forge_2", name = "Forge #2", kind = "forge", tier = 3, costTier = 3, costFactor = 0.8 },
	{ id = "decor_banners", name = "Banners", kind = "decor", tier = 3, costTier = 3, costFactor = 0.25 },
	{ id = "line_2", name = "Ore Line #2", kind = "line", tier = 4, costTier = 4, costFactor = 0.8 },
	{ id = "podiums_2", name = "Display Podiums", kind = "podiums", tier = 5, costTier = 5, costFactor = 0.6, requires = "podiums_1" },
	{ id = "decor_fountain", name = "Lava Fountain", kind = "decor", tier = 6, costTier = 6, costFactor = 0.3 },
	{ id = "forge_3", name = "Forge #3", kind = "forge", tier = 7, costTier = 7, costFactor = 1.0, requires = "forge_2" },
	{ id = "line_3", name = "Ore Line #3", kind = "line", tier = 9, costTier = 9, costFactor = 1.0, requires = "line_2" },
	{ id = "podiums_3", name = "Display Podiums", kind = "podiums", tier = 11, costTier = 11, costFactor = 0.7, requires = "podiums_2" },
	{ id = "decor_statue", name = "Golden Anvil", kind = "decor", tier = 14, costTier = 14, costFactor = 0.5 },
	{ id = "decor_crystals", name = "Crystal Garden", kind = "decor", tier = 20, costTier = 20, costFactor = 0.5 },
	{ id = "decor_portal", name = "Star Portal", kind = "decor", tier = 26, costTier = 26, costFactor = 0.5 },
}

local BuildPads = {}
BuildPads.List = {} :: { Pad }
BuildPads.ById = {} :: { [string]: Pad }

BuildPads.StarterLines = 1
BuildPads.StarterForges = 1
BuildPads.MaxLines = 3
BuildPads.MaxForges = 3

for _, row in list do
	local pad = row :: any
	pad.cost = roundPrice(pad.costFactor * Materials[pad.costTier].unlockCost)
	assert(BuildPads.ById[pad.id] == nil, "duplicate pad " .. pad.id)
	table.insert(BuildPads.List, pad)
	BuildPads.ById[pad.id] = pad
end

local function count(pads: { [string]: any }?, kind: string): number
	local n = 0
	for _, pad in BuildPads.List do
		if pad.kind == kind and pads and pads[pad.id] then
			n += 1
		end
	end
	return n
end

function BuildPads.lineCount(pads: { [string]: any }?): number
	return math.min(BuildPads.MaxLines, BuildPads.StarterLines + count(pads, "line"))
end

function BuildPads.forgeCount(pads: { [string]: any }?): number
	return math.min(BuildPads.MaxForges, BuildPads.StarterForges + count(pads, "forge"))
end

-- Display slots unlocked: two starter podiums plus two per podium pad.
function BuildPads.showcaseSlots(pads: { [string]: any }?, starter: number, max: number): number
	return math.min(max, starter + 2 * count(pads, "podiums"))
end

-- Whether a pad is visible/buyable for a profile (tier reached and prerequisite built).
function BuildPads.available(pad: Pad, pads: { [string]: any }?, highestTier: number): boolean
	if pads and pads[pad.id] then
		return false
	end
	if highestTier < pad.tier then
		return false
	end
	return pad.requires == nil or (pads ~= nil and pads[pad.requires] == true)
end

return BuildPads
