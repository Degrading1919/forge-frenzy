--!nonstrict
-- Number / time formatting. Cash always carries a dollar sign (docs/21 §2).
local Theme = require(script.Parent.Theme)

local Format = {}

Format.abbr = Theme.abbr
Format.money = Theme.money

function Format.commas(n: number?): string
	local s = tostring(math.floor((n or 0) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return out
end

function Format.pct(x: number, decimals: number?): string
	local value = x * 100
	if decimals == nil then
		if value >= 10 then
			return string.format("%.0f%%", value)
		elseif value >= 1 then
			return string.format("%.1f%%", value)
		elseif value >= 0.1 then
			return string.format("%.2f%%", value)
		end
		return string.format("%.3f%%", value)
	end
	return string.format("%." .. decimals .. "f%%", value)
end

-- "2.4/s" or "45/min" whichever reads better for a kid.
function Format.rate(perSec: number?): string
	perSec = perSec or 0
	if perSec >= 1 then
		return string.format("%.1f/s", perSec)
	end
	return string.format("%d/min", math.floor(perSec * 60 + 0.5))
end

function Format.clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

function Format.seconds(sec: number): string
	if sec >= 60 then
		return Format.clock(sec)
	end
	return string.format("%.1fs", math.max(0, sec))
end

return Format
