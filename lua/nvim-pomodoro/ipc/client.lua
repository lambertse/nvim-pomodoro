local M = {}

local uv = vim.loop
local json = vim.json

-- ── state ────────────────────────────────────────────────────────────────────

local pipe = nil -- uv_pipe_t
local _on_state = nil -- function(state_tbl)  called on every broadcast
local _on_disconnect = nil -- function()           called when server dies

-- ── helpers ──────────────────────────────────────────────────────────────────

local function encode(msg)
	return json.encode(msg) .. "\n"
end

-- ── public API ───────────────────────────────────────────────────────────────

--- Connect to the server at `socket_path`.
--- `on_state(tbl)`      – called whenever a state broadcast arrives.
--- `on_disconnect()`    – called when the connection drops (server exited).
function M.connect(socket_path, on_state, on_disconnect)
	if pipe then
		return
	end

	_on_state = on_state
	_on_disconnect = on_disconnect

	pipe = uv.new_pipe(false)
	pipe:connect(socket_path, function(err)
		if err then
			pipe = nil
			if _on_disconnect then
				vim.schedule(_on_disconnect)
			end
			return
		end

		local buf = ""
		pipe:read_start(vim.schedule_wrap(function(read_err, data)
			if read_err or not data then
				-- Server went away
				pipe = nil
				if _on_disconnect then
					_on_disconnect()
				end
				return
			end

			buf = buf .. data
			for line in buf:gmatch("([^\n]+)\n") do
				buf = buf:gsub(vim.pesc(line) .. "\n", "", 1)
				local ok, tbl = pcall(json.decode, line)
				if ok and tbl and _on_state then
					_on_state(tbl)
				end
			end
		end))
	end)
end

--- Send a command to the server (e.g. start, pause, stop, switch_session).
function M.send(action, payload)
	if not pipe or pipe:is_closing() then
		return
	end
	local msg = vim.tbl_extend("force", { action = action }, payload or {})
	pipe:write(encode(msg))
end

--- Gracefully close the client connection.
function M.disconnect()
	if pipe and not pipe:is_closing() then
		pipe:close()
	end
	pipe = nil
end

function M.is_connected()
	return pipe ~= nil and not pipe:is_closing()
end

return M
