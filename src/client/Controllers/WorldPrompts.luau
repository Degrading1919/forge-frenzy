--!nonstrict
--[[
	World interaction prompts (v2): everything is done by walking up to things (docs/21 §1).

	Your workshop: forges, ore lines, the storage vault, the tool rack, podiums (display), build
	pads (step on them or press E), the cash collector (step on it) and the LOCK button.
	Other workshops: hold E on a podium to steal its weapon.
	The hub: the sell booth, pet eggs, the evolution altar and the shop.
	Prompts are local to this client; the server checks distance and rules for every action.
]]
local Players = game:GetService("Players")
local Common = require(script.Parent.WorldUtil.Common)
local Sfx = require(script.Parent.WorldUtil.Sfx)
local State = Common.State
local UI = Common.Client.UI
local Panels = require(UI.Panels)
local Kit = require(UI.Kit)
local Toast = require(UI.Toast)
local Reveal = require(UI.Reveal)
local Theme = require(UI.Theme)
local Net = require(Common.Client.Net)

local WorldPrompts = { Priority = 0 }

-- Shared hold-time rule (the server enforces the same one).
local function holdFor(value: number): number
	local Steal = Common.shared({ "Steal" })
	return if Steal then Steal.holdSeconds(value) else 2
end

local made: { [Instance]: ProximityPrompt } = {}
local touchHooked: { [Instance]: boolean } = {}
local lastTouch: { [string]: number } = {}

local function prompt(att: Instance, action: string, object: string, onTrigger: () -> (), opts: any?): ProximityPrompt?
	if not att or made[att] then
		return made[att]
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "WorldPrompt"
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = opts and opts.hold or 0
	p.MaxActivationDistance = opts and opts.range or 11
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Style = Enum.ProximityPromptStyle.Default
	p.Triggered:Connect(function()
		Sfx.play("click")
		onTrigger(att)
	end)
	p.Parent = att
	made[att] = p
	return p
end

-- The station a panel was opened from; walking away from it closes the panel, so stations
-- feel like real places instead of remote menus.
local openedFrom: { att: Attachment?, name: string? } = {}

local function open(name: string, arg: any?)
	return function(att: Attachment?)
		if Reveal.isOpen() then return end
		Panels.open(name, arg)
		openedFrom.att, openedFrom.name = att, name
	end
end

local function myPlot()
	return Common.myPlot()
end

local function padCost(padId: string): (number?, string?)
	local cfg = Common.config("BuildPads")
	local pad = cfg and cfg.ById and cfg.ById[padId]
	return pad and pad.cost, pad and pad.name
end

local function buyPad(padId: string)
	local key = "pad:" .. padId
	if lastTouch[key] and os.clock() - lastTouch[key] < 1.5 then return end
	lastTouch[key] = os.clock()
	local cost, name = padCost(padId)
	local p = State.profile
	if cost and p and (p.coins or 0) < cost then
		Toast.show(string.format("%s costs %s. Keep forging!", name or "This", Theme.money(cost)), "bad")
		return
	end
	local ok = Kit.call("BuyPad", padId)
	if ok then
		Sfx.play("upgrade")
		Reveal.message("BUILT!", name or padId, Theme.Colors.green, "🏗️", "Your workshop is growing!")
		Net.call("TutorialStep", 6)
	end
end

-- Calls `fn` when the local character steps on `part` (debounced).
local function onStep(part: BasePart, key: string, fn: () -> ())
	if touchHooked[part] then return end
	touchHooked[part] = true
	part.CanTouch = true
	part.Touched:Connect(function(hit)
		local char = Players.LocalPlayer.Character
		if not char or not hit:IsDescendantOf(char) then return end
		if lastTouch[key] and os.clock() - lastTouch[key] < 1.5 then return end
		fn()
	end)
end

