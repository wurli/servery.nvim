local M = {}

M.cfg_defaults = function()
	local cache_dir = vim.fn.stdpath("cache")
	assert(type(cache_dir) == "string")

	---@class mux.Cfg
	local out = {
		dirs = { "~" }, ---@type string[]
		session_dir = vim.fs.joinpath(cache_dir, "mux.nvim"),
		-- switch_on_start = false,
	}

	return out
end

M.cfg = nil --[[@as mux.Cfg?]]

local mkdir = function(dir)
	if vim.fn.mkdir(dir, "p") ~= 1 then
		error("Failed to create directory " .. dir)
	end
end

---@param opts? mux.Cfg
M.setup = function(opts)
	if not M.cfg then
		M.cfg = vim.tbl_deep_extend("force", M.cfg_defaults(), opts or {})

		mkdir(M.cfg.session_dir)

		vim.api.nvim_create_user_command("Mux", function()
			M.switch()
		end, { nargs = 0 })

		-- if M.cfg.switch_on_start and not M.is_mux() then
		-- 	vim.api.nvim_create_autocmd("VimEnter", {
		-- 		group = vim.api.nvim_create_augroup("mux.nvim"),
		-- 		once = true,
		-- 		callback = function()
		-- 			M.switch()
		-- 		end,
		-- 	})
		-- end
	end
end

M.is_mux = function()
	assert(M.cfg, "Config is missing. Please call mux.setup()")

	local session = vim.v.servername

	for _, mux_session in ipairs(M.list_sessions()) do
		if session == vim.fs.joinpath(M.cfg.session_dir, mux_session) then
			return true
		end
	end

	return false
end

M.switch = function()
	---@type { session_name: string, display_name: string, pipe_basename: string, dir: string? }[]
	local options = {}

	local sessions = M.list_sessions()

	for _, session in ipairs(sessions) do
		local opt = {}
		opt.pipe_basename = session
		opt.session_name = session:gsub("%.[^.]*$", "")
		opt.display_name = "[nvim] " .. opt.session_name
		table.insert(options, opt)
	end

	for _, dir in ipairs(M.list_dirs()) do
		local opt = {}
		opt.pipe_basename = vim.fs.basename(dir) .. ".pipe"
		opt.display_name = dir
		opt.dir = dir
		if not vim.tbl_contains(sessions, opt.session_name) then
			table.insert(options, opt)
		end
	end

	vim.ui.select(options, {
		format_item = function(x)
			return x.display_name
		end,
		prompt = "Switch nvim session",
	}, function(item, idx)
		if item and idx then
			if item.dir then
				M.new_session(item.dir)
			end
			M.switch_session(item.pipe_basename)
		end
	end)
end

---@return string[]
M.list_dirs = function()
	assert(M.cfg, "Config is missing. Please call mux.setup()")

	local dirs = {}
	for _, dir in ipairs(M.cfg.dirs) do
		for name, type, err in vim.fs.dir(dir, { err = true, follow = true }) do
			if err then
				vim.notify(string.format("Failed to scan dir `%s`: %s", name, err))
			end
			if type == "directory" then
				table.insert(dirs, vim.fs.joinpath(dir, name))
			end
		end
	end
	return dirs
end

---@return string[]
M.list_sessions = function()
	assert(M.cfg, "Config is missing. Please call mux.setup()")

	local sessions = {}
	for name, type, err in vim.fs.dir(M.cfg.session_dir) do
		if err then
			vim.notify(string.format("Failed to scan dir `%s`: %s", name, err))
		end
		if type == "socket" then
			table.insert(sessions, name)
		end
	end
	return sessions
end

M.new_session = function(dir)
	assert(M.cfg, "Config is missing. Please call mux.setup()")

	dir = vim.fs.normalize(dir)
	local stat = vim.uv.fs_stat(dir)
	assert(stat and stat.type == "directory", string.format("`%s` is not a directory", dir))

	local session_name = vim.fs.basename(dir) .. ".pipe"
	local session_file = vim.fs.joinpath(M.cfg.session_dir, session_name)
	local cmd = { "nvim", "--headless", "--listen", session_file }
	local cmd_str = table.concat(cmd, " ")

	vim.print(string.format("Starting session `%s`", cmd_str))

	local chan = vim.fn.jobstart(cmd, {
		detach = true,
		cwd = dir,
	})

	if chan == 0 or chan == -1 then
		error(string.format("Failed to run command `%s`", cmd_str))
	end
end

---@param session_name string
M.switch_session = function(session_name)
	assert(M.cfg, "Config is missing. Please call mux.setup()")

	local ok = vim.wait(500, function()
		for _, session in ipairs(M.list_sessions()) do
			if session == session_name then
				vim.print("connecting to " .. vim.inspect(vim.fs.joinpath(M.cfg.session_dir, session_name)))
				vim.cmd.connect(vim.fs.joinpath(M.cfg.session_dir, session_name))
				return true
			end
		end
		return false
	end)

	assert(ok, "Failed to connect to session " .. session_name)
end

return M
