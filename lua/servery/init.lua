local utils = require("servery.utils")
local Session = require("servery.session")

local M = {}

---@alias servery.ui_provider "builtin" | "snacks" | "fzf" | "telescope" | "mini_pick"
---@alias servery.action "switch" | "switch_and_detach" | "spawn" | "detach"

---@param opts { count: integer?, name: string?, status: ("any" | "active" | "inactive")? }
---@return servery.Session?
local get_session = function(opts)
	local sessions = M.list_sessions(opts.status)

	if opts.count then
		local servers = vim.tbl_filter(
			function(session) return session.server and session.server.socket ~= vim.v.servername or false end,
			sessions
		)
		local out = servers[opts.count]
		if not out then
			utils.notify_error(
				"Could not get last server #%d. Only found %d other servers running",
				opts.count,
				#servers
			)
		end
		return out
	end

	if opts.name then
		---@diagnostic disable-next-line: param-type-mismatch
		for _, session in ipairs(sessions) do
			if session:display_name() == opts.name then
				return session
			end
		end
	end
end

local setup_cmds = function()
	vim.api.nvim_create_user_command("Sv", function(args)
		local count = args.count ~= 0 and args.count or nil
		local arg = args.fargs[1]
		local bang = args.bang

		assert(not (count and arg), "Cannot combine forms `:[N]Sv` and `:Sv [dir]`")

		if count or arg then
			local session = get_session({ count = count, name = arg })
			if session then
				session:switch()
			elseif arg then
				local stat = vim.uv.fs_stat(vim.fs.normalize(arg))
				if stat and stat.type == "directory" then
					utils.switch_to(spawn_nvim(arg), bang)
				else
					utils.notify_error("No such directory found '%s'", arg)
				end
			end
		else
			M.show_ui()
		end
	end, {
		nargs = "?",
		count = true,
		bang = true,
		complete = function()
			return vim.tbl_map(function(session) return session:display_name() end, M.list_sessions())
		end,
	})

	vim.api.nvim_create_user_command("SvStop", function(args)
		local count = args.count ~= 0 and args.count or nil
		local arg = args.fargs[1]

		assert(not (count and arg), "Cannot combine forms `:[N]SvStop` and `:SvStop [server]`")

		if count or arg then
			local session = get_session({ count = count, name = arg, only_running = true })
			if session then
				session:detach()
			elseif arg then
				utils.notify_error("No such running server found '%s'", arg)
			end
		end
	end, {
		nargs = "?",
		count = true,
		bang = true,
		complete = function()
			return vim.tbl_map(function(session) return session:display_name() end, M.list_sessions("active"))
		end,
	})
end

cfg_defaults = function()
	---@class servery.Cfg
	local out = {
		---@type string[] | fun(): string[]
		dirs = function() return vim.fn.glob("~/*", true, true) end,
		---@type fun(): string[]
		servers = function()
			return vim.tbl_filter(
				-- By default, servers are only shown if the 'name' part of the
				-- server name is "nvim". See `:h serverstart()` for more info.
				function(s) return vim.startswith(vim.fs.basename(s), "nvim.") end,
				vim.fn.serverlist({ peer = true })
			)
		end,
		session_dir = vim.fs.normalize(vim.fs.joinpath(vim.fn.stdpath("run") --[[@as string]], "..", "servery")),
		---@type string[]
		spawn_cmd = { vim.v.progpath },
		ui = {
			provider = "builtin", ---@type servery.ui_provider
			prompt = "Switch Nvim Session",
			icons = {
				current = "",
				active = "",
				inactive = "",
			},
			---@type table<string, servery.action>
			actions = {
				["<enter>"] = "switch",
				["<c-g>"] = "switch_and_detach",
				["<c-x>"] = "detach",
				["<c-s>"] = "spawn",
			},
			---@type table<string, servery.action>
			fzf_actions = {
				["enter"] = "switch",
				["ctrl-g"] = "switch_and_detach",
				["ctrl-x"] = "detach",
				["ctrl-s"] = "spawn",
			},
		},
	}

	return out
end

