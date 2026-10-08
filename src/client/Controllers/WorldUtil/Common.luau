--!nonstrict
-- Shared helpers for the World* presentation controllers (client only, defensive).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent.Parent
local State = require(Client.State)

local Common = {}
Common.player = Players.LocalPlayer
Common.State = State
Common.Client = Client

Common.RarityNames = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
Common.RarityColors = {
	Color3.fromRGB(190, 190, 195),
	Color3.fromRGB(90, 205, 105),
	Color3.fromRGB(80, 155, 255),
	Color3.fromRGB(185, 105, 255),
	Color3.fromRGB(255, 190, 40),
	Color3.fromRGB(255, 70, 130),
}
Common.ClassNames = { "Sword", "Greatsword", "Axe", "Dagger", "Hammer" }
Common.CraftNames = { "Crude", "Standard", "Fine", "Masterwork", "Perfect" }

function Common.rarityColor(r)
	return Common.RarityColors[r or 1] or Common.RarityColors[1]
end

-- Safe require of ReplicatedStorage.Shared.<path...>; cached once found.
local sharedCache = {}
function Common.shared(path)
	local key = table.concat(path, ".")
	if sharedCache[key] ~= nil then
		return sharedCache[key] or nil
	end
	local inst = ReplicatedStorage:FindFirstChild("Shared")
	for _, n in path do
		inst = inst and inst:FindFirstChild(n)
	end
	if not inst or not inst:IsA("ModuleScript") then
		return nil -- not cached so a later call can succeed once it replicates
	end
	local ok, m = pcall(require, inst)
	sharedCache[key] = ok and m or false
	return ok and m or nil
end

function Common.config(name)
	return Common.shared({ "Config", name })
end

-- Materials config row for a material index (nil-safe).
function Common.materialRow(m)
	local mats = Common.config("Materials")
	if mats and m then
		return mats[m]
	end
	return nil
end

function Common.materialColor(m)
	local row = Common.materialRow(m)
	return row and row.color or nil
end

function Common.skin(m)
	local row = Common.materialRow(m)
	if row then
		return { color = row.color, material = row.material, accent = row.accent, glow = row.glow }
	end
	return { color = Color3.fromRGB(180, 180, 190), material = "Metal", accent = nil, glow = false }
end

function Common.vfx()
	local p = State.profile
	return not (p and p.settings and p.settings.vfx == false)
end

function Common.plotsFolder()
	local w = Workspace:FindFirstChild("World")
	return w and w:FindFirstChild("Plots")
end

function Common.hub()
	local w = Workspace:FindFirstChild("World")
	return w and w:FindFirstChild("Hub")
end

function Common.myPlotIndex()
	local p = State.profile
	local idx = p and p.plotIndex
	if type(idx) ~= "number" or idx <= 0 then
		idx = Common.player:GetAttribute("PlotIndex")
	end
	if type(idx) == "number" and idx > 0 then
		return idx
	end
	return nil
end

function Common.myPlot()
	local idx = Common.myPlotIndex()
	local plots = Common.plotsFolder()
	if idx and plots then
		return plots:FindFirstChild("Plot" .. idx)
	end
	return nil
end

-- Path lookup with FindFirstChild; returns nil if anything is missing.
function Common.find(root, ...)
	local inst = root
	for _, n in { ... } do
		if not inst then
			return nil
		end
		inst = inst:FindFirstChild(n)
	end
	return inst
end

function Common.myMachine(name)
	local plot = Common.myPlot()
	return plot and Common.find(plot, "Machines", name)
end

function Common.fxFolder()
	local f = Workspace:FindFirstChild("ClientFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "ClientFX"
		f.Parent = Workspace
	end
	return f
end

function Common.camPos()
	local cam = Workspace.CurrentCamera
	return cam and cam.CFrame.Position
end

function Common.sumLevels(profile)
	local n = 0
	if profile and profile.levels then
		for _, v in profile.levels do
			if type(v) == "number" then
				n += v
			end
		end
	end
	return n
end

function Common.sumArray(t)
	local n = 0
	if t then
		for _, v in t do
			if type(v) == "number" then
				n += v
			end
		end
	end
	return n
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
function Common.abbrev(n)
	n = n or 0
	if n ~= n then
		return "0"
	end
	local neg = n < 0
	n = math.abs(n)
	local i = 1
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	local s
	if i == 1 then
		s = tostring(math.floor(n + 0.5))
	elseif n >= 100 then
		s = string.format("%d", math.floor(n))
	elseif n >= 10 then
		s = string.format("%.1f", n)
	else
		s = string.format("%.2f", n)
	end
	if i > 1 then
		if string.find(s, ".", 1, true) then
			s = string.gsub(s, "0+$", "")
			s = string.gsub(s, "%.$", "")
		end
		s = s .. SUFFIXES[i]
	end
	return (neg and "-" or "") .. s
end

-- Make every BasePart in inst inert (anchored, no collision / queries).
function Common.inert(inst)
	local function fix(p)
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
		end
	end
	fix(inst)
	for _, d in inst:GetDescendants() do
		fix(d)
	end
end

return Common
