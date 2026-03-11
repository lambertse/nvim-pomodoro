local M = {}

M.IS_WINDOWS = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1

function M.socket_path()
	if M.IS_WINDOWS then
		-- TODO: return "\\\\.\\pipe\\nvim-pomodoro"
		return nil
	end
	local data_dir  = vim.fn.stdpath("data") .. "/nvim-pomodoro"
  local socket_path = data_dir .. "/socket"
  return socket_path
end

function M.supported()
	return not M.IS_WINDOWS
end

return M
