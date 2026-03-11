local M = {}

local uv = vim.loop
local json = vim.json

-- ── helpers ─────────────────────────────────────────────────────────────────

local function encode(msg)
	return json.encode(msg) .. "\n"
end

-- ── state ────────────────────────────────────────────────────────────────────

local server_handle = nil 
local clients = {} 

-- ── broadcast ────────────────────────────────────────────────────────────────

--- Send a message to every connected client, dropping dead ones.
function M.broadcast(msg)
	local payload = encode(msg)
	local alive = {}
	for _, client in ipairs(clients) do
		if client and not client:is_closing() then
			client:write(payload)
			alive[#alive + 1] = client
		end
	end
	clients = alive
end

-- ── client handling ──────────────────────────────────────────────────────────

local function on_client_connect(client_pipe)
	clients[#clients + 1] = client_pipe

	-- Buffer for incomplete lines
	local buf = ""

	client_pipe:read_start(vim.schedule_wrap(function(err, data)
		if err or not data then
			client_pipe:close()
			return
		end

		buf = buf .. data
		-- Commands are newline-delimited JSON
		for line in buf:gmatch("([^\n]+)\n") do
			buf = buf:gsub(vim.pesc(line) .. "\n", "", 1)
			local ok, cmd = pcall(json.decode, line)
			if ok and cmd and cmd.action then
				M._dispatch(cmd)
			end
		end
	end))
end

-- ── command dispatch (clients → server) ──────────────────────────────────────

--- Override this from init.lua to forward commands to the real timer.
--- Signature: function(cmd)  where cmd = { action = "start"|"pause"|... }
M._dispatch = function(_cmd) end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function M.start(socket_path)
	if server_handle then
		return
	end

	server_handle = uv.new_pipe(false)
	local ok, err = server_handle:bind(socket_path)
	if not ok then
		vim.notify("[pomodoro] server bind failed: " .. tostring(err), vim.log.levels.ERROR)
		server_handle:close()
		server_handle = nil
		return false
	end

	server_handle:listen(128, function(listen_err)
		if listen_err then
			return
		end
		local client = uv.new_pipe(false)
		server_handle:accept(client)
		on_client_connect(client)
	end)

	return true
end

--- Stop the server and close all client connections.
function M.stop()
	for _, c in ipairs(clients) do
		if not c:is_closing() then
			c:close()
		end
	end
	clients = {}

	if server_handle and not server_handle:is_closing() then
		server_handle:close()
	end
	server_handle = nil
end

function M.is_running()
	return server_handle ~= nil
end

return M
