local M = {}

local uv = vim.loop
local server = require("nvim-pomodoro.ipc.server")
local client = require("nvim-pomodoro.ipc.client")
local type = require("nvim-pomodoro.ipc.type")

-- ── config ───────────────────────────────────────────────────────────────────

local SOCKET_PATH = type.socket_path() -- nil on type until TODO is done

-- ── role tracking ────────────────────────────────────────────────────────────

M._role = nil
M._on_state = nil
M._on_promote = nil

-- ── helpers ──────────────────────────────────────────────────────────────────

local function socket_exists()
	if not SOCKET_PATH then
		return false
	end
	return uv.fs_stat(SOCKET_PATH) ~= nil
end

local function try_remove_socket()
	if SOCKET_PATH then
		pcall(uv.fs_unlink, SOCKET_PATH)
	end
end

-- ── server role ──────────────────────────────────────────────────────────────

local function become_server()
	try_remove_socket()
	local ok = server.start(SOCKET_PATH)
	if not ok then
		return false
	end
	M._role = "server"
	if M._on_promote then
		M._on_promote()
	end
	return true
end

-- ── client role ──────────────────────────────────────────────────────────────

local function become_client()
	M._role = "client"
	client.connect(SOCKET_PATH, function(state_tbl)
		if M._on_state then
			M._on_state(state_tbl)
		end
	end, function()
		M._role = nil
		vim.defer_fn(function()
			M.setup(M._opts)
		end, 200)
	end)
end

-- ── public API ───────────────────────────────────────────────────────────────

M._opts = {}

function M.setup(opts)
	M._opts = opts or {}
	M._on_state = M._opts.on_state
	M._on_promote = M._opts.on_promote

	-- IPC not supported on this platform → always act as a standalone server
	if not type.supported() then
		M._role = "server"
		if M._on_promote then
			M._on_promote()
		end
		return
	end

	if socket_exists() then
		become_client()
	else
		become_server()
	end
end

function M.broadcast(state_tbl)
	if M._role == "server" then
		server.broadcast(state_tbl)
	end
end

function M.send_command(action, payload)
	if M._role == "server" then
		server._dispatch(vim.tbl_extend("force", { action = action }, payload or {}))
	elseif M._role == "client" then
		client.send(action, payload)
	end
end

function M.is_server()
	return M._role == "server"
end
function M.is_client()
	return M._role == "client"
end

function M.shutdown()
	if M._role == "server" then
		server.stop()
		try_remove_socket()
	elseif M._role == "client" then
		client.disconnect()
	end
	M._role = nil
end

return M
