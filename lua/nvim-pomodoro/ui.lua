local M = {}

local timer  = require("nvim-pomodoro.timer")
local notify = require("nvim-pomodoro.notify")

local SESSION = timer.SESSION

local TABS = {
  { id = SESSION.FOCUS,       label = "🍅 Focus"       },
  { id = SESSION.SHORT_BREAK, label = "☕ Short Break" },
  { id = SESSION.LONG_BREAK,  label = "🛌 Long Break"  },
}

local HINTS = {
  "[Tab] Next Mode",
  "[S-Tab] Prev Mode",
  "[s] Start/Pause",
  "[r] Restart",
  "[q] Detach",
  "[x] Close",
}

local WIDTH  = 125
local HEIGHT = 20

local state = {
  buf      = nil,
  win      = nil,
  active   = SESSION.FOCUS,
  detached = false,
}

-- ── big digit font (5 rows × variable width) ──────────────────────────────
local BIG_DIGITS = {
  ["0"] = { "█▀▀█", "█  █", "█  █", "█  █", "█▄▄█" },
  ["1"] = { "▀█ ",  " █ ",  " █ ",  " █ ",  "▄█▄"  },
  ["2"] = { "█▀▀█", "   █", "▄▄▄█", "█   ", "█▄▄▄" },
  ["3"] = { "█▀▀█", "   █", " ▀▀█", "   █", "█▄▄█" },
  ["4"] = { "█  █", "█  █", "█▄▄█", "   █", "   █" },
  ["5"] = { "█▀▀▀", "█   ", "▀▀▀█", "   █", "█▄▄█" },
  ["6"] = { "█▀▀▀", "█   ", "█▀▀█", "█  █", "█▄▄█" },
  ["7"] = { "█▀▀█", "   █", "  █ ", " █  ", " █  " },
  ["8"] = { "█▀▀█", "█  █", "█▀▀█", "█  █", "█▄▄█" },
  ["9"] = { "█▀▀█", "█  █", "█▄▄█", "   █", "█▄▄█" },
  [":"] = { "   ",  " ▪ ",  "   ",  " ▪ ",  "   "  },
}

local BIG_DIGIT_ROWS = 5
local BIG_DIGIT_GAP  = 1

local function big_clock_lines(time_str, width)
  local rows = {}
  for r = 1, BIG_DIGIT_ROWS do
    rows[r] = ""
  end

  for i = 1, #time_str do
    local ch    = time_str:sub(i, i)
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
    local dw  = vim.fn.strdisplaywidth(rows[r])
    local pad = math.floor((width - dw) / 2)
    result[r] = string.rep(" ", math.max(pad, 0)) .. rows[r]
  end
  return result
end

-- ── helpers ────────────────────────────────────────────────────────────────

local function fmt_time(secs)
  return string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
end

local function is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

local function space_around(items, width)
  local n         = #items
  local total_len = 0
  for _, item in ipairs(items) do
    total_len = total_len + vim.fn.strdisplaywidth(item)
  end

  local total_space = width - total_len
  local slot        = total_space / n
  local left_pad    = math.floor(slot / 2)
  local right_pad   = math.floor(slot - left_pad)

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

