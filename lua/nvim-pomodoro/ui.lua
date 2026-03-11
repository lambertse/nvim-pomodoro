-- nvim-pomodoro/ui.lua
-- Owns the floating window and keymaps for this nvim session only.
-- Timer mutations are sent via IPC so both server and client go through
-- the same path. Rendering is always driven by on_remote_state(), which is
-- called both by the IPC client callback AND by the server's own on_tick.

local M = {}

local timer = require("nvim-pomodoro.timer")
local notify = require("nvim-pomodoro.notify")

local SESSION = timer.SESSION

local TABS = {
	{ id = SESSION.FOCUS, label = "🍅 Focus" },
	{ id = SESSION.SHORT_BREAK, label = "☕ Short Break" },
	{ id = SESSION.LONG_BREAK, label = "🛌 Long Break" },
}

local HINTS = {
	"[Tab] Next Mode",
	"[S-Tab] Prev Mode",
	"[s] Start/Pause",
	"[r] Restart",
	"[q] Detach",
	"[x] Close",
}

local WIDTH = 125
local HEIGHT = 20

local state = {
	buf = nil,
	win = nil,
	backdrop_buf = nil,
	backdrop_win = nil,
	active = SESSION.FOCUS,
	detached = false,
}

-- ── big digit font ────────────────────────────────────────────────────────────

local BIG_DIGITS = {
	["0"] = { "█▀▀█", "█  █", "█  █", "█  █", "█▄▄█" },
	["1"] = { "▀█ ", " █ ", " █ ", " █ ", "▄█▄" },
	["2"] = { "█▀▀█", "   █", "▄▄▄█", "█   ", "█▄▄▄" },
	["3"] = { "█▀▀█", "   █", " ▀▀█", "   █", "█▄▄█" },
	["4"] = { "█  █", "█  █", "█▄▄█", "   █", "   █" },
	["5"] = { "█▀▀▀", "█   ", "▀▀▀█", "   █", "█▄▄█" },
	["6"] = { "█▀▀▀", "█   ", "█▀▀█", "█  █", "█▄▄█" },
	["7"] = { "█▀▀█", "   █", "  █ ", " █  ", " █  " },
	["8"] = { "█▀▀█", "█  █", "█▀▀█", "█  █", "█▄▄█" },
	["9"] = { "█▀▀█", "█  █", "█▄▄█", "   █", "█▄▄█" },
	[":"] = { "   ", " ▪ ", "   ", " ▪ ", "   " },
}

local BIG_DIGIT_ROWS = 5
local BIG_DIGIT_GAP = 1

local function big_clock_lines(time_str, width)
	local rows = {}
	for r = 1, BIG_DIGIT_ROWS do
		rows[r] = ""
	end

	for i = 1, #time_str do
		local ch = time_str:sub(i, i)
		local glyph = BIG_DIGITS[ch] or BIG_DIGITS["0"]
		for r = 1, BIG_DIGIT_ROWS do
			if i > 1 then
				rows[r] = rows[r] .. string.rep(" ", BIG_DIGIT_GAP)
			end
			rows[r] = rows[r] .. glyph[r]
		end
	end

	local result = {}
	for r = 1, BIG_DIGIT_ROWS do
		local dw = vim.fn.strdisplaywidth(rows[r])
		local pad = math.floor((width - dw) / 2)
		result[r] = string.rep(" ", math.max(pad, 0)) .. rows[r]
	end
	return result
end

-- ── helpers ───────────────────────────────────────────────────────────────────

local function fmt_time(secs)
	return string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
end

local function is_open()
	if state.win ~= nil and vim.api.nvim_win_is_valid(state.win) then
		return true
	end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local ok, ft = pcall(vim.api.nvim_buf_get_option, buf, "filetype")
		if ok and ft == "pomodoro" then
			state.win = win
			state.buf = buf
			return true
		end
	end
	return false
end

local function space_around(items, width)
	local n = #items
	local total_len = 0
	for _, item in ipairs(items) do
		total_len = total_len + vim.fn.strdisplaywidth(item)
	end
	local slot = (width - total_len) / n
	local left_pad = math.floor(slot / 2)
	local right_pad = math.floor(slot - left_pad)

	local result = ""
	for i, item in ipairs(items) do
		result = result .. string.rep(" ", left_pad) .. item .. string.rep(" ", right_pad)
		if i == n then
			local actual = vim.fn.strdisplaywidth(result)
			if actual < width then
				result = result .. string.rep(" ", width - actual)
			end
		end
	end
	return result
end

local function open_backdrop()
	local ui = vim.api.nvim_list_uis()[1]
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = ui.width,
		height = ui.height,
		row = 0,
		col = 0,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 40,
	})
	vim.api.nvim_set_hl(0, "PomodoroBackdrop", { bg = "#0a0a0f", blend = 30 })
	vim.api.nvim_win_set_option(win, "winhighlight", "Normal:PomodoroBackdrop")
	vim.api.nvim_win_set_option(win, "winblend", 90)
	return buf, win
end

