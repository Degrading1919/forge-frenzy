--!nonstrict
-- Number / time formatting.
local Format = {}

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1234 -> "1.23K"; handles up to ~1e36.
function Format.abbr(n: number?): string
	n = n or 0
	if n ~= n then return "0" end
	local neg = n < 0
	n = math.abs(n)
	if n < 1000 then
		return (neg and "-" or "") .. tostring(math.floor(n + 0.5))
	end
	local i = math.min(math.floor(math.log10(n) / 3), #SUFFIX - 1)
	local v = n / 10 ^ (i * 3)
	if v >= 999.5 and i < #SUFFIX - 1 then
		i += 1
		v = n / 10 ^ (i * 3)
	end
	local s
	if v >= 100 then
		s = string.format("%.0f", v)
	elseif v >= 10 then
		s = string.format("%.1f", v)
	else
		s = string.format("%.2f", v)
	end
	if s:find("%.") then
		s = s:gsub("0+$", ""):gsub("%.$", "")
	end
	return (neg and "-" or "") .. s .. SUFFIX[i + 1]
end

function Format.commas(n: number?): string
	local s = tostring(math.floor((n or 0) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return out
end

function Format.pct(x: number, decimals: number?): string
	return string.format("%." .. (decimals or 3) .. "f%%", x * 100)
end

function Format.rate(perSec: number?): string
	local perMin = (perSec or 0) * 60
	if perMin >= 100 then return Format.abbr(perMin) end
	return string.format("%.1f", perMin)
end

function Format.clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

return Format
