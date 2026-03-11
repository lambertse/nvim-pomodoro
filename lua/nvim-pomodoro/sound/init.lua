local M = {}

local backend = nil
local opts = {}

-- ── default bundled sounds (macOS system sounds, no files needed) ──────────
local DEFAULTS = {
	start = "/System/Library/Sounds/Glass.aiff",
	done = "/System/Library/Sounds/Hero.aiff",
	milestone = "/System/Library/Sounds/Glass.aiff",
	tick = "/System/Library/Sounds/Basso.aiff",
	urgent = "/System/Library/Sounds/Glass.aiff",
}

local function detect_backend()
	if vim.fn.has("mac") == 1 then
		return require("nvim-pomodoro.sound.backend.macos")
	end
	-- TODO: add support for other platforms (Linux, Windows)
	return nil
end

function M.setup(sound_opts)
	opts = sound_opts or {}

	-- Merge user file overrides with defaults
	local files = vim.tbl_deep_extend("force", DEFAULTS, opts.files or {})
	opts._resolved_files = files

	-- Detect and initialise backend
	backend = detect_backend()
	if backend then
		backend.setup({ volume = opts.volume or 0.7 })
	end
end

function M.play(event)
	if not opts.enabled then
		return
	end
	if not backend then
		return
	end

	local events = opts.events or {}
	if events[event] == false then
		return
	end

	local file = opts._resolved_files and opts._resolved_files[event]
	if not file then
		return
	end

	backend.play(event, file, opts.volume or 0.7)
end

function M.toggle()
	opts.enabled = not opts.enabled
	return opts.enabled
end

function M.is_enabled()
	return opts.enabled == true
end

function M.is_available()
	return backend ~= nil
end

return M
