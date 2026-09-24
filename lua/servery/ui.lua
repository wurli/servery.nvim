local utils = require("servery.utils")

local M = {}

M.buf = -99
M.ns = vim.api.nvim_create_namespace("servery.ui")
M.items = {}

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

local did_setup = false

M.setup = function()
	if did_setup then
		return
	end

	did_setup = true

	set_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", { callback = set_highlights })
end

---@param items? servery.PickerItem[]
M.select = function(items)
	M.setup()

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
				require("servery").connect({ dir = item.cwd, server = vim.tbl_get(item, "server", "socket") })
				-- Close the selection window when we switch to a new session
				vim.cmd.bdelete()
			end
		end, { buf = M.buf })

		vim.keymap.set("n", "S", function()
			local item = M.items[vim.api.nvim_win_get_cursor(0)[1]]
			if item then
				require("servery").switch({ dir = item.cwd })
				vim.defer_fn(function() M.select() end, 400)
			end
		end, { buf = M.buf })

		vim.keymap.set("n", "<c-g>", function()
			local item = M.items[vim.api.nvim_win_get_cursor(0)[1]]
			if item then
				-- TODO: warn unsaved files, etc?
				require("servery").connect({ dir = item.cwd, server = vim.tbl_get(item, "server", "socket") }, true)
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
	local marks = {} ---@type [ integer, vim.api.keyset.set_extmark ][][]

	for _, item in ipairs(M.items) do
		local socket = item.server and item.server.socket
		local icon = socket == vim.v.servername and "" or ""
		local starttime = item.server and item.server.starttime
		local spacer2 = starttime and "  " or ""
		local run_time = starttime and "(" .. utils.time_since(starttime / 1e9) .. ")" or ""
		local dir = vim.fn.fnamemodify(item.cwd, ":~")

		local hl_type = socket and socket == vim.v.servername and "Current" or socket and "Active" or "Inactive"

		local line = ""
		local line_marks = {} ---@type [ integer, vim.api.keyset.set_extmark ][]

		---@type vim.api.keyset.set_extmark
		local indent_mark = {
			virt_text = { { "  ", "Normal" }, { icon, "ServeryIcon" .. hl_type }, { "  ", "Normal" } },
			virt_text_pos = "inline",
		}

		table.insert(line_marks, { 0, indent_mark })

		for _, part in ipairs({
			{ dir, "ServeryLine" .. hl_type },
			{ spacer2, "Normal" },
			{ run_time, "ServeryTime" },
		}) do
			local mark_start = #line
			line = line .. part[1]
			table.insert(line_marks, { mark_start, { hl_group = part[2], end_col = #line } })
		end

		table.insert(lines, line)
		table.insert(marks, line_marks)
	end

	vim.bo[M.buf].modifiable = true
	vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
	vim.bo[M.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(M.buf, M.ns, 0, -1)
	for line, line_marks in ipairs(marks) do
		for _, m in ipairs(line_marks) do
			vim.api.nvim_buf_set_extmark(M.buf, M.ns, line - 1, m[1], m[2])
		end
	end

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
