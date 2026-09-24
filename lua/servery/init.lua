local M = {}

M.cfg_defaults = function()
	local cache_dir = vim.fn.stdpath("cache")
	assert(type(cache_dir) == "string")

	---@class servery.Cfg
	local out = {
		---@type string[] | fun(): string[]
		dirs = { "~" },
		---@type string
		session_dir = vim.fs.joinpath(cache_dir, "servery.nvim"),
	}

	return out
end

---@class servery.PickerItem
---@field cwd string
---@field server servery.ServerInfo?

---@class servery.ServerInfo
---@field socket string
---@field useractive integer
---@field starttime integer

M.cfg = nil --[[@as servery.Cfg?]]

---@type table<string, vim.api.keyset.highlight>
local highlights = {
	ServeryLineCurrent = { link = "@keyword" },
	ServeryLineActive = { link = "Normal" },
	ServeryLineInactive = { link = "Normal" },
	ServeryIconCurrent = { link = "CursorLineNr" },
	ServeryIconActive = { link = "@label" },
	ServeryIconInactive = { link = "ComplHint" },
	ServeryTime = { link = "Comment" },
}

local set_highlights = function()
	for group, hl in pairs(highlights) do
		hl.default = true
		vim.api.nvim_set_hl(0, group, hl)
	end
end

---@param opts? Partial<servery.Cfg>
M.setup = function(opts)
	if not M.cfg then
		M.cfg = vim.tbl_deep_extend("force", M.cfg_defaults(), opts or {})

		set_highlights()
		vim.api.nvim_create_autocmd("ColorScheme", { callback = set_highlights })

		require("servery.utils").mkdir(M.cfg.session_dir)
		vim.api.nvim_create_user_command("Sv", function(args)
			local arg = args.fargs[1]
			local which = tonumber(arg)
			which = which and math.floor(which)

			assert(which or not arg, string.format("Argument must be a number, not '%s'", arg))

			if which then
				M.switch({ prev = which })
			else
				M.show_ui()
			end
		end, { nargs = "?" })
	end
end

---@return servery.PickerItem
local get_server_info = function(server)
	local chan = vim.fn.sockconnect("pipe", server, { rpc = true })
	assert(chan ~= 0, "Could not connect to server at " .. server)
	local out = {
		cwd = vim.rpcrequest(chan, "nvim_call_function", "getcwd", {}) --[[@as string]],
		server = {
			socket = server,
			useractive = vim.rpcrequest(chan, "nvim_get_vvar", "useractive") --[[@as integer]],
			starttime = vim.rpcrequest(chan, "nvim_get_vvar", "starttime") --[[@as integer]],
		},
	}
	vim.fn.chanclose(chan)
	return out
end

---@return { cwd: string, server: servery.ServerInfo }[]
M.list_servers = function()
	assert(M.cfg, "Config is empty. Please call servery.setup()")

	local servers = vim.fn.serverlist({ peer = true })
	for name, type in vim.fs.dir(M.cfg.session_dir) do
		if type == "socket" then
			local server = vim.fs.joinpath(M.cfg.session_dir, name)
			if not vim.tbl_contains(servers, server) then
				table.insert(servers, server)
			end
		end
	end

	return vim.tbl_map(get_server_info, servers)
end

---@return string[]
M.list_dirs = function()
	assert(M.cfg, "Config is empty. Please call servery.setup()")
	return type(M.cfg.dirs) == "table" and M.cfg.dirs or M.cfg.dirs()
end

---@return servery.PickerItem[]
M.get_picker_items = function()
	local options = M.list_servers()

	for _, dir in ipairs(M.list_dirs()) do
		table.insert(options, { cwd = vim.fs.normalize(dir) })
	end

	table.sort(options, function(a, b)
		if a.server and not b.server then
			return true
		end

		if b.server and not a.server then
			return false
		end

		if a.server and b.server then
			if a.server.socket == vim.v.servername then
				return true
			end

			if b.server.socket == vim.v.servername then
				return false
			end

			if a.cwd == b.cwd then
				return a.server.starttime < b.server.starttime
			end
		end

		return a.cwd < b.cwd
	end)

	return options
end

---@param opts? { server: string?, dir: string?, prev: integer? }
M.switch = function(opts)
	opts = opts or { prev = nil } -- LSP gets confused

	if opts.server or opts.dir then
		M.connect(opts)
		return
	end

	if opts.prev then
		local servers = vim.tbl_filter(function(s) return s.server.socket ~= vim.v.servername end, M.list_servers())
		table.sort(servers, function(a, b) return a.server.useractive > b.server.useractive end)

		if servers[opts.prev] then
			M.connect({ server = servers[opts.prev].server.socket })
		else
			print(string.format("Can't get prev server %d; only %d servers running", opts.prev, #servers))
		end
		return
	end

	error("No options supplied")
end

---@param items? servery.PickerItem[]
M.show_ui = function(items)
	--
	require("servery.ui").select(items or M.get_picker_items())
end

---@return string
---@private
local spawn_nvim = function(dir)
	assert(M.cfg, "Config is empty. Please call servery.setup()")

	dir = vim.fs.normalize(dir)
	local stat = vim.uv.fs_stat(dir)
	assert(stat and stat.type == "directory", string.format("`%s` is not a directory", dir))

	local server_name = vim.fs.basename(dir) .. os.date("%Y%m%d-%H%M%S") .. ".pipe"
	local server_file = vim.fs.joinpath(M.cfg.session_dir, server_name)
	local cmd = { vim.v.progpath, "--headless", "--listen", server_file }
	local cmd_str = table.concat(cmd, " ")

	local chan = vim.fn.jobstart(cmd, { detach = true, cwd = dir })

	if chan == 0 or chan == -1 then
		error(string.format("Failed to spawn nvim with command `%s`", cmd_str))
	end

	return server_file
end

---Internal helper; use `connect()` instead
---
---@param server string
---@param detach boolean?
---@private
local switch_to = function(server, detach)
	assert(M.cfg, "Config is empty. Please call servery.setup()")

	if server == vim.v.servername then
		return
	end

	-- If the server has just been started (e.g. by M.spawn_nvim()) it might
	-- take a little while to actually get ready, so we should check if it
	-- exists.
	local ok = vim.wait(1000, function() return vim.uv.fs_stat(server) ~= nil end)
	assert(ok, "Failed to connect to session " .. server)
	vim.cmd({ cmd = "connect", args = { server }, bang = detach ~= nil })
end

---@param opts { dir: string?, server: string? }
---@param detach boolean?
M.connect = function(opts, detach)
	assert(opts.dir or opts.server, "Must supply `dir` or `server`")
	if opts.server then
		switch_to(opts.server, detach)
	else
		switch_to(spawn_nvim(opts.dir), detach)
	end
end

return M
