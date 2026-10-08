--!nonstrict
--[[
	Kit — shared widgets for the station panels: material tiles, weapon tiles, upgrade rows with
	"current -> next" effects, and a safe action caller that toasts friendly errors.
]]
local Net = require(script.Parent.Parent.Net)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)
local Data = require(script.Parent.Data)
local Toast = require(script.Parent.Toast)

local Kit = {}
local C = Theme.Colors

Kit.ClassOrder = { 4, 1, 3, 5, 2 } -- smallest to largest
Kit.ClassIcons = { "🗡️", "⚔️", "🪓", "🔪", "🔨" }
Kit.RarityShort = { "Common", "Uncommon", "Rare", "Epic", "Legend", "Mythic" }

-- Calls a server action; shows the friendly error on failure. Returns (ok, result).
function Kit.call(action: string, ...: any): (boolean, any)
	local ok, res = Net.call(action, ...)
	if not ok and res and res ~= "Slow down" then
		Toast.show(tostring(res), "bad")
	end
	return ok, res
end

function Kit.balance(): any
	return Data.config("Balance")
end

-- The shared economy rules, so the client shows exactly what the server pays.
function Kit.economy(): any?
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("Economy")
	if not module then return nil end
	local ok, Economy = pcall(require, module)
	return if ok then Economy else nil
end

-- What weapon `w` sells for right now (a stolen weapon is capped by your progression).
function Kit.usableValue(p: any, w: any): number
	local Economy = Kit.economy()
	if not Economy or not p then return w.v end
	local ok, value = pcall(Economy.usableValue, p, w, p.cashMult or 1)
	return if ok then value else w.v
end

-- What weapon `w` earns per second on a podium, exactly as the server pays it.
function Kit.displayIncome(p: any, w: any): number
	local Economy = Kit.economy()
	if not Economy or not p then return 0 end
	local ok, value = pcall(Economy.displayIncome, p, w, p.cashMult or 1)
	return if ok then value else 0
end

function Kit.recipe(classIndex: number): number
	local B = Kit.balance()
	local class = B and B.weaponClasses[classIndex]
	return class and class.ingots or 1
end

function Kit.classMult(classIndex: number): number
	local B = Kit.balance()
	local class = B and B.weaponClasses[classIndex]
	return class and class.valueMult or 1
end

-- Weapon value range for a material/class at the player's cash multiplier.
function Kit.valueRange(m: number, c: number): (number, number)
	local mat = Data.mat(m)
	local mult = (State.profile and State.profile.cashMult) or 1
	local k = Kit.classMult(c) * mult
	return mat.priceMin * k * 1.01, mat.priceMax * k * 0.99
end

-- A chunky ingot icon (colored bar) for a material.
function Kit.ingotIcon(parent: Instance, m: number, size: number?, props: { [string]: any }?): Frame
	local mat = Data.mat(m)
	local s = size or 44
	local p = props and table.clone(props) or {}
	p.Size = p.Size or UDim2.fromOffset(s, s * 0.6)
	p.BackgroundColor3 = mat.color
	p.Corner = math.floor(s * 0.15)
	p.Stroke = { Color = C.ink, Thickness = 2.5 }
	p.Gradient = { Theme.shade(mat.color, 0.45), Theme.shade(mat.color, -0.25) }
	p.Parent = parent
	local icon = Theme.make("Frame", p)
	if mat.glow then
		Theme.make("UIStroke", { Color = mat.accent or mat.color, Thickness = 3, Transparency = 0.2, Parent = icon })
	end
	return icon
end

-- Text for an upgrade effect at a level: "+15% Ore Speed", "+10 Storage", "-0.1 sec Heat".
function Kit.effectText(track: string, level: number): string
	local B = Kit.balance()
	local def = B and B.tracks[track]
	if not def then return track end
	local v = def.effectPerLevel * level
	if def.unit == "pct" then
		return string.format("+%d%% %s", math.floor(v * 100 + 0.5), def.label)
	elseif def.unit == "flat" then
		return string.format("+%d %s", math.floor(v + 0.5), def.label)
	elseif def.unit == "sec" then
		return string.format("-%.2g sec %s", v, def.label)
	elseif def.unit == "chance" then
		return string.format("%d%% %s", math.floor(v * 100 + 0.5), def.label)
	end
	return tostring(v)
end

-- Per-level step as a short headline: "+15% Ore Speed".
function Kit.stepText(track: string): string
	return Kit.effectText(track, 1)
end

