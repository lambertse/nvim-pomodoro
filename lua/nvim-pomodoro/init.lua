local M = {}

-- Setup function called by Lazy.nvim
function M.setup(opts)
  opts = opts or {}
  vim.api.nvim_create_user_command("Pomodoro", function()
    print( "nvim-pomodoro from lambertse")
  end, {})
end

return M

