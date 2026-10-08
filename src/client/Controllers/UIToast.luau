--!nonstrict
-- Creates the ScreenGui early and routes Push Toast / Announce to the Toast module.
local Net = require(script.Parent.Parent.Net)
local Panels = require(script.Parent.Parent.UI.Panels)
local Toast = require(script.Parent.Parent.UI.Toast)

local M = { Priority = 100 }

function M.init()
	Panels.gui()
	Net.on("Toast", function(p)
		if type(p) == "table" then
			Toast.show(p.text or "", p.kind)
		elseif p then
			Toast.show(tostring(p), "info")
		end
	end)
	Net.on("Announce", function(p)
		if type(p) == "table" then
			Toast.announce(p.text or "", p.rarity)
		end
	end)
end

return M