---@type table<string, vim.api.keyset.highlight>
local highlights = {
	ServeryLineCurrent = { link = "@keyword" },
	ServeryLineActive = { link = "NONE" },
	ServeryLineInactive = { link = "NONE" },
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

M.cfg = nil --[[@as servery.Cfg?]]

---@param opts? servery.Cfg | {}
M.setup = function(opts)
	if not M.cfg then
		M.cfg = vim.tbl_deep_extend("force", cfg_defaults(), opts or {})
		vim.g.servery_original_cwd = vim.fn.getcwd()

		set_highlights()
		vim.api.nvim_create_autocmd("ColorScheme", { callback = set_highlights })

		require("servery.utils").mkdir(M.cfg.session_dir)
		setup_cmds()
	end
end

---@return servery.Cfg
M.get_cfg = function()
	assert(M.cfg, "Config is empty. Please call servery.setup()")
	return M.cfg
end

---@class servery.ServerInfo
---@field socket string
---@field pid integer
---@field original_cwd string?
---@field useractive integer?
---@field starttime integer?

---A neovim session may move to a different cwd, e.g. using :cd. servery.nvim
---keeps a record of where the session originally started, e.g. session name
---doesn't change too much in the UI.
---
---Currently gets cleared on :restart unless `globals` appears in
---'sessionoptions'.
---
---@return string
M.cwd = function() return vim.g.servery_original_cwd or vim.fn.getcwd() end

---@return servery.SessionActive
local get_server_info = function(server)
	local chan = vim.fn.sockconnect("pipe", server, { rpc = true })
	assert(chan ~= 0, "Could not connect to server at " .. server)

	local out = Session.new(vim.rpcrequest(chan, "nvim_call_function", "getcwd", {})--[[@as string]], {
		socket = server,
		pid = vim.rpcrequest(chan, "nvim_call_function", "getpid", {}) --[[@as integer]],
		useractive = vim.fn.has("nvim-0.13") == 1 and vim.rpcrequest(chan, "nvim_get_vvar", "useractive") or nil --[[@as integer?]],
		starttime = vim.fn.has("nvim-0.13") == 1 and vim.rpcrequest(chan, "nvim_get_vvar", "starttime") or nil --[[@as integer?]],
		original_cwd = utils.nilify(vim.rpcrequest(
			chan,
			"nvim_exec_lua",
			[[
				local ok, cwd = pcall(function() require("servery").cwd() end)
				return ok and cwd or nil
			]],
			{}
		)) --[[@as string?]],
	})
	vim.fn.chanclose(chan)
	return out
end

---List running servers
---
---@return servery.SessionActive[]
list_servers = function()
	local out = M.get_cfg().servers()

	-- Servers already started by servery should always be included
	for name, type in vim.fs.dir(M.get_cfg().session_dir) do
		if type == "socket" then
			local server = vim.fs.joinpath(M.get_cfg().session_dir, name)
			if not vim.tbl_contains(out, server) then
				table.insert(out, server)
			end
		end
	end

	return vim.tbl_map(get_server_info, out)
end

---List configured session directories
---
---@return servery.Session[]
list_dirs = function()
	local cfg = M.get_cfg()
	local dirs = type(cfg.dirs) == "table" and cfg.dirs or cfg.dirs()
	return vim.tbl_map(Session.new, dirs)
end

---List the sessions discoverable by servery
---
---@param status? "any" | "active" | "inactive"
---@return servery.Session[]
M.list_sessions = function(status)
	status = status or "any"
	local out = {} --[[@as servery.Session[] ]]

	if status == "any" or status == "active" then
		vim.list_extend(out, list_servers())
	end

	if status == "any" or status == "inactive" then
		vim.list_extend(out, list_dirs())
	end

	table.sort(out, function(a, b)
		if a.server and not b.server then
			return true
		end

		if b.server and not a.server then
			return false
		end

		if a.server and b.server then
			if vim.fs.normalize(a.server.socket) == vim.v.servername then
				return true
			end

			if vim.fs.normalize(b.server.socket) == vim.v.servername then
				return false
			end

			local sort_by = vim.fn.has("nvim-0.13") == 1 and "useractive" or "pid"

			return a.server[sort_by] > b.server[sort_by]
		end

		return a.cwd < b.cwd
	end)

	return out
end

---@param provider? servery.ui_provider
M.show_ui = function(provider)
	provider = provider or M.get_cfg().ui.provider
	require("servery.ui." .. provider).select()
end

---@return string
spawn_nvim = function(dir)
	dir = vim.fs.normalize(dir)
	local stat = vim.uv.fs_stat(dir)
	assert(stat and stat.type == "directory", string.format("`%s` is not a directory", dir))

	local server_name = vim.fs.basename(dir):sub(1, 5) .. "-" .. os.date("%Y%m%d-%H%M%S") .. ".pipe"
	local server_file = vim.fs.joinpath(M.get_cfg().session_dir, server_name)
	local cmd = vim.list_extend(vim.deepcopy(M.get_cfg().spawn_cmd), { "--headless", "--listen", server_file })
	local cmd_str = table.concat(cmd, " ")

	local chan = vim.fn.jobstart(cmd, { detach = true, cwd = dir })

	if chan == 0 or chan == -1 then
		error(string.format("Failed to spawn nvim with command `%s`", cmd_str))
	end

	return server_file
end

---@param opts { dir: string?, server: string? }
---@param detach boolean?
connect = function(opts, detach)
	assert(opts.dir or opts.server, "Must supply `dir` or `server`")
	utils.switch_to(opts.server or spawn_nvim(opts.dir), detach)
end

return M