-- ── IPC command helper ────────────────────────────────────────────────────────

local function send(action, payload)
	local ok, ipc = pcall(require, "nvim-pomodoro.ipc")
	if ok then
		ipc.send_command(action, payload)
	end
end

-- ── rendering ─────────────────────────────────────────────────────────────────

local function render()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local tab_items = {}
	for _, tab in ipairs(TABS) do
		if tab.id == state.active then
			table.insert(tab_items, "[ " .. tab.label .. " ]")
		else
			table.insert(tab_items, "  " .. tab.label .. "  ")
		end
	end

	local clock = fmt_time(timer.seconds_left())
	local status = timer.is_running() and "▶  Running" or "⏸  Paused"
	local status_pad = math.floor((WIDTH - vim.fn.strdisplaywidth(status)) / 2)
	local big = big_clock_lines(clock, WIDTH)

	local lines = {
		string.rep("─", WIDTH), -- [1]  row 0
		space_around(tab_items, WIDTH), -- [2]  row 1
		string.rep("─", WIDTH), -- [3]  row 2
		"",
		"",
		big[1],
		big[2],
		big[3],
		big[4],
		big[5],
		"",
		string.rep(" ", status_pad) .. status, -- [12] row 11
		"",
		"",
		"",
		"",
		"",
		space_around(HINTS, WIDTH), -- [18] row 17
		string.rep("─", WIDTH), -- [19] row 18
		"",
	}

	vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(state.buf, "modifiable", false)

	local ns = vim.api.nvim_create_namespace("pomodoro_hl")
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

	-- Tab bar
	local col = 0
	for _, tab in ipairs(TABS) do
		local is_active = tab.id == state.active
		local raw_label = is_active and ("[ " .. tab.label .. " ]") or ("  " .. tab.label .. "  ")
		local byte_len = #raw_label

		local n, total_len = #TABS, 0
		for _, t in ipairs(TABS) do
			total_len = total_len
				+ vim.fn.strdisplaywidth(
					(t.id == state.active) and ("[ " .. t.label .. " ]") or ("  " .. t.label .. "  ")
				)
		end
		local slot = (WIDTH - total_len) / n
		local left_pad = math.floor(slot / 2)
		if col == 0 then
			col = left_pad
		end

		local hl
		if is_active then
			if tab.id == SESSION.FOCUS then
				hl = "PomodoroTabFocus"
			elseif tab.id == SESSION.SHORT_BREAK then
				hl = "PomodoroTabShort"
			else
				hl = "PomodoroTabLong"
			end
		else
			hl = "PomodoroTabInactive"
		end

		vim.api.nvim_buf_add_highlight(state.buf, ns, hl, 1, col, col + byte_len)
		col = col + byte_len + left_pad + math.floor(slot - left_pad)
	end

	-- Dividers
	for _, row in ipairs({ 0, 2, 18 }) do
		vim.api.nvim_buf_add_highlight(state.buf, ns, "PomorodoDivider", row, 0, -1)
	end

	-- Clock colour
	local palette = { "#a6e3a1", "#f38ba8" }
	local tick_idx = (timer.seconds_left() < 55) and 2 or 1
	vim.api.nvim_set_hl(0, "PomodoroClockPulse", { fg = palette[tick_idx], bold = true })
	for r = 5, 9 do
		vim.api.nvim_buf_add_highlight(state.buf, ns, "PomodoroClockPulse", r, 0, -1)
	end

	-- Status
	local status_str = timer.is_running() and "▶  Running" or "⏸  Paused"
	local status_hl = timer.is_running() and "PomodoroRunning" or "PomorodoPaused"
	local status_scol = math.floor((WIDTH - vim.fn.strdisplaywidth(status_str)) / 2)
	vim.api.nvim_buf_add_highlight(state.buf, ns, status_hl, 11, status_scol, status_scol + #status_str)

	-- Hints
	local hint_line = lines[18]
	local search_from = 0
	for _, hint in ipairs(HINTS) do
		local s = hint_line:find(hint, search_from + 1, true)
		if s then
			local key_start = s - 1
			local key_end = key_start + #hint:match("%[.-%]")
			local label_end = key_start + #hint
			vim.api.nvim_buf_add_highlight(state.buf, ns, "PomodoroHintKey", 17, key_start, key_end)
			vim.api.nvim_buf_add_highlight(state.buf, ns, "PomodoroHintLabel", 17, key_end, label_end)
			search_from = s + #hint - 1
		end
	end
end

-- ── window management ─────────────────────────────────────────────────────────

function M._open_win()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local ok, ft = pcall(vim.api.nvim_buf_get_option, buf, "filetype")
		if ok and ft == "pomodoro" and win ~= state.win then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end

	if is_open() then
		return
	end

	state.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(state.buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(state.buf, "filetype", "pomodoro")

	local ui = vim.api.nvim_list_uis()[1]
	local row = math.floor((ui.height - HEIGHT) / 2)
	local col = math.floor((ui.width - WIDTH) / 2)

	state.backdrop_buf, state.backdrop_win = open_backdrop()
	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		width = WIDTH,
		height = HEIGHT,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " 🍅 Pomodoro ",
		title_pos = "center",
	})

	vim.api.nvim_win_set_option(state.win, "wrap", false)
	vim.api.nvim_win_set_option(state.win, "cursorline", false)

	vim.api.nvim_set_hl(0, "PomodoroTabActive", { fg = "#1e1e2e", bg = "#cba6f7", bold = true })
	vim.api.nvim_set_hl(0, "PomodoroTabInactive", { fg = "#585b70", bold = false })
	vim.api.nvim_set_hl(0, "PomodoroTabFocus", { fg = "#1e1e2e", bg = "#f38ba8", bold = true })
	vim.api.nvim_set_hl(0, "PomodoroTabShort", { fg = "#1e1e2e", bg = "#a6e3a1", bold = true })
	vim.api.nvim_set_hl(0, "PomodoroTabLong", { fg = "#1e1e2e", bg = "#74c7ec", bold = true })
	vim.api.nvim_set_hl(0, "PomodoroClockPulse", { fg = "#cba6f7", bold = true })
	vim.api.nvim_set_hl(0, "PomodoroRunning", { fg = "#a6e3a1", bold = true })
	vim.api.nvim_set_hl(0, "PomorodoPaused", { fg = "#fab387", bold = false })
	vim.api.nvim_set_hl(0, "PomodoroHintKey", { fg = "#cba6f7", bold = true })
	vim.api.nvim_set_hl(0, "PomodoroHintLabel", { fg = "#9399b2", bold = false })
	vim.api.nvim_set_hl(0, "PomorodoDivider", { fg = "#313244" })

	local o = { noremap = true, silent = true, nowait = true, buffer = state.buf }
	local tab_order = { SESSION.FOCUS, SESSION.SHORT_BREAK, SESSION.LONG_BREAK }

	local function index_of(session)
		for i, s in ipairs(tab_order) do
			if s == session then
				return i
			end
		end
		return 1
	end

	vim.keymap.set("n", "1", function()
		send("switch_session", { session = SESSION.FOCUS })
		state.active = SESSION.FOCUS
		render()
	end, o)

	vim.keymap.set("n", "2", function()
		send("switch_session", { session = SESSION.SHORT_BREAK })
		state.active = SESSION.SHORT_BREAK
		render()
	end, o)

	vim.keymap.set("n", "3", function()
		send("switch_session", { session = SESSION.LONG_BREAK })
		state.active = SESSION.LONG_BREAK
		render()
	end, o)

	vim.keymap.set("n", "<Tab>", function()
		local nxt = tab_order[(index_of(state.active) % #tab_order) + 1]
		send("switch_session", { session = nxt })
		state.active = nxt
		render()
	end, o)

	vim.keymap.set("n", "<S-Tab>", function()
		local prev = tab_order[((index_of(state.active) - 2) % #tab_order) + 1]
		send("switch_session", { session = prev })
		state.active = prev
		render()
	end, o)

	vim.keymap.set("n", "r", function()
		send("switch_session", { session = state.active })
		render()
	end, o)

	-- Toggle start / pause — just send the intent; the server's on_tick
	-- will call on_remote_state() which calls render() every second.
	vim.keymap.set("n", "s", function()
		if timer.is_running() then
			send("pause")
		else
			send("start")
		end
		-- render() will be called by on_remote_state on the very next tick;
		-- call it once immediately so the status line flips without delay.
		render()
	end, o)

	vim.keymap.set("n", "q", M.detach, o)
	vim.keymap.set("n", "<Esc>", M.detach, o)
	vim.keymap.set("n", "x", M.close, o)

	render()
end

-- ── public API ────────────────────────────────────────────────────────────────

function M.close()
	if state.backdrop_win and vim.api.nvim_win_is_valid(state.backdrop_win) then
		vim.api.nvim_win_close(state.backdrop_win, true)
	end
	state.backdrop_win = nil
	state.backdrop_buf = nil

	send("stop")
	if is_open() then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
	state.detached = false
end

function M.detach()
	if state.backdrop_win and vim.api.nvim_win_is_valid(state.backdrop_win) then
		vim.api.nvim_win_close(state.backdrop_win, true)
	end
	state.backdrop_win = nil
	state.backdrop_buf = nil

	if is_open() then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
	state.detached = true
	vim.notify("Pomodoro timer is running in the background.", vim.log.levels.INFO, { title = "Pomodoro" })
end

function M.toggle()
	if is_open() then
		M.detach()
		return
	end
	state.active = timer.current_session()
	state.detached = false
	M._open_win()
end

--- Called every tick — both by IPC client callback AND by the server's own
--- on_tick (via init.lua). This is the SINGLE place that drives render().
function M.on_remote_state(s)
	timer.apply_remote_state(s)
	state.active = s.session
	if is_open() then
		render()
	elseif state.detached and not s.running then
		-- Session ended while detached → re-open the window
		state.detached = false
		M._open_win()
	end
end

return M
