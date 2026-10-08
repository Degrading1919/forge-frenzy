--!nonstrict
--[[
	Workshop machines in motion (v2, docs/21 §7-10). Client-only presentation.

	Every workshop: drills spin while mining, ore chunks ride the raised belt up and drop into
	the smelter, glowing ingots ride the output belt into the vault, ore gems take the color of
	the metal each line mines, and red lasers seal a workshop while its Forge Lock is on.
	Your workshop also gets big billboards: what each forge is doing (with a countdown), what
	each drill mines, build pad prices, cash waiting in the collector and the lock timer.
]]
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Common = require(script.Parent.WorldUtil.Common)
local State = Common.State
local UI = Common.Client.UI
local Theme = require(UI.Theme)
local Data = require(UI.Data)
local Format = require(UI.Format)

local WorldMachines = { Priority = 0 }
local C = Theme.Colors

local plotsState = {} -- [plot] = { visual, lines = { [i] = { acc } }, lockedVisible }
local movers = {} -- moving ore/ingot parts
local pool = {}
local billboards = {} -- [key] = gui
local phaseInfo = {} -- [station] = ForgePhase push

local function decodeVisual(plot)
	local raw = plot:GetAttribute("VisualState")
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, res = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and res or nil
end

local function takePart(): BasePart
	local p = table.remove(pool)
	if not p then
		p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
	end
	p.Parent = Common.fxFolder()
	return p
end

local function givePart(p: BasePart)
	p.Parent = nil
	if #pool < 120 then
		table.insert(pool, p)
	else
		p:Destroy()
	end
end

-- Spawns an item that travels a -> b over `duration`, then optionally drops `fall` studs.
local function launch(a: Vector3, b: Vector3, duration: number, color: Color3, size: Vector3, neon: boolean, fall: number?)
	if #movers > 150 then return end
	local p = takePart()
	p.Size = size
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.Slate
	p.CFrame = CFrame.new(a)
	table.insert(movers, { part = p, a = a, b = b, t = 0, d = duration, fall = fall or 0 })
end

local function billboard(key: string, adornee: Instance, size: Vector2, offset: Vector3, maxDistance: number?)
	local gui = billboards[key]
	if gui and gui.Parent and gui.Adornee == adornee then
		return gui
	end
	if gui then gui:Destroy() end
	gui = Instance.new("BillboardGui")
	gui.Name = "FF_" .. key
	gui.Adornee = adornee
	-- Sized in studs so labels stay in proportion to the world instead of covering the screen.
	gui.Size = UDim2.new(size.X / 30, 0, size.Y / 30, 0)
	gui.StudsOffset = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance or 90
	gui.LightInfluence = 0
	local label = Theme.text({ Name = "Text", Text = "", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.panelDark, BackgroundTransparency = 0.1, Corner = 14, Stroke = { Color = C.ink, Thickness = 3 }, TextScaled = true, Parent = gui })
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = label
	gui.Parent = Common.player:WaitForChild("PlayerGui")
	billboards[key] = gui
	return gui
end

local function setBoard(key: string, text: string, color: Color3?)
	local gui = billboards[key]
	if gui then
		gui.Text.Text = text
		gui.Text.BackgroundColor3 = color or C.panelDark
	end
end

local function dropBoard(key: string)
	if billboards[key] then
		billboards[key]:Destroy()
		billboards[key] = nil
	end
end

-- Per-plot animation ------------------------------------------------------------------------