local function buildMine()
	local plot = myPlot()
	if not plot then return end
	local machines = plot:FindFirstChild("Machines")
	if machines then
		for _, model in machines:GetChildren() do
			local forgeIndex = model:GetAttribute("ForgeIndex")
			local lineIndex = model:GetAttribute("LineIndex")
			if forgeIndex then
				prompt(model:FindFirstChild("PromptPoint", true), "Forge", "Forge " .. forgeIndex, open("Forge", forgeIndex))
			elseif lineIndex then
				local drill = model:FindFirstChild("Drill")
				local smelter = model:FindFirstChild("Smelter")
				if drill then prompt(drill:FindFirstChild("PromptPoint", true), "Pick Metal", "Ore Drill " .. lineIndex, open("Ore", lineIndex)) end
				if smelter then prompt(smelter:FindFirstChild("PromptPoint", true), "Upgrade", "Smelter " .. lineIndex, open("Ore", lineIndex)) end
			elseif model.Name == "Storage" then
				prompt(model:FindFirstChild("PromptPoint", true), "Open", "Storage Vault", open("Vault"))
			elseif model.Name == "ToolRack" then
				prompt(model:FindFirstChild("PromptPoint", true), "Tools", "Tool Rack", open("Tools"))
			end
		end
	end
	local showcase = plot:FindFirstChild("Showcase")
	if showcase then
		for _, ped in showcase:GetChildren() do
			local slot = ped:GetAttribute("Slot")
			if slot then
				prompt(ped:FindFirstChild("DisplaySpot", true), "Display", "Podium " .. slot, open("Backpack", slot))
			end
		end
	end
	local pads = plot:FindFirstChild("BuildPads")
	if pads then
		for _, pad in pads:GetChildren() do
			local padId = pad:GetAttribute("PadId")
			if padId and pad:IsA("BasePart") then
				local cost, name = padCost(padId)
				prompt(pad:FindFirstChild("PromptPoint"), "Build " .. Theme.money(cost or 0), name or padId, function()
					buyPad(padId)
				end, { range = 9 })
				onStep(pad, "pad:" .. padId, function()
					buyPad(padId)
				end)
			end
		end
	end
	local collector = plot:FindFirstChild("Collector")
	if collector then
		local function collect()
			lastTouch.collect = os.clock()
			local p = State.profile
			if not p or (p.bank or 0) < 1 then return end
			local ok, amount = Net.call("CollectCash")
			if ok and type(amount) == "number" then
				Toast.cashPop(amount)
				Sfx.play("coin")
			end
		end
		prompt(collector:FindFirstChild("PromptPoint"), "Collect Cash", "Display Earnings", collect)
		onStep(collector, "collect", collect)
	end
	local lock = plot:FindFirstChild("LockButton")
	if lock then
		prompt(lock:FindFirstChild("PromptPoint"), "LOCK FORGE", "30 seconds of lasers", function()
			local ok = Kit.call("LockForge")
			if ok then
				Sfx.play("upgrade")
				Toast.show("LOCKED! Nobody can get in for 30 seconds", "good")
			end
		end)
	end
end

-- Steal prompts on everyone else's podiums.
local function buildSteal()
	local plots = Common.plotsFolder()
	if not plots then return end
	local mine = Common.myPlotIndex()
	for _, plot in plots:GetChildren() do
		local index = plot:GetAttribute("PlotIndex")
		if index and index ~= mine then
			local showcase = plot:FindFirstChild("Showcase")
			if showcase then
				for _, ped in showcase:GetChildren() do
					local slot = ped:GetAttribute("Slot")
					local att = ped:FindFirstChild("DisplaySpot", true)
					if slot and att and not made[att] then
						local p = prompt(att, "STEAL", "Hold to grab it!", function()
							local ok, res = Net.call("StealCommit", index, slot)
							if not ok and res then
								Toast.show(tostring(res), "bad")
							end
						end, { hold = 2, range = 9 })
						if p then
							p.Enabled = false -- shown only while that podium has a weapon
							p.PromptButtonHoldBegan:Connect(function()
								p:SetAttribute("Holding", true)
								local ok, res = Net.call("StealBegin", index, slot)
								if not ok then
									if res then Toast.show(tostring(res), "bad") end
									p.Enabled = false
									task.delay(1, function()
										p.Enabled = true
									end)
								end
							end)
							p.PromptButtonHoldEnded:Connect(function()
								p:SetAttribute("Holding", nil)
								Net.call("StealCancel")
							end)
						end
					end
				end
			end
		end
	end
