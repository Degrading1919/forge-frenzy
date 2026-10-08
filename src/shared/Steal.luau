--!strict
--[[
	Steal — the shared rules for how long stealing a displayed weapon takes.

	The client uses this to show the right hold time on the steal prompt; the server uses the same
	function to time and enforce the hold, so the two can never disagree, and the server's copy
	is the only one that counts.

	Hold time grows with the weapon's value on a log10 scale, because values run from about $20
	to tens of quadrillions. It is rounded to half seconds so it reads simply on screen:

	  value      hold      what it usually is
	  <= $1K     2.0 s     starter weapons
	  $30K       2.5 s     a Gold greatsword
	  $1M        3.5 s     mid game
	  $100M      4.5 s     Adamantite
	  $100B      5.5 s     late game
	  $1T        6.0 s     late game
	  $1Qa       7.5 s     Primordium
	  >= $10Qa   8.0 s     the very best endgame weapons
]]

local Steal = {}

Steal.MIN_HOLD_SEC = 2
Steal.MAX_HOLD_SEC = 8
-- log10 of the value that takes the minimum hold, and of the value that takes the maximum.
Steal.LOW_LOG10 = 3
Steal.HIGH_LOG10 = 16
Steal.STEP_SEC = 0.5

-- Seconds a thief must hold the steal prompt for a weapon worth `value`.
function Steal.holdSeconds(value: any): number
	local v = if type(value) == "number" and value == value and value > 0 then value else 1
	local t = math.clamp((math.log10(v) - Steal.LOW_LOG10) / (Steal.HIGH_LOG10 - Steal.LOW_LOG10), 0, 1)
	local raw = Steal.MIN_HOLD_SEC + t * (Steal.MAX_HOLD_SEC - Steal.MIN_HOLD_SEC)
	local rounded = math.floor(raw / Steal.STEP_SEC + 0.5) * Steal.STEP_SEC
	return math.clamp(rounded, Steal.MIN_HOLD_SEC, Steal.MAX_HOLD_SEC)
end

return Steal