-- ── rendering ──────────────────────────────────────────────────────────────

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

  local tab_items = {}
  for _, tab in ipairs(TABS) do
    if tab.id == state.active then
      table.insert(tab_items, "[ " .. tab.label .. " ]")
    else
      table.insert(tab_items, "  " .. tab.label .. "  ")
    end
  end

  local clock      = fmt_time(timer.seconds_left())
  local status     = timer.is_running() and "▶  Running" or "⏸  Paused"
  local status_pad = math.floor((WIDTH - vim.fn.strdisplaywidth(status)) / 2)
  local big        = big_clock_lines(clock, WIDTH)

  local lines = {
    string.rep("─", WIDTH),                        -- [1]  row 0  : top divider
    space_around(tab_items, WIDTH),                 -- [2]  row 1  : tab bar
    string.rep("─", WIDTH),                        -- [3]  row 2  : mid divider
    "",                                             -- [4]  row 3  : padding
    "",                                             -- [5]  row 4  : padding
    big[1],                                         -- [6]  row 5  : clock line 1
    big[2],                                         -- [7]  row 6  : clock line 2
    big[3],                                         -- [8]  row 7  : clock line 3
    big[4],                                         -- [9]  row 8  : clock line 4
    big[5],                                         -- [10] row 9  : clock line 5
    "",                                             -- [11] row 10 : padding
    string.rep(" ", status_pad) .. status,          -- [12] row 11 : status
    "",                                             -- [13] row 12 : padding
    "",                                             -- [14] row 13 : padding
    "",                                             -- [15] row 14 : padding
    "",                                             -- [16] row 15 : padding
    "",                                             -- [17] row 16 : padding
    space_around(HINTS, WIDTH),                     -- [18] row 17 : hint bar
    string.rep("─", WIDTH),                        -- [19] row 18 : bottom divider
    "",                                             -- [20] row 19
  }

  vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)

  -- ── highlights ────────────────────────────────────────────────────────

  local ns = vim.api.nvim_create_namespace("pomodoro_hl")
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

  -- Tab bar: row 1 — highlight each tab individually
  local col = 0
  for _, tab in ipairs(TABS) do
    local is_active = tab.id == state.active
    local raw_label = is_active
      and ("[ " .. tab.label .. " ]")
      or  ("  " .. tab.label .. "  ")
    local byte_len  = #raw_label

    local n         = #TABS
    local total_len = 0
    for _, t in ipairs(TABS) do
      total_len = total_len + vim.fn.strdisplaywidth(
        (t.id == state.active)
          and ("[ " .. t.label .. " ]")
          or  ("  " .. t.label .. "  ")
      )
    end
    local slot     = (WIDTH - total_len) / n
    local left_pad = math.floor(slot / 2)
    if col == 0 then col = left_pad end

    local hl
    if is_active then
      if     tab.id == SESSION.FOCUS       then hl = "PomodoroTabFocus"
      elseif tab.id == SESSION.SHORT_BREAK then hl = "PomodoroTabShort"
      else                                      hl = "PomodoroTabLong"
      end
    else
      hl = "PomodoroTabInactive"
    end

    vim.api.nvim_buf_add_highlight(state.buf, ns, hl, 1, col, col + byte_len)
    col = col + byte_len + left_pad + math.floor(slot - left_pad)
  end

  -- Divider lines: rows 0, 2, 18
  for _, row in ipairs({ 0, 2, 18 }) do
    vim.api.nvim_buf_add_highlight(state.buf, ns, "PomorodoDivider", row, 0, -1)
  end

  -- Animated clock: colour cycles through palette each second
  local palette = {
    -- "#cba6f7",  -- mauve
    -- "#89b4fa",  -- blue
    -- "#74c7ec",  -- sapphire
    "#a6e3a1",  -- green
    -- "#f9e2af",  -- yellow
    -- "#fab387",  -- peach
    "#f38ba8",  -- red
  }
  -- If the second left less than 30, return red. Then use mause
  local tick_idx = 1 
  if timer.seconds_left() < 55 then
    tick_idx = 2
  end

  vim.api.nvim_set_hl(0, "PomodoroClockPulse", { fg = palette[tick_idx], bold = true })

  -- Highlight all 5 big-digit rows (rows 5–9, 0-indexed)
  for r = 5, 9 do
    vim.api.nvim_buf_add_highlight(state.buf, ns, "PomodoroClockPulse", r, 0, -1)
  end

  -- Status: row 11
  local status_str  = timer.is_running() and "▶  Running" or "⏸  Paused"
  local status_hl   = timer.is_running() and "PomodoroRunning" or "PomorodoPaused"
  local status_scol = math.floor((WIDTH - vim.fn.strdisplaywidth(status_str)) / 2)
  vim.api.nvim_buf_add_highlight(state.buf, ns, status_hl, 11, status_scol, status_scol + #status_str)

  -- Hint bar: row 17 — colour [key] and label separately
  local hint_row    = 17
  local hint_line   = lines[18]
  local search_from = 0
  for _, hint in ipairs(HINTS) do
    local s = hint_line:find(hint, search_from + 1, true)
    if s then
      local key_start = s - 1
      local key_end   = key_start + #hint:match("%[.-%]")
      local label_end = key_start + #hint
      vim.api.nvim_buf_add_highlight(state.buf, ns, "PomodoroHintKey",   hint_row, key_start, key_end)
      vim.api.nvim_buf_add_highlight(state.buf, ns, "PomodoroHintLabel", hint_row, key_end,   label_end)
      search_from = s + #hint - 1
    end
  end
end

-- ── session handlers ───────────────────────────────────────────────────────

local function on_done(finished, nxt)
  notify.session_ended(finished, nxt)
  state.active = nxt

  if state.detached or not is_open() then
    state.detached = false
    M._open_win()
  end

  render()

  timer.start(
    function(session, _)
      state.active = session
      if is_open() then render() end
    end,
    on_done
  )
end

local function toggle_session()
  if timer.is_running() then
    timer.pause()
    render()
  else
    timer.resume()
    if not timer.is_running() then
      timer.start(
        function(session, _)
          state.active = session
          if is_open() then render() end
        end,
        on_done
      )
    end
    render()
  end
end

-- ── window management ──────────────────────────────────────────────────────

function M._open_win()
  if is_open() then return end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(state.buf, "filetype",  "pomodoro")

  local ui  = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - HEIGHT) / 2)
  local col = math.floor((ui.width  - WIDTH)  / 2)

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative  = "editor",
    width     = WIDTH,
    height    = HEIGHT,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = "rounded",
    title     = " 🍅 Pomodoro ",
    title_pos = "center",
  })

  vim.api.nvim_win_set_option(state.win, "wrap",       false)
  vim.api.nvim_win_set_option(state.win, "cursorline", false)

  -- Define highlight groups
  vim.api.nvim_set_hl(0, "PomodoroTabActive",   { fg = "#1e1e2e", bg = "#cba6f7", bold = true  })
  vim.api.nvim_set_hl(0, "PomodoroTabInactive", { fg = "#585b70",                 bold = false })
  vim.api.nvim_set_hl(0, "PomodoroTabFocus",    { fg = "#1e1e2e", bg = "#f38ba8", bold = true  })
  vim.api.nvim_set_hl(0, "PomodoroTabShort",    { fg = "#1e1e2e", bg = "#a6e3a1", bold = true  })
  vim.api.nvim_set_hl(0, "PomodoroTabLong",     { fg = "#1e1e2e", bg = "#74c7ec", bold = true  })
  vim.api.nvim_set_hl(0, "PomodoroClockPulse",  { fg = "#cba6f7",                 bold = true  })
  vim.api.nvim_set_hl(0, "PomodoroRunning",     { fg = "#a6e3a1",                 bold = true  })
  vim.api.nvim_set_hl(0, "PomorodoPaused",      { fg = "#fab387",                 bold = false })
  vim.api.nvim_set_hl(0, "PomodoroHintKey",     { fg = "#cba6f7",                 bold = true  })
  vim.api.nvim_set_hl(0, "PomodoroHintLabel",   { fg = "#9399b2",                 bold = false })
  vim.api.nvim_set_hl(0, "PomorodoDivider",     { fg = "#313244"                               })

  local o = { noremap = true, silent = true, nowait = true, buffer = state.buf }

  -- Tab order for cycling
  local tab_order = { SESSION.FOCUS, SESSION.SHORT_BREAK, SESSION.LONG_BREAK }

  local function index_of(session)
    for i, s in ipairs(tab_order) do
      if s == session then return i end
    end
    return 1
  end

  -- Switch tabs by number
  vim.keymap.set("n", "1", function()
    timer.switch_session(SESSION.FOCUS)
    state.active = SESSION.FOCUS
    render()
  end, o)

  vim.keymap.set("n", "2", function()
    timer.switch_session(SESSION.SHORT_BREAK)
    state.active = SESSION.SHORT_BREAK
    render()
  end, o)

  vim.keymap.set("n", "3", function()
    timer.switch_session(SESSION.LONG_BREAK)
    state.active = SESSION.LONG_BREAK
    render()
  end, o)

  -- Tab: cycle forward
  vim.keymap.set("n", "<Tab>", function()
    local idx  = index_of(state.active)
    local nxt  = tab_order[(idx % #tab_order) + 1]
    timer.switch_session(nxt)
    state.active = nxt
    render()
  end, o)

  -- Shift-Tab: cycle backward
  vim.keymap.set("n", "<S-Tab>", function()
    local idx  = index_of(state.active)
    local prev = tab_order[((idx - 2) % #tab_order) + 1]
    timer.switch_session(prev)
    state.active = prev
    render()
  end, o)

  -- Restart: reset current session timer
  vim.keymap.set("n", "r", function()
    timer.switch_session(state.active)
    render()
  end, o)

  -- Toggle start / pause
  vim.keymap.set("n", "s", toggle_session, o)

  -- Detach: keep timer running, hide popup
  vim.keymap.set("n", "q",     M.detach, o)
  vim.keymap.set("n", "<Esc>", M.detach, o)

  -- Close: stop timer and close popup
  vim.keymap.set("n", "x", M.close, o)

  render()
end

-- ── public API ─────────────────────────────────────────────────────────────

function M.close()
  timer.stop()
  if is_open() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win      = nil
  state.buf      = nil
  state.detached = false
end

function M.detach()
  if is_open() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win      = nil
  state.buf      = nil
  state.detached = true
  vim.notify(
    "Pomodoro timer is running in the background.",
    vim.log.levels.INFO,
    { title = "Pomodoro" }
  )
end

function M.toggle()
  if is_open() then
    M.detach()
    return
  end

  state.active   = timer.current_session()
  state.detached = false
  M._open_win()
end

return M
