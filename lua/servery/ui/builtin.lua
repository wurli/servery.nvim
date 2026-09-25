local M = {}

M.buf = -99
M.ns = vim.api.nvim_create_namespace("servery.ui")
M.items = {}

---@type table<servery.action, fun()>
local builtin_actions = {
	switch = function()
		local item = M.items[vim.api.nvim_win_get_cursor(0)[1]]
		if item then
			item:switch()
			vim.cmd.bdelete()
		end
	end,
	spawn = function()
		local item = M.items[vim.api.nvim_win_get_cursor(0)[1]]
		if item then
			item:spawn_new()
			vim.defer_fn(function() M.select() end, 400)
		end
	end,
	switch_and_detach = function()
		local item = M.items[vim.api.nvim_win_get_cursor(0)[1]]
		if item then
			item:switch(true)
			-- Close the selection window when we switch to a new session
			vim.cmd.bdelete()
		end
	end,
	detach = function()
		local item = M.items[vim.api.nvim_win_get_cursor(0)[1]]
		if item then
			item:detach()
		end
	end,
}

---@param items? servery.PickerItem[]
M.select = function(items)
	local servery = require("servery")
	local cfg = servery.get_cfg()

	if items then
		assert(type(items) == "table")
	end
	M.items = items or servery.get_picker_items()

	if not vim.api.nvim_buf_is_valid(M.buf) then
		M.buf = vim.api.nvim_create_buf(false, true)
		vim.bo[M.buf].modifiable = false

		vim.keymap.set("n", "q", "<cmd>bd<cr>", { buf = M.buf })

		for key, action in pairs(cfg.ui.actions) do
			local fn = builtin_actions[action]
			if fn then
				vim.keymap.set("n", key, fn, { buf = M.buf })
			else
				vim.notify(
					string.format("[Servery] Action '%s' is not available for the builtin provider", action),
					vim.log.levels.WARN
				)
			end
		end
	end

	local lines = {} ---@type string[]
	local marks = {} ---@type [ integer, vim.api.keyset.set_extmark ][][]

	for _, item in ipairs(M.items) do
		local starttime = item.server and item.server.starttime
		local spacer = starttime and "  " or ""
		local run_time = item:time_since_active() or ""
		local status = item:status()

		local line = ""
		local line_marks = {} ---@type [ integer, vim.api.keyset.set_extmark ][]

		---@type vim.api.keyset.set_extmark
		local indent_mark = {
			virt_text = { { "  " }, { item:icon(), "ServeryIcon" .. status }, { "  " } },
			virt_text_pos = "inline",
		}

		table.insert(line_marks, { 0, indent_mark })

		for _, part in ipairs({
			{ item:display_name(), "ServeryLine" .. status },
			{ spacer },
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

M.select()

return M
