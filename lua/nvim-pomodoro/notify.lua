local M = {}
local timer = require("nvim-pomodoro.timer")

local labels = {
	[timer.SESSION.FOCUS] = "🍅 Focus",
	[timer.SESSION.SHORT_BREAK] = "☕ Short Break",
	[timer.SESSION.LONG_BREAK] = "🛌 Long Break",
}

function M.session_ended(finished_session, next_session)
	local msg = string.format(
		"%s session ended!  Starting %s.",
		labels[finished_session] or "Session",
		labels[next_session] or "next session"
	)
	vim.notify(msg, vim.log.levels.INFO, { title = "Pomodoro" }, { timeout = 5000 })
end

return M
