local M = {}

M.SESSION = {
	FOCUS = 1,
	SHORT_BREAK = 2,
	LONG_BREAK = 3,
}

local state = {
	session = M.SESSION.FOCUS,
	seconds_left = 0,
	cycle = 0,
	running = false,
	handle = nil,
	opts = {},
	on_tick = nil,
	on_done = nil,
	notified = {},
}

local MILESTONES = {
	{ secs = 300, msg = "⏳ 5 minutes left!" },
	{ secs = 120, msg = "⏰ 2 minutes left!" },
	{ secs = 60, msg = "⚡ 1 minute left!" },
	{ secs = 30, msg = "🔔 30 seconds left!" },
	{ secs = 10, msg = "⏱️ 10 seconds left!" },
}

local session_labels = {
	[M.SESSION.FOCUS] = "🍅 Focus",
	[M.SESSION.SHORT_BREAK] = "☕ Short Break",
	[M.SESSION.LONG_BREAK] = "🛌 Long Break",
}

-- Sound notifications for milestones (5 min, 2 min, 1 min, 30 sec, 10 sec)
local sound = require("nvim-pomodoro.sound")

local function notify_milestone(secs)
	for _, m in ipairs(MILESTONES) do
		if secs == m.secs and not state.notified[m.secs] then
			state.notified[m.secs] = true
			sound.play("milestone")
			vim.notify(
				string.format("%s — %s", session_labels[state.session] or "Session", m.msg),
				vim.log.levels.WARN,
				{
					title = "Pomodoro",
					timeout = 8000,
				}
			)
		end
	end
end

-- ── helpers ────────────────────────────────────────────────────────────────

local function session_duration(session, opts)
	if session == M.SESSION.FOCUS then
		return opts.focus_time * 60
	end
	if session == M.SESSION.SHORT_BREAK then
		return opts.break_time * 60
	end
	if session == M.SESSION.LONG_BREAK then
		return opts.long_break_time * 60
	end
end

local function next_session()
	if state.session == M.SESSION.FOCUS then
		state.cycle = state.cycle + 1
		if state.cycle >= state.opts.cycles_before_long_break then
			state.cycle = 0
			return M.SESSION.LONG_BREAK
		end
		return M.SESSION.SHORT_BREAK
	end
	return M.SESSION.FOCUS
end

local function stop_handle()
	if state.handle then
		state.handle:stop()
		state.handle:close()
		state.handle = nil
	end
end

-- ── public API ─────────────────────────────────────────────────────────────

function M.setup(opts)
	state.opts = opts
	state.session = M.SESSION.FOCUS
	state.seconds_left = session_duration(M.SESSION.FOCUS, opts)
	state.cycle = 0
	state.running = false
	state.on_tick = nil
	state.on_done = nil
	state.notified = {}
	stop_handle()
end

function M.start(on_tick, on_done)
	if state.running then
		return
	end

	-- Kill any orphaned handle from a previous load
	stop_handle()
	sound.play("start")

	state.on_tick = on_tick
	state.on_done = on_done
	state.running = true

	state.handle = vim.loop.new_timer()
	state.handle:start(
		0,
		1000,
		vim.schedule_wrap(function()
			if not state.running then
				return
			end

			if state.on_tick then
				state.on_tick(state.session, state.seconds_left)
			end

			notify_milestone(state.seconds_left)
			if state.seconds_left >= 10 then
				sound.play("tick")
			else
				sound.play("urgent")
			end

			if state.seconds_left <= 0 then
				sound.play("done")
				local finished = state.session
				local nxt = next_session()
				state.session = nxt
				state.seconds_left = session_duration(nxt, state.opts)

				if state.on_done then
					state.on_done(finished, nxt)
				end
				state.running = false
				stop_handle()
				return
			end

			state.seconds_left = state.seconds_left - 1
		end)
	)
end

function M.pause()
	if not state.running then
		return
	end
	state.running = false
	stop_handle()
end

function M.resume()
	if state.running then
		return
	end
	if not state.on_tick or not state.on_done then
		return
	end
	M.start(state.on_tick, state.on_done)
end

function M.stop()
	state.running = false
	state.on_tick = nil
	state.on_done = nil
	stop_handle()
	-- Stop any in-flight tick sound
	local b = require("nvim-pomodoro.sound.backend.macos")
	pcall(b.stop_tick)
end

function M.is_running()
	return state.running
end

function M.current_session()
	return state.session
end

function M.seconds_left()
	return state.seconds_left
end

function M.switch_session(session)
	M.stop()
	state.session = session
	state.seconds_left = session_duration(session, state.opts)
	state.notified = {}
end

return M
