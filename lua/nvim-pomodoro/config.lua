local M = {}

M.defaults = {
	focus_time = 25, -- minutes
	break_time = 5, -- minutes
	long_break_time = 15, -- minutes
	cycles_before_long_break = 4,
	keymap = "<leader>p",
	-- Sound configuration
	sound = {
		enabled = true,
		volume = 0.7, -- 0.0 to 1.0
		backend = "auto",
		events = {
			start = true,
			done = true,
			milestone = true,
			tick = false, -- off by default, can be noisy
			urgent = true,
		},
		files = {
			start = nil, -- nil = use bundled default
			done = nil,
			milestone = nil,
			tick = nil,
			urgent = nil,
		},
	},
}

function M.merge(user_opts)
	return vim.tbl_deep_extend("force", M.defaults, user_opts or {})
end

return M
