---@diagnostic disable: undefined-global
local M = {}

M.select = function()
	if not MiniPick then
		vim.notify(
			'[Servery] `MiniPick` not found. `ui = "mini_pick"` requires mini.pick to be installed!',
			vim.log.levels.ERROR
		)
		return
	end

	local servery = require("servery")
	local cfg = servery.get_cfg()

	local time = os.time()
	local items = {} --[[@as servery.PickerItem[] ]]

	local get_items = function()
		items = servery.get_picker_items()
		time = os.time()
		for _, item in ipairs(items) do
			item.text = item:display_name()
		end
		return items
	end

	local ns = vim.api.nvim_create_namespace("servery_mini_pick")

	local show = function(buf_id, items_to_show, _query)
		local lines = {}
		local hl_data = {}
		for i, item in ipairs(items_to_show) do
			local icon = item:icon()
			local status = item:status()
			local name = item:display_name()
			local active_time = item:time_since_active(time) or ""
			local suffix = active_time ~= "" and ("  " .. active_time) or ""
			lines[i] = icon .. "  " .. name .. suffix

			local name_col = #icon + 2
			table.insert(hl_data, { i - 1, 0, #icon, "ServeryIcon" .. status })
			table.insert(hl_data, { i - 1, name_col, name_col + #name, "ServeryLine" .. status })
			if active_time ~= "" then
				local t_col = name_col + #name + 2
				table.insert(hl_data, { i - 1, t_col, t_col + #active_time, "ServeryTime" })
			end
		end

		vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
		vim.api.nvim_buf_clear_namespace(buf_id, ns, 0, -1)
		for _, h in ipairs(hl_data) do
			vim.api.nvim_buf_set_extmark(buf_id, ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
		end
	end

	---@type table<servery.action, fun(item: servery.PickerItem?): any>
	local mini_actions = {
		switch = function(item)
			if item then
				item:switch()
			end
			return true
		end,
		switch_and_detach = function(item)
			if item then
				item:switch(true)
			end
			return true
		end,
		spawn = function(item)
			if item then
				item:spawn_new()
				vim.defer_fn(function() MiniPick.set_picker_items(get_items()) end, 500)
			end
		end,
		detach = function(item)
			if item then
				item:detach()
				vim.defer_fn(function() MiniPick.set_picker_items(get_items()) end, 500)
			end
		end,
	}

	-- mini.pick mappings require `char` to be a single keystroke string like
	-- "<CR>", "<C-x>", etc. Normalize from servery's builtin key format.
	local normalize_key = function(key) return (key:gsub("^<enter>$", "<CR>"):gsub("^<Enter>$", "<CR>")) end

	local mappings = {}
	for key, action in pairs(cfg.ui.actions) do
		local fn = mini_actions[action]
		if fn then
			mappings["servery_" .. action] = {
				char = normalize_key(key),
				func = function()
					local item = MiniPick.get_picker_matches().current --[[@as servery.PickerItem?]]
					return fn(item)
				end,
			}
		else
			vim.notify(
				string.format("[Servery] Action '%s' is not available for the mini_pick provider", action),
				vim.log.levels.WARN
			)
		end
	end

	-- Disable mini.pick built-ins that share keys with servery's default actions.
	-- Setting a built-in mapping to "" is the supported way to disable it.
	mappings.choose_in_split = ""
	mappings.choose_in_vsplit = ""
	mappings.choose_in_tabpage = ""
	mappings.move_start = ""
	mappings.mark = ""

	MiniPick.start({
		source = {
			items = get_items(),
			name = cfg.ui.prompt,
			show = show,
			choose = function(item)
				if item then
					item:switch()
				end
			end,
		},
		mappings = mappings,
	})
end

return M
