local M = {}

M.defaults = {
  focus_time = 20, 
  break_time = 5,
  long_break_time = 10,
  cycles_before_long_break = 4,
}

function M.setup(user_opts)
  local opts = vim.tbl_deep_extend("force", M.defaults, user_opts or {})
  require("nvim-pomodoro").setup(opts)
end

return M

