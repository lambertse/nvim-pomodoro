local M = {}

local config = { volume = 0.7 }

-- Keep a handle for tick specifically so we can kill the previous one
-- before spawning the next (prevents overlapping tick sounds)
local tick_handle = nil

local function spawn(file, volume)
  local handle
  local vol_str = string.format("%.2f", math.max(0, math.min(1, volume)))

  handle = vim.loop.spawn("afplay", {
    args = { file, "--volume", vol_str },
    stdio = { nil, nil, nil },
  }, function(code, _)
    -- Process exited — close the handle to avoid leaks
    if handle and not handle:is_closing() then
      handle:close()
    end
  end)

  return handle
end

function M.setup(opts)
  config.volume = opts.volume or 0.7
end

function M.play(event, file, volume)
  -- Validate file exists before spawning
  if vim.fn.filereadable(file) == 0 then
    vim.schedule(function()
      vim.notify(
        string.format("[nvim-pomodoro] Sound file not found: %s", file),
        vim.log.levels.WARN,
        { title = "Pomodoro Sound" }
      )
    end)
    return
  end

  if event == "tick" then
    -- Kill the previous tick process if still running
    if tick_handle and not tick_handle:is_closing() then
      tick_handle:kill(15)   -- SIGTERM
      tick_handle:close()
    end
    tick_handle = spawn(file, volume or config.volume)
  else
    spawn(file, volume or config.volume)
  end
end

function M.stop_tick()
  if tick_handle and not tick_handle:is_closing() then
    tick_handle:kill(15)
    tick_handle:close()
    tick_handle = nil
  end
end

return M
