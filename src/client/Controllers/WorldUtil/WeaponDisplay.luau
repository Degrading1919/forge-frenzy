--!nonstrict
-- Builds an inert, upright, size-normalised weapon visual from a weapon-like entry { c, d, r, t, m, q? }.
local Common = require(script.Parent.Common)

local WeaponDisplay = {}

function WeaponDisplay.displayName(e)
	local row = Common.materialRow(e.m)
	local parts = {}
	if e.q and Common.CraftNames[e.q] then
		table.insert(parts, Common.CraftNames[e.q])
	end
	if e.t and e.t ~= "" then
		table.insert(parts, tostring(e.t))
	end
	table.insert(parts, row and row.name or ("Material " .. tostring(e.m or "?")))
	table.insert(parts, Common.ClassNames[e.c] or "Weapon")
	return table.concat(parts, " ")
end

-- Returns (instance, fixCFrame). Caller parents it and uses
-- inst:PivotTo(CFrame.new(pos) * CFrame.Angles(0, spin, 0) * fix).
function WeaponDisplay.build(e, targetSize)
	local skin = Common.skin(e.m)
	local inst = nil
	local WM = Common.shared({ "Visuals", "WeaponModels" })
	if WM and WM.build then
		local ok, r = pcall(WM.build, e.c, e.d, e.r, skin, e.t)
		if ok and typeof(r) == "Instance" then
			inst = r
		end
	end
	if not inst then
		local p = Instance.new("Part")
		p.Name = "WeaponFallback"
		p.Size = Vector3.new(0.5, targetSize, 0.25)
		p.Color = skin.color or Color3.fromRGB(180, 180, 190)
		p.Material = Enum.Material.Metal
		inst = p
	end
	Common.inert(inst)
	local ext
	if inst:IsA("Model") then
		ext = inst:GetExtentsSize()
		local maxDim = math.max(ext.X, ext.Y, ext.Z, 0.01)
		pcall(function()
			inst:ScaleTo(inst:GetScale() * targetSize / maxDim)
		end)
		ext = inst:GetExtentsSize()
	else
		ext = inst.Size
	end
	local fix = CFrame.identity
	if ext.Z > ext.Y * 1.2 and ext.Z >= ext.X then
		fix = CFrame.Angles(-math.pi / 2, 0, 0)
	elseif ext.X > ext.Y * 1.2 and ext.X > ext.Z then
		fix = CFrame.Angles(0, 0, math.pi / 2)
	end
	return inst, fix
end

return WeaponDisplay
