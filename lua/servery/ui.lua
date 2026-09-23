local utils = require("servery.utils")

local M = {}

M.buf = -99

M.items = {}

---@param items? servery.PickerItem[]
M.select = function(items)
	if items then
		assert(type(items) == "table")
	end
	M.items = items or require("servery").get_picker_items()

	if not vim.api.nvim_buf_is_valid(M.buf) then
		M.buf = vim.api.nvim_create_buf(false, true)

		vim.bo[M.buf].modifiable = false

		vim.keymap.set("n", "q", "<cmd>bd<cr>", { buf = M.buf })

		vim.keymap.set("n", "<enter>", function()
			local item = M.items[vim.api.nvim_win_get_cursor(0)[1]]
			if item then
				require("servery").switch_to(item)
				-- Close the selection window when we switch to a new session
				vim.cmd.bdelete()
			end
		end, { buf = M.buf })

		vim.keymap.set("n", "S", function()
			local item = M.items[vim.api.nvim_win_get_cursor(0)[1]]
			if item then
				require("servery").spawn_nvim(item.cwd)
				vim.defer_fn(function() M.select() end, 400)
			end
		end, { buf = M.buf })

		vim.keymap.set("n", "<c-g>", function()
			local item = M.items[vim.api.nvim_win_get_cursor(0)[1]]
			if item then
				-- TODO: warn unsaved files, etc?
				require("servery").switch_to(item, true)
				M.select()
			end
		end, { buf = M.buf })

		vim.keymap.set("n", "x", function()
			local item = M.items[vim.api.nvim_win_get_cursor(0)[1]]
			if item and item.server then
				local chan = vim.fn.sockconnect("pipe", item.server.socket, { rpc = true })
				-- Slightly defer the :qall so we have time to close the channel, rather
				-- than having it forcibly closed and show an annoying message
				vim.rpcrequest(chan, "nvim_exec_lua", "vim.defer_fn(vim.cmd.qall, 200)", {})
				vim.fn.chanclose(chan)
				vim.defer_fn(function() M.select() end, 600)
			end
		end, { buf = M.buf })
	end

	local lines = {} ---@type string[]
	for _, item in ipairs(M.items) do
		local socket = item.server and item.server.socket
		local icon = socket == vim.v.servername and "" or socket and "" or " "
		local starttime = item.server and item.server.starttime
		local run_time = starttime and "  (" .. utils.time_since(starttime / 1e9) .. ")" or ""
		table.insert(lines, icon .. "  " .. vim.fn.fnamemodify(item.cwd, ":~") .. run_time)
	end

	vim.bo[M.buf].modifiable = true
	vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
	vim.bo[M.buf].modifiable = false

	local wins = vim.api.nvim_tabpage_list_wins(0)
	local win = vim.tbl_filter(function(w) return vim.api.nvim_win_get_buf(w) == M.buf end, wins)[1]
	if win then
		vim.api.nvim_set_current_win(win)
		return
	else
		local w = vim.api.nvim_open_win(M.buf, true, {
			title = "Switch Sessions",
			style = "minimal",
			relative = "editor",
			col = math.floor(vim.o.columns * 0.1),
			row = math.floor(vim.o.lines * 0.1),
			width = math.floor(vim.o.columns * 0.8),
			height = math.floor(vim.o.lines * 0.8),
		})

		vim.api.nvim_create_autocmd({ "WinClosed", "BufWinLeave" }, {
			pattern = tostring(w),
			callback = function() vim.api.nvim_buf_delete(M.buf) end,
		})
	end
end

return M
