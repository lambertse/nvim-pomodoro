local M = {}

function M.setup(user_opts)
	if M._initialized then
		return
	end
	M._initialized = true

	local config = require("nvim-pomodoro.config")
	local opts = config.merge(user_opts)

	local timer = require("nvim-pomodoro.timer")
	local ui = require("nvim-pomodoro.ui")
	local sound = require("nvim-pomodoro.sound")
	local ipc = require("nvim-pomodoro.ipc")

	sound.setup(opts.sound)

	-- ── IPC setup ────────────────────────────────────────────────────────────
	ipc.setup({
		-- Called in CLIENT instances when a state broadcast arrives.
		on_state = function(state_tbl)
			if state_tbl.type == "state" then
				ui.on_remote_state(state_tbl)
			end
		end,

		-- Called when THIS instance becomes (or remains) the server.
		on_promote = function()
			timer.setup(opts)

			local server = require("nvim-pomodoro.ipc.server")

			local function server_on_tick(session, seconds_left)
				ui.on_remote_state({
					type = "state",
					session = session,
					seconds_left = seconds_left,
					running = true,
					cycle = 0,
				})
			end

			local function server_on_done(finished, nxt)
				require("nvim-pomodoro.notify").session_ended(finished, nxt)
				ui.on_remote_state({
					type = "state",
					session = nxt,
					seconds_left = timer.seconds_left(),
					running = false,
					cycle = 0,
				})
			end

			server._dispatch = function(cmd)
				if cmd.action == "start" then
					timer.start(server_on_tick, server_on_done)
				elseif cmd.action == "pause" then
					timer.pause()
				elseif cmd.action == "resume" then
					if timer.is_running() then
						return
					end
					timer.start(server_on_tick, server_on_done)
				elseif cmd.action == "stop" then
					timer.stop()
				elseif cmd.action == "switch_session" and cmd.session then
					timer.switch_session(cmd.session)
				end
			end
		end,
	})

	-- ── user-facing commands & keymaps ───────────────────────────────────────
	vim.api.nvim_create_user_command("Pomodoro", function()
		ui.toggle()
	end, { desc = "Toggle Pomodoro popup" })

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("NvimPomodoroCleanup", { clear = true }),
		callback = function()
			ipc.shutdown()
		end,
		desc = "Shutdown pomodoro IPC on exit",
	})

	if opts.keymap and opts.keymap ~= "" then
		vim.keymap.set("n", opts.keymap, ui.toggle, {
			desc = "Toggle Pomodoro popup",
			silent = true,
		})
	end
end 

return M
