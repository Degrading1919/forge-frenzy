--!nonstrict
-- Guided first session. profile.tutorial = number of completed steps (0 = new). Current step = tutorial + 1.
local Players = game:GetService("Players")

local Common = require(script.Parent.WorldUtil.Common)
local Net = require(script.Parent.Parent.Net)
local State = Common.State

local WorldOnboarding = { Priority = 0 }

local TOTAL = 7
local TEXT = {
	"Walk to your workshop",
	"Open the forge at the anvil",
	"Forge your first weapon",
	"Sell it or keep it",
	"Buy an upgrade at the Workshop",
	"Unlock Tin at the Extractor",
	"Visit the Hatchery for a companion",
}

local localDone = 0 -- steps we have detected complete locally
local reported = 0
local forgeStarted = false
local gui, card, titleL, bodyL, barFill
local beam, a0, marker
local lastTarget = nil
local finished = false

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "Onboarding"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(1, 0)
	card.Position = UDim2.new(1, -12, 0, 70)
	card.Size = UDim2.fromOffset(270, 92)
	card.BackgroundColor3 = Color3.fromRGB(34, 26, 22)
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = card
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(255, 160, 60)
	s.Thickness = 2
	s.Parent = card
	titleL = Instance.new("TextLabel")
	titleL.BackgroundTransparency = 1
	titleL.Position = UDim2.fromOffset(12, 6)
	titleL.Size = UDim2.new(1, -24, 0, 18)
	titleL.Font = Enum.Font.GothamBold
	titleL.TextSize = 13
	titleL.TextXAlignment = Enum.TextXAlignment.Left
	titleL.TextColor3 = Color3.fromRGB(255, 170, 70)
	titleL.Parent = card
	bodyL = Instance.new("TextLabel")
	bodyL.BackgroundTransparency = 1
	bodyL.Position = UDim2.fromOffset(12, 26)
	bodyL.Size = UDim2.new(1, -24, 0, 42)
	bodyL.Font = Enum.Font.FredokaOne
	bodyL.TextSize = 20
	bodyL.TextWrapped = true
	bodyL.TextXAlignment = Enum.TextXAlignment.Left
	bodyL.TextYAlignment = Enum.TextYAlignment.Top
	bodyL.TextColor3 = Color3.fromRGB(245, 235, 215)
	bodyL.Parent = card
	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 12, 1, -16)
	bar.Size = UDim2.new(1, -24, 0, 6)
	bar.BackgroundColor3 = Color3.fromRGB(70, 58, 50)
	bar.BorderSizePixel = 0
	bar.Parent = card
	barFill = Instance.new("Frame")
	barFill.BackgroundColor3 = Color3.fromRGB(255, 160, 60)
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.Parent = bar
	gui.Parent = Common.player:WaitForChild("PlayerGui")
end

local function targetAtt(step)
	local function pp(machine)
		local m = Common.myMachine(machine)
		return m and m:FindFirstChild("PromptPoint", true)
	end
	if step <= 3 then
		return pp("Anvil")
	elseif step == 5 then
		return pp("Smelter")
	elseif step == 6 then
		return pp("Extractor")
	elseif step == 7 then
		local hub = Common.hub()
		local hatch = hub and hub:FindFirstChild("Hatchery")
		if hatch then
			for _, m in hatch:GetChildren() do
				if m:GetAttribute("EggId") then
					local a = m:FindFirstChild("PromptPoint", true)
					if a then
						return a
					end
				end
			end
			return hatch:FindFirstChildWhichIsA("BasePart")
		end
	end
	return nil
end

local function clearGuide()
	if beam then
		beam:Destroy()
		beam = nil
	end
	if a0 then
		a0:Destroy()
		a0 = nil
	end
	if marker then
		marker:Destroy()
		marker = nil
	end
	lastTarget = nil
end

