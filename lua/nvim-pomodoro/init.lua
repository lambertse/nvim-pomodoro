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

	timer.setup(opts)
	sound.setup(opts.sound)

	vim.api.nvim_create_user_command("Pomodoro", function()
		ui.toggle()
	end, { desc = "Toggle Pomodoro popup" })

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("NvimPomodoroCleanup", { clear = true }),
		callback = function()
			require("nvim-pomodoro.timer").stop()
		end,
		desc = "Stop pomodoro timer on exit",
	})

	if opts.keymap and opts.keymap ~= "" then
		vim.keymap.set("n", opts.keymap, ui.toggle, {
			desc = "Toggle Pomodoro popup",
			silent = true,
		})
	end
end

return M
