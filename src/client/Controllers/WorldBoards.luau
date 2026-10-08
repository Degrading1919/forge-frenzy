--!nonstrict
-- Hall of Blacksmiths leaderboard screens.
local Players = game:GetService("Players")

local Common = require(script.Parent.WorldUtil.Common)
local Net = require(script.Parent.Parent.Net)

local WorldBoards = { Priority = 0 }

local ROWS = 10
local REFRESH = 30
local GOLD = Color3.fromRGB(255, 205, 60)
local SILVER = Color3.fromRGB(215, 220, 230)
local BRONZE = Color3.fromRGB(215, 135, 70)
local CREAM = Color3.fromRGB(240, 228, 205)

local boards = {} -- [model] = { metric, rows = {...}, empty = TextLabel }
local thumbs = {} -- [userId] = content string | false(pending)

local function getThumb(userId, cb)
	local c = thumbs[userId]
	if type(c) == "string" then
		cb(c)
		return
	end
	if c == false then
		task.delay(1.5, function()
			getThumb(userId, cb)
		end)
		return
	end
	thumbs[userId] = false
	task.spawn(function()
		local ok, content = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		thumbs[userId] = ok and content or ""
		if ok then
			cb(content)
		end
	end)
end

local function label(parent, pos, size, align, font, textSize)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.TextXAlignment = align
	l.Font = font
	l.TextSize = textSize
	l.TextColor3 = CREAM
	l.TextStrokeTransparency = 0.6
	l.Text = ""
	l.Parent = parent
	return l
end

local function buildBoard(model, screen)
	local old = screen:FindFirstChild("BoardGui")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = screen
	local b = { metric = model:GetAttribute("Metric"), rows = {}, gui = gui }
	local rowH = 56
	for i = 1, ROWS do
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset(15, 20 + (i - 1) * (rowH + 2))
		f.Size = UDim2.new(1, -30, 0, rowH)
		f.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
		f.BackgroundTransparency = 0.45
		f.BorderSizePixel = 0
		f.Visible = false
		f.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = f
		local rank = label(f, UDim2.fromOffset(6, 0), UDim2.fromOffset(46, rowH), Enum.TextXAlignment.Center, Enum.Font.FredokaOne, 30)
		local img = Instance.new("ImageLabel")
		img.Position = UDim2.fromOffset(56, 6)
		img.Size = UDim2.fromOffset(44, 44)
		img.BackgroundColor3 = Color3.fromRGB(50, 44, 40)
		img.Parent = f
		local ic = Instance.new("UICorner")
		ic.CornerRadius = UDim.new(1, 0)
		ic.Parent = img
		local name = label(f, UDim2.fromOffset(108, 0), UDim2.new(1, -270, 1, 0), Enum.TextXAlignment.Left, Enum.Font.GothamBold, 22)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local value = label(f, UDim2.new(1, -160, 0, 0), UDim2.fromOffset(150, rowH), Enum.TextXAlignment.Right, Enum.Font.FredokaOne, 26)
		b.rows[i] = { frame = f, rank = rank, img = img, name = name, value = value, userId = nil }
	end
	local empty = label(gui, UDim2.fromScale(0, 0.4), UDim2.fromScale(1, 0.1), Enum.TextXAlignment.Center, Enum.Font.GothamBold, 32)
	empty.Text = "No records yet"
	empty.Visible = true
	b.empty = empty
	return b
end

local function discover()
	local hub = Common.hub()
	local hall = hub and hub:FindFirstChild("HallOfBlacksmiths")
	if not hall then
		return
	end
	for _, m in hall:GetChildren() do
		if not boards[m] and m:GetAttribute("Metric") then
			local screen = m:FindFirstChild("Screen")
			if screen then
				boards[m] = buildBoard(m, screen)
			end
		end
	end
end

local function render(b, list)
	local n = 0
	if type(list) == "table" then
		n = math.min(#list, ROWS)
	end
	b.empty.Visible = n == 0
	for i = 1, ROWS do
		local r = b.rows[i]
		local e = n >= i and list[i] or nil
		r.frame.Visible = e ~= nil
		if e then
			local color = i == 1 and GOLD or i == 2 and SILVER or i == 3 and BRONZE or CREAM
			r.rank.Text = tostring(i)
			r.rank.TextColor3 = color
			r.name.Text = tostring(e.name or e.displayName or e.userId or "?")
			r.name.TextColor3 = color
			r.value.Text = Common.abbrev(tonumber(e.value) or 0)
			r.value.TextColor3 = color
			r.frame.BackgroundColor3 = i <= 3 and color:Lerp(Color3.fromRGB(20, 16, 14), 0.8) or Color3.fromRGB(20, 16, 14)
			local uid = e.userId
			if r.userId ~= uid then
				r.userId = uid
				r.img.Image = ""
				if type(uid) == "number" and uid > 0 then
					getThumb(uid, function(content)
						if r.userId == uid then
							r.img.Image = content
						end
					end)
				end
			end
		else
			r.userId = nil
		end
	end
end

local function refresh()
	discover()
	local ok, data = Net.call("Leaderboards")
	if not ok or type(data) ~= "table" then
		return
	end
	for _, b in boards do
		render(b, data[b.metric])
	end
end

function WorldBoards.start()
	task.wait(2)
	while true do
		local ok, err = pcall(refresh)
		if not ok then
			warn("[WorldBoards]", err)
		end
		task.wait(REFRESH)
	end
end

return WorldBoards