local function updateGuide(step)
	local target = targetAtt(step)
	local char = Common.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not target or not hrp then
		clearGuide()
		return
	end
	if a0 and a0.Parent ~= hrp then
		clearGuide()
	end
	if lastTarget ~= target then
		clearGuide()
	end
	if not a0 then
		a0 = Instance.new("Attachment")
		a0.Name = "OnboardingStart"
		a0.Parent = hrp
	end
	if not marker then
		marker = Instance.new("BillboardGui")
		marker.Adornee = target
		marker.Size = UDim2.fromOffset(120, 40)
		marker.StudsOffset = Vector3.new(0, 4, 0)
		marker.AlwaysOnTop = true
		marker.MaxDistance = 1000
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.FredokaOne
		l.TextSize = 30
		l.TextColor3 = Color3.fromRGB(255, 190, 70)
		l.TextStrokeTransparency = 0.3
		l.Text = "▼ HERE"
		l.Parent = marker
		marker.Parent = Common.player.PlayerGui
		lastTarget = target
	end
	local wantBeam = Common.vfx() and (hrp.Position - target.WorldPosition).Magnitude > 14
	if wantBeam and not beam then
		beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = target
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 190, 70))
		beam.LightEmission = 1
		beam.Width0 = 0.5
		beam.Width1 = 0.5
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new(0.35)
		beam.Parent = a0
	elseif not wantBeam and beam then
		beam:Destroy()
		beam = nil
	end
end

local function stepDone(step, p)
	if step == 1 then
		local att = targetAtt(1)
		local char = Common.player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		return att and hrp and (hrp.Position - att.WorldPosition).Magnitude <= 22
	elseif step == 2 then
		return forgeStarted or p.pending ~= nil or (p.weaponsForged or 0) >= 1
	elseif step == 3 then
		return p.pending ~= nil or (p.weaponsForged or 0) >= 1
	elseif step == 4 then
		return (p.weaponsForged or 0) >= 1 and p.pending == nil
	elseif step == 5 then
		return Common.sumLevels(p) >= 1
	elseif step == 6 then
		return (p.unlockedTier or 1) >= 2
	elseif step == 7 then
		return p.pets ~= nil and #p.pets >= 1
	end
	return false
end

local function tick()
	local p = State.profile
	if not p or finished then
		return
	end
	if not gui then
		buildGui()
	end
	if (p.tutorial or 0) >= TOTAL then
		-- already complete
		finished = true
		clearGuide()
		gui:Destroy()
		return
	end
	local done = math.max(p.tutorial or 0, localDone)
	while done < TOTAL and stepDone(done + 1, p) do
		done += 1
	end
	localDone = done
	if done > reported and done > (p.tutorial or 0) then
		reported = done
		task.spawn(Net.call, "TutorialStep", done)
	end
	if done >= TOTAL then
		finished = true
		clearGuide()
		titleL.Text = "TUTORIAL COMPLETE"
		bodyL.Text = "You're a blacksmith now. Go forth and forge!"
		barFill.Size = UDim2.fromScale(1, 1)
		task.delay(4, function()
			gui:Destroy()
		end)
		return
	end
	local step = done + 1
	titleL.Text = ("OBJECTIVE  %d / %d"):format(step, TOTAL)
	bodyL.Text = TEXT[step]
	barFill.Size = UDim2.fromScale(done / TOTAL, 1)
	updateGuide(step)
end

function WorldOnboarding.start()
	Net.on("ForgePhase", function(p)
		if type(p) == "table" and p.phase == "heat" then
			forgeStarted = true
		end
	end)
	task.spawn(function()
		local ui = Common.Client:WaitForChild("UI", 10)
		local mod = ui and ui:WaitForChild("ForgeSignals", 10)
		local ok, Signals = pcall(require, mod)
		if ok and type(Signals) == "table" and Signals.Started then
			Signals.Started.Event:Connect(function()
				forgeStarted = true
			end)
		end
	end)
	while true do
		local ok, err = pcall(tick)
		if not ok then
			warn("[WorldOnboarding]", err)
		end
		if finished then
			break
		end
		task.wait(0.4)
	end
end

return WorldOnboarding
