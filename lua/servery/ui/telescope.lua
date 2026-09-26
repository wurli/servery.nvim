local M = {}

M.select = function()
	local ok, pickers = pcall(function() return require("telescope.pickers") end)
	if not ok then
		vim.notify(
			'[Servery] `telescope` not found. `ui = "telescope"` requires telescope.nvim to be installed!',
			vim.log.levels.ERROR
		)
		return
	end

	local finders = require("telescope.finders")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local entry_display = require("telescope.pickers.entry_display")
	local conf = require("telescope.config").values

	local servery = require("servery")
	local cfg = servery.get_cfg()

	local time = os.time()

	local displayer = entry_display.create({
		separator = "  ",
		items = {
			{ width = 2 },
			{ remaining = true },
			{ remaining = true },
		},
	})

	---@param entry { value: servery.PickerItem }
	local make_display = function(entry)
		local item = entry.value
		local status = item:status()
		return displayer({
			{ item:icon(), "ServeryIcon" .. status },
			{ item:display_name(), "ServeryLine" .. status },
			{ item:time_since_start(time) or "", "ServeryTime" },
		})
	end

	---@param item servery.PickerItem
	local entry_maker = function(item)
		return {
			value = item,
			display = make_display,
			ordinal = item:display_name(),
		}
	end

	local new_finder = function()
		time = os.time()
		return finders.new_table({
			results = servery.get_picker_items(),
			entry_maker = entry_maker,
		})
	end

	---@type table<servery.action, fun(prompt_bufnr: integer)>
	local telescope_actions = {
		switch = function(prompt_bufnr)
			local entry = action_state.get_selected_entry()
			actions.close(prompt_bufnr)
			if entry then
				entry.value:switch()
			end
		end,
		switch_and_detach = function(prompt_bufnr)
			local entry = action_state.get_selected_entry()
			actions.close(prompt_bufnr)
			if entry then
				entry.value:switch(true)
			end
		end,
		spawn = function(prompt_bufnr)
			local entry = action_state.get_selected_entry()
			if entry then
				entry.value:spawn_new()
				local picker = action_state.get_current_picker(prompt_bufnr)
				vim.defer_fn(function() picker:refresh(new_finder()) end, 500)
			end
		end,
		detach = function(prompt_bufnr)
			local entry = action_state.get_selected_entry()
			if entry then
				entry.value:detach()
				local picker = action_state.get_current_picker(prompt_bufnr)
				vim.defer_fn(function() picker:refresh(new_finder()) end, 500)
			end
		end,
	}

	pickers
		.new({}, {
			prompt_title = cfg.ui.prompt,
			finder = new_finder(),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(_prompt_bufnr, map)
				-- <enter> is bound as the default action; override it too so
				-- users can rebind it via cfg.ui.actions
				actions.select_default:replace(telescope_actions[cfg.ui.actions["<enter>"]] or function() end)

				for key, action in pairs(cfg.ui.actions) do
					if key ~= "<enter>" then
						local fn = telescope_actions[action]
						if fn then
							map({ "i", "n" }, key, fn)
						else
							vim.notify(
								string.format(
									"[Servery] Action '%s' is not available for the telescope provider",
									action
								),
								vim.log.levels.WARN
							)
						end
					end
				end
				return true
			end,
		})
		:find()
end

return M