local function stepPlot(plot: Instance, dt: number, now: number)
	local st = plotsState[plot]
	if not st then
		st = { lines = {}, lasersOn = nil }
		plotsState[plot] = st
	end
	local owned = (plot:GetAttribute("OwnerUserId") or 0) ~= 0
	local visual = if owned then decodeVisual(plot) else nil
	local machines = plot:FindFirstChild("Machines")
	if machines then
		for _, model in machines:GetChildren() do
			local index = model:GetAttribute("LineIndex")
			if index then
				local m = visual and visual.lines and visual.lines[index]
				local drill = model:FindFirstChild("Drill")
				local smelter = model:FindFirstChild("Smelter")
				local belt = model:FindFirstChild("OreBelt")
				local out = model:FindFirstChild("OutBelt")
				local color = if m then Data.mat(m).color else C.grey
				local gem = drill and drill:FindFirstChild("OreGem")
				if gem and gem.Color ~= color then
					gem.Color = color
				end
				local bit = drill and drill:FindFirstChild("DrillBit")
				if bit and m then
					bit.CFrame = bit.CFrame * CFrame.Angles(dt * 8, 0, 0)
				end
				if m and belt and out and smelter then
					local ls = st.lines[index] or { acc = math.random() }
					st.lines[index] = ls
					local rate = math.clamp((visual.rates and visual.rates.orePerSec or 0.3), 0.2, 1.5)
					ls.acc += dt * rate
					if ls.acc >= 1 then
						ls.acc -= 1
						local a = belt.BeltStart.WorldPosition
						local b = belt.BeltEnd.WorldPosition
						launch(a, b, 1.6, color, Vector3.new(0.9, 0.9, 0.9), false, 2.2)
						task.delay(2.2, function()
							if out.Parent then
								launch(out.BeltStart.WorldPosition, out.BeltEnd.WorldPosition, 1.8, color, Vector3.new(1.3, 0.45, 0.7), true, 0)
							end
						end)
					end
				end
			end
		end
	end
	-- Forge Lock lasers (everyone sees them).
	local lockedUntil = plot:GetAttribute("LockedUntil") or 0
	local locked = lockedUntil > now
	local lasers = plot:FindFirstChild("Lasers")
	if lasers then
		if locked then
			local flicker = 0.15 + 0.1 * math.sin(now * 10)
			for _, laser in lasers:GetChildren() do
				laser.Transparency = flicker
			end
		elseif st.lasersOn ~= false then
			for _, laser in lasers:GetChildren() do
				laser.Transparency = 1
			end
		end
		st.lasersOn = locked
	end
end

-- Your workshop's billboards -------------------------------------------------------------

local function forgeText(index: number, p: any, now: number): (string, Color3)
	local st = p.forgeStatus and p.forgeStatus[index]
	local info = phaseInfo[index]
	local recipe = p.stations and p.stations[index]
	local name = if recipe then (Data.mat(recipe.m).name .. " " .. Data.ClassNames[recipe.c]) else ""
	if st and st.auto then
		local remain = math.max(0, ((info and info.endsAt) or st.endsAt or 0) - now)
		local phase = (info and info.phase) or st.phase
		if st.waiting or phase == "waiting" then
			return "AUTO ⏳ waiting for ingots", C.orange
		elseif phase == "heat" then
			return string.format("AUTO 🔥 %.1fs\n%s", remain, name), Theme.shade(C.green, -0.3)
		elseif phase == "strike" then
			return string.format("AUTO 🔨 %.1fs\n%s", remain, name), Theme.shade(C.green, -0.3)
		end
		return "AUTO 💧\n" .. name, Theme.shade(C.green, -0.3)
	end
	if info and info.mode == "manual" and (info.phase == "heat" or info.phase == "strike") then
		return "🔨 HAMMERING!", C.orange
	end
	return "READY! Walk up & forge\n" .. name, C.blue
end

