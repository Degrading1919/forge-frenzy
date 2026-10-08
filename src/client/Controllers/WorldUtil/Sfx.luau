--!nonstrict
-- Sound playback with placeholder ids. The integrator fills Sfx.ids with verified Roblox audio ids
-- (e.g. "rbxassetid://123456"). Empty id = silently skipped.
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local State = require(script.Parent.Parent.Parent.State)

local Sfx = {}

Sfx.ids = {
	hammer_hit = "",
	heat = "",
	quench = "",
	reveal_common = "",
	reveal_rare = "",
	reveal_legendary = "",
	coin = "",
	upgrade = "",
	hatch = "",
	evolve = "",
	click = "",
	music_workshop = "",
}

Sfx.volumes = {
	hammer_hit = 0.7, heat = 0.5, quench = 0.7, reveal_common = 0.6, reveal_rare = 0.8,
	reveal_legendary = 1, coin = 0.5, upgrade = 0.6, hatch = 0.8, evolve = 0.9, click = 0.4,
	music_workshop = 0.25,
}

local function settingOn(key)
	local p = State.profile
	return not (p and p.settings and p.settings[key] == false)
end

-- target: Instance (BasePart/Attachment, 3D) | Vector3 (3D at position) | nil (2D)
function Sfx.play(name, target)
	local id = Sfx.ids[name]
	if not id or id == "" or not settingOn("sfx") then
		return
	end
	local parent = SoundService
	local temp = nil
	if typeof(target) == "Instance" then
		parent = target
	elseif typeof(target) == "Vector3" then
		local att = Instance.new("Attachment")
		att.WorldPosition = target
		att.Parent = Workspace.Terrain
		parent, temp = att, att
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = Sfx.volumes[name] or 0.6
	s.RollOffMaxDistance = 90
	s.Parent = parent
	s.Ended:Once(function()
		s:Destroy()
		if temp then
			temp:Destroy()
		end
	end)
	Debris:AddItem(temp or s, 20)
	s:Play()
end

local music = nil
function Sfx.startMusic()
	local id = Sfx.ids.music_workshop
	if not id or id == "" or music then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "WorldMusic"
	s.SoundId = id
	s.Looped = true
	s.Volume = Sfx.volumes.music_workshop
	s.Parent = SoundService
	music = s
	State.observe(function()
		if music then
			music.Playing = settingOn("music")
		end
	end)
	s.Playing = settingOn("music")
end

return Sfx
