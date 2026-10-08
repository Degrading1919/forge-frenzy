--!nonstrict
-- One-time "Your workshop" billboard, optional initial camera orientation, music and a few event sounds.
local Workspace = game:GetService("Workspace")

local Common = require(script.Parent.WorldUtil.Common)
local Sfx = require(script.Parent.WorldUtil.Sfx)
local Net = require(script.Parent.Parent.Net)
local State = Common.State

local WorldOwner = { Priority = -1 }

local shown = false
local lastLevels = nil

local function showBillboard(plot)
	local sign = plot:FindFirstChild("SignBoard")
	if not sign then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "YourWorkshop"
	gui.Adornee = sign
	gui.Size = UDim2.fromOffset(260, 56)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 400
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = Color3.fromRGB(40, 28, 20)
	l.BackgroundTransparency = 0.2
	l.Font = Enum.Font.FredokaOne
	l.TextSize = 28
	l.TextColor3 = Color3.fromRGB(255, 200, 90)
	l.Text = "Your workshop"
	l.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = l
	gui.Parent = Common.player:WaitForChild("PlayerGui")
	task.spawn(function()
		local t0 = os.clock()
		while gui.Parent and os.clock() - t0 < 25 do
			local char = Common.player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - sign.Position).Magnitude < 18 then
				break
			end
			task.wait(0.5)
		end
		gui:Destroy()
	end)
end

local function faceCamera(plot)
	local cam = Workspace.CurrentCamera
	local char = Common.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (cam and hrp) then
		return
	end
	local target = plot:GetPivot().Position
	local dir = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)
	if dir.Magnitude < 5 then
		return
	end
	dir = dir.Unit
	local pos = hrp.Position - dir * 14 + Vector3.new(0, 7, 0)
	cam.CFrame = CFrame.lookAt(pos, target + Vector3.new(0, 6, 0))
end

local function onProfile(profile)
	local sum = Common.sumLevels(profile)
	if lastLevels and sum > lastLevels then
		Sfx.play("upgrade")
	end
	lastLevels = sum
	if shown then
		return
	end
	local plot = Common.myPlot()
	if not plot then
		return
	end
	shown = true
	pcall(showBillboard, plot)
	task.delay(1.5, function()
		pcall(faceCamera, plot)
	end)
end

function WorldOwner.start()
	Sfx.startMusic()
	Net.on("Hatched", function()
		Sfx.play("hatch")
	end)
	Net.on("Evolved", function()
		Sfx.play("evolve")
	end)
	State.observe(onProfile)
end

return WorldOwner
