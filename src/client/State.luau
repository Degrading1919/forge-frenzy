--!strict
-- Latest server profile snapshot plus a change signal. Read-only on the client.
local State = {}
State.profile = nil :: any
local listeners: { (any) -> () } = {}

function State.init(Net: any)
	Net.on("Profile", function(p)
		-- The server omits the weapon list when it has not changed since the last snapshot.
		if p.weapons == nil then
			p.weapons = if State.profile then State.profile.weapons else {}
		end
		State.profile = p
		for _, fn in listeners do
			task.spawn(fn, p)
		end
	end)
end

-- Calls fn now (if a profile exists) and on every update. Returns a disconnect function.
function State.observe(fn: (any) -> ()): () -> ()
	table.insert(listeners, fn)
	if State.profile then
		task.spawn(fn, State.profile)
	end
	return function()
		local i = table.find(listeners, fn)
		if i then table.remove(listeners, i) end
	end
end

function State.wait(): any
	while not State.profile do
		task.wait()
	end
	return State.profile
end

return State
