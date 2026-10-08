--!nonstrict
-- Client-side forge events for other controllers (e.g. world/anvil effects).
-- Each signal supports both styles:  ForgeSignals.Hit:Connect(fn)   and   ForgeSignals.Hit.Event:Connect(fn)
--   Started(sessionInfo)  sessionInfo = { sessionId, heatSec, windowSec, revealSec, mode, classIndex, materialIndex }
--   Hit()                 one valid hammer strike (manual mode, local)
--   Result(weapon, luck)  server result for a forge (manual or auto)
--   Phase(phase)          "heat" | "strike" | "quench" | "done" | "cancelled" (local manual minigame)
local function newSignal()
	local be = Instance.new("BindableEvent")
	local s = { Event = be.Event }
	function s:Connect(fn)
		return be.Event:Connect(fn)
	end
	function s:Fire(...)
		be:Fire(...)
	end
	function s:Wait()
		return be.Event:Wait()
	end
	return s
end

return {
	Started = newSignal(),
	Hit = newSignal(),
	Result = newSignal(),
	Phase = newSignal(),
}
