local utils = require("servery.utils")

---Active sessions include the `server` field, inactive ones don't.
---
---@class servery.Session
---@field cwd string
---@field server servery.ServerInfo?
local Session = {}
Session.__index = Session

---@class servery.SessionActive : servery.Session
---@field server servery.ServerInfo

---@param cwd string
---@param server servery.ServerInfo
Session.new = function(cwd, server)
	--
	return setmetatable({ cwd = cwd, server = server }, Session)
end

function Session:status()
	local socket = self.server and self.server.socket
	if socket == vim.v.servername then
		return "Current"
	elseif socket then
		return "Active"
	else
		return "Inactive"
	end
end

function Session:icon()
	local cfg = require("servery").get_cfg()
	return cfg.ui.icons[string.lower(self:status())] or " "
end

---@param as_of? integer
---@return string?
function Session:time_since_start(as_of)
	if self.server and self.server.starttime then
		return "(" .. utils.time_since(self.server.starttime / 1e9, as_of) .. ")"
	end
end

-- TODO: warn unsaved files, etc?
---@param detach boolean?
function Session:switch(detach)
	require("servery").get_cfg().on_switch(self)
	connect({
		server = self.server and self.server.socket,
		dir = self.cwd,
	}, detach)
end

function Session:spawn_new() spawn_nvim(self.cwd) end

function Session:display_name()
	local dir = vim.fn.fnamemodify(self.cwd, ":~")
	if self:status() == "Inactive" then
		return dir
	else
		local curr_dir = vim.fs.basename(dir)
		local original_cwd = self.server and self.server.original_cwd
		if original_cwd and original_cwd ~= self.cwd then
			local original_dir = vim.fs.basename(vim.fn.fnamemodify(original_cwd, ":~"))
			return original_dir .. " ( " .. curr_dir .. ")"
		end
		return curr_dir
	end
end

function Session:detach()
	if not self.server then
		return
	end

	local chan = vim.fn.sockconnect("pipe", self.server.socket, { rpc = true })

	local unsaved = vim.rpcrequest(
		chan,
		"nvim_exec_lua",
		[[
			return vim.tbl_filter(
				function(b) return vim.bo[b.bufnr].buftype == "" end,
				vim.fn.getbufinfo({ bufmodified = 1 })
			)
		]],
		{}
	) --[[@as table[] ]]

	if #unsaved > 0 then
		local names = vim.tbl_map(function(b) return "`" .. vim.fn.fnamemodify(b.name, ":~:.") .. "`" end, unsaved)
		local check = table.concat(names, ", ")
		utils.notify_warn("Can't close session '%s' due to unsaved changes. Check %s", self:display_name(), check)
	else
		-- Slightly defer the :qall so we have time to close the channel, rather
		-- than having it forcibly closed and show an annoying message
		vim.rpcrequest(chan, "nvim_exec_lua", "vim.defer_fn(vim.cmd.qall, 100)", {})
	end

	vim.fn.chanclose(chan)
end

return Session
