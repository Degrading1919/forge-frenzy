--!nonstrict
-- Defensive accessors over Shared.Config.* (modules may not exist yet) plus naming helpers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.Theme)

local Data = {}

Data.ClassNames = { "Sword", "Greatsword", "Axe", "Dagger", "Hammer" }
Data.ClassIcons = { "🗡", "⚔", "🪓", "🔪", "🔨" }
Data.CraftNames = { "Crude", "Standard", "Fine", "Masterwork", "Perfect" }
Data.EraNames = {
	"Basic Metals", "Refined Metals", "Industrial Metals", "Arcane Metals",
	"Elemental", "Forbidden", "Celestial", "Ancient",
}
Data.CraftOdds = { 0.24, 0.42, 0.24, 0.09, 0.01 }
Data.TraitOdds = { 0.02, 0.04, 0.08, 0.15, 0.30, 0.50 }
Data.BaseRarity = { 0.65045, 0.23, 0.09, 0.025, 0.0045, 0.00005 }
Data.LuckPerCps = 0.3

local cache: { [string]: any } = {}

local function loadConfig(name: string): any
	if cache[name] ~= nil then return cache[name] end
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local folder = shared and shared:FindFirstChild("Config")
	local mod = folder and folder:FindFirstChild(name)
	if not mod then return nil end
	local ok, res = pcall(require, mod)
	if ok and type(res) == "table" then
		cache[name] = res
		return res
	end
	return nil
end
Data.config = loadConfig

-- Materials ---------------------------------------------------------------

local materials: { any }? = nil
local fallback: { any }? = nil
local fallbackAt = 0

function Data.materials(): { any }
	if materials then return materials end
	if fallback and os.clock() - fallbackAt < 3 then return fallback end
	local raw = loadConfig("Materials")
	local src = raw and (raw.Materials or raw.list or raw)
	local out = {}
	local real = src ~= nil and #src > 0
	for i = 1, 32 do
		local r = real and src[i] or nil
		local minP = (r and r.priceMin) or math.round(12 * 1.78 ^ (i - 1))
		local row = {
			index = i,
			name = (r and r.name) or ("Material " .. i),
			era = (r and r.era) or math.ceil(i / 8),
			priceMin = minP,
			priceMax = (r and r.priceMax) or minP * 18,
			unlockCost = (r and r.unlockCost) or 0,
			color = (r and r.color) or Color3.fromRGB(150, 150, 150),
			material = r and r.material or nil,
			accent = r and r.accent or nil,
			glow = r and r.glow or false,
		}
		out[i] = row
	end
	if real then
		materials = out
	else
		fallback, fallbackAt = out, os.clock() -- retried until the real config exists
	end
	return out
end

function Data.mat(i: number): any
	return Data.materials()[i] or { index = i, name = "Material " .. tostring(i), era = 1, priceMin = 0, priceMax = 0, unlockCost = 0, color = Color3.fromRGB(150, 150, 150) }
end

-- Returns the display header for a material era value (number or string).
function Data.eraName(era: any, idx: number): string
	if type(era) == "string" then return era end
	return Data.EraNames[era or math.ceil(idx / 8)] or ("Era " .. tostring(era))
end

function Data.weaponName(w: any): string
	if not w then return "Unknown" end
	local parts = {}
	if w.q and w.q ~= 2 then -- "Standard" is noise in a name
		table.insert(parts, Data.CraftNames[w.q] or "")
	end
	if w.t and w.t ~= "" then table.insert(parts, w.t) end
	table.insert(parts, Data.mat(w.m).name)
	table.insert(parts, Data.ClassNames[w.c] or "Weapon")
	return table.concat(parts, " ")
end

-- Companions / Eggs / Products ------------------------------------------------

function Data.rarityIndex(r: any): number
	if type(r) == "number" then return math.clamp(math.floor(r), 1, 6) end
	if type(r) == "string" then
		local i = table.find(Theme.RarityNames, r)
		if i then return i end
	end
	return 1