local function updateMine(now: number)
	local p = State.profile
	local plot = Common.myPlot()
	if not p or not plot then return end
	local machines = plot:FindFirstChild("Machines")
	if machines then
		for _, model in machines:GetChildren() do
			local forgeIndex = model:GetAttribute("ForgeIndex")
			local lineIndex = model:GetAttribute("LineIndex")
			if forgeIndex and p.stations and p.stations[forgeIndex] then
				local key = "forge" .. forgeIndex
				billboard(key, model:FindFirstChild("Base") or model.PrimaryPart, Vector2.new(210, 66), Vector3.new(0, 12, 0), 120)
				local text, color = forgeText(forgeIndex, p, now)
				setBoard(key, text, color)
			elseif lineIndex and p.lines and p.lines[lineIndex] then
				local drill = model:FindFirstChild("Drill")
				if drill then
					local key = "line" .. lineIndex
					billboard(key, drill:FindFirstChild("Base") or drill.PrimaryPart, Vector2.new(170, 44), Vector3.new(0, 17, 0), 120)
					local m = p.lines[lineIndex].m
					setBoard(key, string.format("⛏️ %s  %s", Data.mat(m).name, Format.rate(math.min(p.rates.orePerSec, p.rates.ingotPerSec))), Theme.shade(Data.mat(m).color, -0.45))
				end
			end
		end
	end
	-- Build pads in view.
	local pads = plot:FindFirstChild("BuildPads")
	local seen = {}
	if pads then
		local cfg = Common.config("BuildPads")
		for _, pad in pads:GetChildren() do
			local padId = pad:GetAttribute("PadId")
			local def = cfg and cfg.ById and padId and cfg.ById[padId]
			if def then
				local key = "pad" .. padId
				seen[key] = true
				billboard(key, pad, Vector2.new(170, 58), Vector3.new(0, 4, 0), 90)
				local afford = (p.coins or 0) >= def.cost
				setBoard(key, string.format("🏗️ %s\n%s", def.name, Theme.money(def.cost)), if afford then Theme.shade(C.green, -0.25) else C.panelDark)
				pad.Transparency = 0.15 + 0.2 * (0.5 + 0.5 * math.sin(now * 3))
			end
		end
	end
	for key in billboards do
		if key:sub(1, 3) == "pad" and not seen[key] then
			dropBoard(key)
		end
	end
	-- Collector.
	local collector = plot:FindFirstChild("Collector")
	if collector then
		billboard("collector", collector, Vector2.new(140, 50), Vector3.new(0, 5, 0), 120)
		local bank = p.bank or 0
		if (p.incomePerSec or 0) > 0 then
			bank += 0 -- server value; the collector shows what is waiting
		end
		setBoard("collector", string.format("💰 %s\nstep here!", Theme.money(bank)), if bank >= 1 then Theme.shade(C.green, -0.2) else C.panelDark)
	end
	-- Lock button.
	local lock = plot:FindFirstChild("LockButton")
	if lock then
		billboard("lock", lock, Vector2.new(150, 44), Vector3.new(0, 7, 0), 120)
		local lockedUntil = plot:GetAttribute("LockedUntil") or 0
		local nextLock = plot:GetAttribute("NextLockAt") or 0
		if lockedUntil > now then
			setBoard("lock", string.format("🔒 LOCKED %ds", math.ceil(lockedUntil - now)), C.red)
		elseif nextLock > now then
			setBoard("lock", string.format("Recharging %ds", math.ceil(nextLock - now)), C.grey)
		else
			setBoard("lock", "🔒 LOCK FORGE", Theme.shade(C.red, -0.2))
		end
	end
	-- Vault bins board.
	local storage = machines and machines:FindFirstChild("Storage")
	local board = storage and storage:FindFirstChild("BinBoard")
	local gui = board and board:FindFirstChild("Bins")
	if gui then
		local label = gui:FindFirstChild("Text")
		if not label then
			label = Theme.text({ Name = "Text", Size = UDim2.new(1, 0, 1, 0), TextScaled = true, Parent = gui })
		end
		local parts = {}
		local fullest = 0
		for m = p.unlockedTier or 1, 1, -1 do
			local n = p.ingots and p.ingots[m] or 0
			if n > 0 and #parts < 3 then
				table.insert(parts, string.format("%s %s", Data.mat(m).name, Theme.abbr(n)))
			end
			fullest = math.max(fullest, n / math.max(1, p.rates.capacity))
		end
		label.Text = if #parts > 0 then table.concat(parts, "  ·  ") else "EMPTY"
		local fill = storage:FindFirstChild("Fill")
		if fill then
			local h = math.max(0.05, (fill:GetAttribute("MaxHeight") or 4) * math.clamp(fullest, 0, 1))
			local base = fill:GetAttribute("BaseY")
			if not base then
				base = fill.Position.Y - fill.Size.Y / 2
				fill:SetAttribute("BaseY", base)
			end
			fill.Size = Vector3.new(fill.Size.X, h, fill.Size.Z)
			fill.CFrame = fill.CFrame - fill.CFrame.Position + Vector3.new(fill.Position.X, base + h / 2, fill.Position.Z)
		end
	end
end

local function step(dt: number)
	local now = workspace:GetServerTimeNow()
	-- Movers.
	for i = #movers, 1, -1 do
		local mv = movers[i]
		mv.t += dt
		local f = mv.t / mv.d
		if f >= 1 then
			if mv.fall > 0 and f < 1 + 0.35 / mv.d then
				local fallT = (mv.t - mv.d) / 0.35
				mv.part.CFrame = CFrame.new(mv.b - Vector3.new(0, mv.fall * fallT * fallT, 0))
			else
				givePart(mv.part)
				table.remove(movers, i)
			end
		else
			local pos = mv.a:Lerp(mv.b, f)
			mv.part.CFrame = CFrame.lookAt(pos, mv.b) * CFrame.Angles(0, mv.t * 3, 0)
		end
	end
end

local acc = 0
function WorldMachines.start()
	local Net = require(Common.Client.Net)
	Net.on("ForgePhase", function(info)
		if type(info) == "table" and info.station then
			phaseInfo[info.station] = info
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		step(dt)
		acc += dt
		if acc < 0.1 then return end
		local frame = acc
		acc = 0
		local now = workspace:GetServerTimeNow()
		local plots = Common.plotsFolder()
		if plots then
			for _, plot in plots:GetChildren() do
				local ok, err = pcall(stepPlot, plot, frame, now)
				if not ok then
					warn("[WorldMachines]", err)
				end
			end
		end
		local ok, err = pcall(updateMine, now)
		if not ok then
			warn("[WorldMachines] mine", err)
		end
	end)
end

return WorldMachines
