--!nonstrict
-- Client-side ProximityPrompts (local only) that open the 2D panels, plus egg stand info billboards.
local Common = require(script.Parent.WorldUtil.Common)
local State = Common.State

local WorldPrompts = { Priority = 0 }

local plotPrompts = {} -- instances created for the local plot
local plotIndexBuilt = nil
local hubDone = {} -- [Instance] = true

local function openPanel(name, arg)
	local ui = Common.Client:FindFirstChild("UI")
	local mod = ui and ui:FindFirstChild("Panels")
	if not mod then
		return
	end
	local ok, Panels = pcall(require, mod)
	if ok and Panels and Panels.open then
		local ok2, err = pcall(Panels.open, name, arg)
		if not ok2 then
			warn("[WorldPrompts] open", name, err)
		end
	end
end

local function makePrompt(att, actionText, objectText, panel, arg)
	local p = Instance.new("ProximityPrompt")
	p.Name = "WorldPrompt"
	p.ActionText = actionText
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Triggered:Connect(function()
		openPanel(panel, arg)
	end)
	p.Parent = att
	return p
end

local function clearPlot()
	for _, p in plotPrompts do
		if p.Parent then
			p:Destroy()
		end
	end
	table.clear(plotPrompts)
end

local function addPlot(done, att, action, object, panel, arg)
	if not att or done[att] then
		return
	end
	done[att] = true
	table.insert(plotPrompts, makePrompt(att, action, object, panel, arg))
end

local plotDone = {}

local function buildPlot()
	local plot = Common.myPlot()
	if not plot then
		return false
	end
	local machines = plot:FindFirstChild("Machines")
	if not machines then
		return false
	end
	local function pp(m)
		local model = machines:FindFirstChild(m)
		return model and model:FindFirstChild("PromptPoint", true)
	end
	addPlot(plotDone, pp("Anvil"), "Forge", "Anvil", "Forge")
	addPlot(plotDone, pp("Extractor"), "Materials", "Extractor", "Materials")
	addPlot(plotDone, pp("Smelter"), "Workshop", "Smelter", "Workshop")
	addPlot(plotDone, pp("Storage"), "Workshop", "Storage", "Workshop")
	addPlot(plotDone, pp("Furnace"), "Workshop", "Furnace", "Workshop")
	local showcase = plot:FindFirstChild("Showcase")
	if showcase then
		for _, ped in showcase:GetChildren() do
			local slot = ped:GetAttribute("Slot")
			if slot then
				addPlot(plotDone, ped:FindFirstChild("DisplaySpot", true), "Showcase", "Pedestal " .. slot, "Showcase", slot)
			end
		end
	end
	return machines:FindFirstChild("Anvil") ~= nil
end

local function eggBillboard(stand, att, eggId)
	local Eggs = Common.config("Eggs")
	local row = Eggs and Eggs.ById and Eggs.ById[eggId]
	local base = stand:FindFirstChild("Egg") or stand.PrimaryPart
	if not row or not base then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggInfo"
	gui.Adornee = base
	gui.Size = UDim2.fromOffset(180, 66)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.MaxDistance = 45
	gui.AlwaysOnTop = false
	local function label(y, h, text, color, size)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, h)
		l.Font = Enum.Font.FredokaOne
		l.TextSize = size
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.4
		l.Text = text
		l.Parent = gui
	end
	label(0, 26, tostring(row.name or eggId), row.color or Color3.new(1, 1, 1), 20)
	label(26, 20, Common.abbrev(row.coinCost or 0) .. " coins", Color3.fromRGB(255, 215, 90), 16)
	if (row.unlockTier or 1) > 1 then
		label(46, 18, "Unlocks at tier " .. tostring(row.unlockTier), Color3.fromRGB(200, 200, 210), 14)
	end
	gui.Parent = stand
end

local function buildHub()
	local hub = Common.hub()
	if not hub then
		return
	end
	local hatch = hub:FindFirstChild("Hatchery")
	if hatch then
		for _, stand in hatch:GetChildren() do
			local eggId = stand:GetAttribute("EggId")
			if eggId and not hubDone[stand] then
				local att = stand:FindFirstChild("PromptPoint", true)
				if att then
					hubDone[stand] = true
					makePrompt(att, "Hatch", stand.Name:gsub("^Egg_", "") .. " Egg", "Hatch", eggId)
					eggBillboard(stand, att, eggId)
				end
			end
		end
	end
	local altar = hub:FindFirstChild("EvolutionAltar")
	if altar and not hubDone[altar] then
		local att = altar:FindFirstChild("PromptPoint", true)
		if att then
			hubDone[altar] = true
			makePrompt(att, "Evolution", "Altar", "Evolution")
		end
	end
	local stall = hub:FindFirstChild("MerchantStall")
	if stall and not hubDone[stall] then
		local att = stall:FindFirstChild("PromptPoint", true)
		if att then
			hubDone[stall] = true
			makePrompt(att, "Shop", "Merchant", "Shop")
		end
	end
end

local function refresh()
	local idx = Common.myPlotIndex()
	if idx ~= plotIndexBuilt then
		clearPlot()
		table.clear(plotDone)
		plotIndexBuilt = idx
	end
	if idx then
		buildPlot()
	end
	buildHub()
end

function WorldPrompts.start()
	State.observe(function()
		refresh()
	end)
	-- Models may stream/replicate late; retry for a while.
	for _ = 1, 30 do
		refresh()
		task.wait(2)
	end
end

return WorldPrompts
