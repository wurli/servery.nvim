local M = {}

M.cfg_defaults = function()
	local cache_dir = vim.fn.stdpath("cache")
	assert(type(cache_dir) == "string")

	---@class mux.Cfg
	local out = {
		---@type string[] | fun(): string[]
		dirs = { "~" },
		---@type string
		session_dir = vim.fs.joinpath(cache_dir, "mux.nvim"),
	}

	return out
end

---@class mux.PickerItem
---@field cwd string
---@field server mux.ServerInfo?

---@class mux.ServerInfo
---@field socket string
---@field useractive string
---@field starttime string

---@return mux.PickerItem
local get_server_info = function(server)
	local chan = vim.fn.sockconnect("pipe", server, { rpc = true })
	assert(chan ~= 0, "Could not connect to server at " .. server)
	local out = {
		cwd = vim.rpcrequest(chan, "nvim_call_function", "getcwd", {}),
		server = {
			socket = server,
			useractive = vim.rpcrequest(chan, "nvim_get_vvar", "useractive"),
			starttime = vim.rpcrequest(chan, "nvim_get_vvar", "starttime"),
		},
	}
	vim.fn.chanclose(chan)
	return out
end

---@return mux.PickerItem[]
M.list_servers = function()
	assert(M.cfg, "Config is empty. Please call mux.setup()")

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

M.cfg = nil --[[@as mux.Cfg?]]

---@param opts? Partial<mux.Cfg>
M.setup = function(opts)
	if not M.cfg then
		M.cfg = vim.tbl_deep_extend("force", M.cfg_defaults(), opts or {})
		vim.api.nvim_create_user_command("Mux", M.switch, { nargs = 0 })
	end
end

---@return mux.PickerItem[]
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

M.switch = function()
	require("mux.ui").select(M.get_picker_items())
	-- vim.ui.select(M.get_picker_items(), {
	-- 	---@param item mux.PickerItem
	-- 	format_item = function(item)
	-- 		local socket = item.server and item.server.socket
	-- 		local icon = socket == vim.v.servername and "" or socket and "" or " "
	--
	-- 		local starttime = item.server and item.server.starttime
	-- 		local run_time = starttime and "  (" .. utils.time_since(starttime / 1e9) .. ")" or ""
	--
	-- 		return icon .. "  " .. vim.fn.fnamemodify(item.cwd, ":~") .. run_time
	-- 	end,
	-- 	prompt = "Switch Sessions",
	-- }, function(item, idx)
	-- 	if item and idx then
	-- 		if item.server then
	-- 			M.connect(item.server.socket)
	-- 		else
	-- 			M.connect(M.spawn_nvim(item.cwd))
	-- 		end
	-- 	end
	-- end)
end

---@param item mux.PickerItem
---@param detach boolean?
M.switch_to = function(item, detach)
	if item.server then
		M.connect(item.server.socket, detach)
	else
		M.connect(M.spawn_nvim(item.cwd), detach)
	end
end

---@return string[]
M.list_dirs = function()
	assert(M.cfg, "Config is empty. Please call mux.setup()")
	return type(M.cfg.dirs) == "table" and M.cfg.dirs or M.cfg.dirs()
end

---@return string
M.spawn_nvim = function(dir)
	assert(M.cfg, "Config is empty. Please call mux.setup()")

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

---@param server string
---@param detach boolean?
M.connect = function(server, detach)
	assert(M.cfg, "Config is empty. Please call mux.setup()")

	if server == vim.v.servername then
		return
	end

	if detach == nil then
		detach = false
	end

	-- If the server has just been started (e.g. by M.spawn_nvim()) it might
	-- take a little while to actually get ready, so we should check if it
	-- exists.
	local ok = vim.wait(1000, function() return vim.uv.fs_stat(server) ~= nil end)
	assert(ok, "Failed to connect to session " .. server)
	vim.cmd({ cmd = "connect", args = { server }, bang = detach })
end

return M