end

function Data.companions(): { [string]: any }
	local c = loadConfig("Companions")
	return c and (c.ById or c) or {}
end

function Data.companion(kind: string): any
	local c = Data.companions()[kind]
	if c then return c end
	return { id = kind, name = tostring(kind), rarity = "Common", bonus = {}, color = Color3.fromRGB(180, 180, 180), modelKind = kind }
end

-- Companion rarity string -> color (supports "Exclusive").
function Data.petRarityColor(rarity: any): Color3
	local c = loadConfig("Companions")
	if c and c.RarityColors and c.RarityColors[rarity] then return c.RarityColors[rarity] end
	return Theme.rarityColor(Data.rarityIndex(rarity))
end

function Data.eggs(): { any }
	local cfg = loadConfig("Eggs")
	if not cfg then return {} end
	return cfg.List or cfg.Eggs or {}
end

function Data.egg(id: any): any
	for _, e in Data.eggs() do
		if e.id == id then return e end
	end
	return nil
end

-- {{ kind, name, rarity, percent }} for an egg; computed from weights if Eggs.odds is absent.
function Data.eggOdds(eggId: string): { any }
	local cfg = loadConfig("Eggs")
	if cfg and cfg.odds then
		local ok, res = pcall(cfg.odds, eggId)
		if ok and type(res) == "table" then return res end
	end
	local egg = Data.egg(eggId)
	local out, total = {}, 0
	if egg then
		for _, k in egg.kinds do total += k.weight end
		for _, k in egg.kinds do
			local d = Data.companion(k.kind)
			table.insert(out, { kind = k.kind, name = d.name, rarity = d.rarity, percent = k.weight / total * 100 })
		end
	end
	return out
end

-- Returns array of { key, def } in config order; also the LIVE flag.
function Data.products(): ({ any }, boolean)
	local cfg = loadConfig("Products")
	local list = {}
	if cfg then
		for _, v in cfg.List or {} do
			table.insert(list, { key = v.key, def = v })
		end
	end
	return list, cfg ~= nil and cfg.LIVE == true
end

-- Bonus summary text for a companion bonus table of fractions.
local BONUS_LABELS = { extract = "Extract", smelt = "Smelt", prep = "Prep", storage = "Storage" }
function Data.bonusText(b: any): string
	local parts = {}
	for _, key in { "extract", "smelt", "prep", "storage" } do
		local v = b and b[key]
		if v and v ~= 0 then
			table.insert(parts, string.format("+%d%% %s", math.round(v * 100), BONUS_LABELS[key]))
		end
	end
	return #parts > 0 and table.concat(parts, "  ") or "No bonus"
end

-- Odds ---------------------------------------------------------------------

-- Rarity chances for a luck value; prefers Shared.ForgeMath.rarityChances.
function Data.rarityChances(luck: number): { number }
	luck = math.clamp(luck, 1, 5)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local mod = shared and shared:FindFirstChild("ForgeMath")
	if mod then
		if cache.ForgeMath == nil then
			local ok, res = pcall(require, mod)
			cache.ForgeMath = (ok and type(res) == "table") and res or false
		end
		local fm = cache.ForgeMath
		if fm and fm.rarityChances then
			local ok, res = pcall(fm.rarityChances, luck)
			if ok and type(res) == "table" and #res == 6 then return res end
		end
	end
	local b = Data.BaseRarity
	local rare, epic, leg, myth = b[3] * luck, b[4] * luck, b[5] * luck, b[6] * luck
	local common = 1 - b[2] - rare - epic - leg - myth
	return { common, b[2], rare, epic, leg, myth }
end

-- Journal helpers -------------------------------------------------------------

function Data.hasBit(mask: number?, rarity: number): boolean
	return bit32.band(mask or 0, bit32.lshift(1, rarity - 1)) ~= 0
end

function Data.sumIngots(p: any): number
	local s = 0
	for _, n in p.ingots or {} do
		s += n
	end
	return s
end

return Data
