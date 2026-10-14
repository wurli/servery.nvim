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

---@param socket string
M.wait_for_server = function(socket)
	return vim.wait(1000, function() return vim.uv.fs_stat(socket) ~= nil end, 100)
end

---@param server string
---@param detach boolean?
M.switch_to = function(server, detach)
	if server ~= vim.v.servername then
		-- If the server has just been started (e.g. by spawn_nvim()) it might
		-- take a little while to actually get ready, so we should check if it
		-- exists.
		local ok = M.wait_for_server(server)
		assert(ok, "Failed to connect to session " .. server)
		vim.cmd({ cmd = "connect", args = { server }, bang = detach or false })
	end
end

---@alias servery.SwitchCompletion fun(success: boolean)

--- Arm Post remotely before switching sessions, then return the completion callback.
---@param socket string
---@param data { cwd: string, server: servery.ServerInfo? }
---@return servery.SwitchCompletion?
M.prepare_switch_post = function(socket, data)
	-- A switch to the current session is a no-op and will not trigger UIEnter.
	if socket == vim.v.servername then
		return nil
	end

	assert(M.wait_for_server(socket), "Failed to connect to session " .. socket)

	local chan = vim.fn.sockconnect("pipe", socket, { rpc = true })
	assert(chan > 0, "Failed to open destination RPC connection")

	-- arm "ServerySwitchPost" in the destination session
	local ok, result = pcall(
		vim.rpcrequest,
		chan,
		"nvim_exec_lua",
		'return require("servery.utils").switch_post_handler(...)',
		{ data }
	)

	if not ok then
		vim.fn.chanclose(chan)
		error(result)
	end

	local autocmd_id = result

	-- keep the RPC channel open until the switch outcome is known.
	---@param success boolean
	local function cleanup(success)
		local cleanup_ok, cleanup_err = true, nil

		if not success then
			-- remove the pending handler so a later attachment cannot emit a stale post
			cleanup_ok, cleanup_err = pcall(
				vim.rpcrequest,
				chan,
				"nvim_exec_lua",
				[[
					local id = ...
					-- The one-shot handler may already have fired.
					if #vim.api.nvim_get_autocmds({ id = id }) > 0 then
						vim.api.nvim_del_autocmd(id)
					end
				]],
				{ autocmd_id }
			)
		end

		vim.fn.chanclose(chan)

		if not cleanup_ok then
			error(cleanup_err)
		end
	end

	return cleanup
end

--- register post in the destination; "ServerySwitchPost" waits for RPC readiness, but also UI attachment
---@param data any
---@return integer Autocommand ID
M.switch_post_handler = function(data)
	return vim.api.nvim_create_autocmd("UIEnter", {
		once = true,
		callback = function()
			vim.schedule(
				function() vim.api.nvim_exec_autocmds("User", { pattern = "ServerySwitchPost", data = data }) end
			)
		end,
	})
end

M.nilify = function(x) return not x == vim.NIL and x end

M.notify_warn = function(...) vim.notify(string.format(...), vim.log.levels.WARN) end
M.notify_error = function(...) vim.notify(string.format(...), vim.log.levels.ERROR) end
M.notify_info = function(...) vim.notify(string.format(...), vim.log.levels.INFO) end

return M