end

-- Enable steal prompts only on occupied podiums of owned, unlocked workshops.
local function updateSteal()
	local plots = Common.plotsFolder()
	if not plots then return end
	local mine = Common.myPlotIndex()
	local now = workspace:GetServerTimeNow()
	local carrying = State.profile and State.profile.carrying
	for _, plot in plots:GetChildren() do
		local index = plot:GetAttribute("PlotIndex")
		if index and index ~= mine then
			local owned = (plot:GetAttribute("OwnerUserId") or 0) ~= 0
			local locked = (plot:GetAttribute("LockedUntil") or 0) > now
			local data = plot:FindFirstChild("ShowcaseData")
			local decoded = nil
			if data and data.Value ~= "" then
				local ok, res = pcall(function()
					return game:GetService("HttpService"):JSONDecode(data.Value)
				end)
				decoded = ok and res or nil
			end
			local showcase = plot:FindFirstChild("Showcase")
			if showcase then
				for _, ped in showcase:GetChildren() do
					local slot = ped:GetAttribute("Slot")
					local att = ped:FindFirstChild("DisplaySpot", true)
					local p = att and made[att]
					if p and slot then
						local entry = decoded and decoded.slots and decoded.slots[slot]
						local has = type(entry) == "table" and not entry.gone
						p.Enabled = owned and not locked and has and not carrying and not (decoded and decoded.shield)
						if type(entry) == "table" then
							local hold = tonumber(entry.h) or holdFor(entry.v)
							-- Never change the hold time while it is being held.
							if not p:GetAttribute("Holding") then
								p.HoldDuration = hold
							end
							p.ObjectText = string.format("Worth %s · hold %ss", Theme.money(entry.v), tostring(hold))
						else
							p.ObjectText = ""
						end
					end
				end
			end
		end
	end
end

local function buildHub()
	local hub = Common.hub()
	if not hub then return end
	local booth = hub:FindFirstChild("SellBooth")
	if booth then
		for _, att in booth:GetDescendants() do
			if att:IsA("Attachment") and att.Name == "PromptPoint" then
				prompt(att, "SELL", "Sell Booth", open("Sell"), { range = 12 })
			end
		end
	end
	local hatch = hub:FindFirstChild("Hatchery")
	if hatch then
		for _, stand in hatch:GetChildren() do
			local eggId = stand:GetAttribute("EggId")
			if eggId then
				local egg = Common.config("Eggs")
				local row = egg and egg.ById and egg.ById[eggId]
				prompt(stand:FindFirstChild("PromptPoint", true), "Open Egg", (row and row.name or eggId) .. "  " .. Theme.money(row and row.coinCost or 0), open("Hatch", eggId))
			end
		end
	end
	local altar = hub:FindFirstChild("EvolutionAltar")
	if altar then
		prompt(altar:FindFirstChild("PromptPoint", true), "Evolve", "Evolution Altar", open("Evolution"))
	end
	local stall = hub:FindFirstChild("MerchantStall")
	if stall then
		prompt(stall:FindFirstChild("PromptPoint", true), "Shop", "Boost Shop", open("Shop"))
	end
end

local lastPlot = nil
local function refresh()
	local idx = Common.myPlotIndex()
	if idx ~= lastPlot then
		for att, p in made do
			p:Destroy()
		end
		table.clear(made)
		table.clear(touchHooked)
		lastPlot = idx
	end
	if idx then
		buildMine()
	end
	buildSteal()
	buildHub()
	updateSteal()
end

function WorldPrompts.start()
	task.spawn(function()
		while true do
			task.wait(0.3)
			local att = openedFrom.att
			if att and openedFrom.name and Panels.isOpen(openedFrom.name) then
				local char = Players.LocalPlayer.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and att.Parent and (root.Position - att.WorldPosition).Magnitude > 22 then
					Panels.close()
					openedFrom.att = nil
				end
			end
		end
	end)
	-- New pads and buildings appear as the player builds, so keep scanning.
	while true do
		local ok, err = pcall(refresh)
		if not ok then
			warn("[WorldPrompts]", err)
		end
		task.wait(1)
	end
end

return WorldPrompts