--[[
	Upgrade row: icon tile, name + level, "now -> next" line, and a big buy button with the price.
	`describe(level)` optionally returns the human value at a level (e.g. "2.0 ore/s").
	Returns a refresh function to call with the latest profile.
]]
function Kit.upgradeRow(parent: Instance, order: number, track: string, icon: string, color: Color3, describe: ((number) -> string)?): (any) -> ()
	local B = Kit.balance()
	local def = B and B.tracks[track]
	local row = Theme.card({
		Name = "Upgrade_" .. track,
		LayoutOrder = order,
		Size = UDim2.new(1, -6, 0, 104),
		BackgroundColor3 = Theme.shade(color, -0.35),
		Parent = parent,
	})
	Theme.text({
		Text = icon,
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.fromOffset(10, 18),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		Corner = 14,
		Stroke = { Color = C.ink, Thickness = 3 },
		TextSize = 36,
		Parent = row,
	})
	local name = Theme.text({
		Text = def and def.name or track,
		Position = UDim2.fromOffset(84, 6),
		Size = UDim2.new(1, -250, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 26,
		Parent = row,
	})
	local effect = Theme.text({
		Text = "",
		Position = UDim2.fromOffset(84, 38),
		Size = UDim2.new(1, -250, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.yellow,
		TextSize = 22,
		Parent = row,
	})
	local now = Theme.text({
		Text = "",
		Position = UDim2.fromOffset(84, 66),
		Size = UDim2.new(1, -250, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.dim,
		TextSize = 19,
		Parent = row,
	})
	local buy = Theme.button({
		Text = "",
		Color = C.green,
		Size = UDim2.fromOffset(150, 70),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, -2),
		TextSize = 26,
		OnClick = function()
			local ok = Kit.call("BuyUpgrade", track)
			if ok then
				Theme.pop(row, 0.92)
			end
		end,
		Parent = row,
	})
	return function(p: any)
		local level = if def and def.kind == "gear" then (p.gear and p.gear[track] or 0) else (p.levels and p.levels[track] or 0)
		local cost = p.costs and p.costs.upgrades and p.costs.upgrades[track]
		name.Text = string.format("%s  Lv %d", def and def.name or track, level)
		if cost then
			effect.Text = Kit.stepText(track) .. " per level"
			if describe then
				now.Text = describe(level) .. "  →  " .. describe(level + 1)
			else
				now.Text = "Now " .. Kit.effectText(track, level) .. "  →  " .. Kit.effectText(track, level + 1)
			end
			Theme.setText(buy, Theme.money(cost))
			Theme.setEnabled(buy, (p.coins or 0) >= cost)
		else
			effect.Text = "MAXED!"
			now.Text = "Now " .. Kit.effectText(track, level)
			Theme.setText(buy, "MAX")
			Theme.setEnabled(buy, false)
		end
	end
end

-- Weapon card color helpers.
function Kit.weaponTitle(w: any): string
	return string.format("%s %s", Data.mat(w.m).name, Data.ClassNames[w.c] or "Weapon")
end

-- A compact weapon card (no 3D viewport, so long lists stay fast). Returns the button.
function Kit.weaponCard(parent: Instance, w: any, order: number, onClick: (() -> ())?, badge: string?): TextButton
	local color = Theme.rarityColor(w.r)
	local card = Instance.new("TextButton")
	card.Name = "Weapon_" .. tostring(w.id)
	card.LayoutOrder = order
	card.Text = ""
	card.AutoButtonColor = false
	card.BackgroundColor3 = Theme.shade(color, -0.45)
	card.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	Theme.text({ Text = Kit.ClassIcons[w.c] or "⚔️", Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 6), TextSize = 40, Parent = card })
	Kit.ingotIcon(card, w.m, 26, { Position = UDim2.fromOffset(8, 8) })
	Theme.text({ Text = Data.mat(w.m).name .. " " .. (Data.ClassNames[w.c] or ""), Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 58), TextScaled = true, Parent = card })
	Theme.text({ Text = Theme.money(w.v), Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(4, 80), TextSize = 22, TextColor3 = C.cash, Parent = card })
	Theme.text({ Text = Kit.RarityShort[w.r] or "", Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 106), TextSize = 17, TextColor3 = color, Parent = card })
	if badge then
		Theme.chip(badge, C.purple, { Size = UDim2.fromOffset(74, 24), Position = UDim2.new(1, -4, 0, 4), AnchorPoint = Vector2.new(1, 0), TextSize = 15, Parent = card })
	end
	if onClick then
		card.Activated:Connect(onClick)
	end
	card.Parent = parent
	return card
end

return Kit
