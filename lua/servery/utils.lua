local M = {}

---Get the elapsed time since `t` as a nicely formatted string
---@param t number
---@param finish? number
---@return string
M.time_since = function(t, finish)
	finish = finish or os.time()

	local seconds = math.floor(os.difftime(finish, t))
	local hh, mm, ss = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60

	if hh == 0 then
		return string.format("%02.f:%02.f", mm, ss)
	else
		return string.format("%02.f:%02.f:%02.f", hh, mm, ss)
	end
end

M.mkdir = function(dir)
	if vim.fn.mkdir(dir, "p") ~= 1 then
		error("Failed to create directory " .. dir)
	end
end

---@param server string
---@param detach boolean?
M.switch_to = function(server, detach)
	if server ~= vim.v.servername then
		-- If the server has just been started (e.g. by spawn_nvim()) it might
		-- take a little while to actually get ready, so we should check if it
		-- exists.
		local ok = vim.wait(1000, function() return vim.uv.fs_stat(server) ~= nil end, 100)
		assert(ok, "Failed to connect to session " .. server)
		vim.cmd({ cmd = "connect", args = { server }, bang = detach ~= nil })
	end
end

M.notify_warn = function(...) vim.notify(string.format(...), vim.log.levels.WARN) end
M.notify_error = function(...) vim.notify(string.format(...), vim.log.levels.ERROR) end
M.notify_info = function(...) vim.notify(string.format(...), vim.log.levels.INFO) end

return M
