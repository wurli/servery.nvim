---@diagnostic disable: param-type-mismatch
local M = {}

---@param items? servery.PickerItem[]
M.select = function(items)
	Snacks.picker.pick("servery_sessions", {
		items = items or require("servery").get_picker_items(),
		---@param item servery.PickerItem
		format = function(item, _picker)
			local icon = item:icon()
			local status = item:status()
			return {
				{ icon, "ServeryIcon" .. status },
				{ "  ", "Normal" },
				{ item:display_name(), "ServeryLine" .. status },
				{ "  ", "Normal" },
				{ item:time_since_active(), "ServeryTime" },
			}
		end,
		layout = { preview = false },
		win = {
			input = {
				keys = {
					["<cr>"] = { "switch", mode = { "i", "n" } },
					["<c-g>"] = { "switch_and_detach", mode = { "i", "n" } },
					["<c-s>"] = { "spawn", mode = { "i", "n" } },
				},
			},
		},
		actions = {
			---@param item servery.PickerItem
			switch = function(_picker, item, _action) item:switch() end,
			---@param item servery.PickerItem
			switch_and_detach = function(_picker, item, _action) item:switch(true) end,
			---@param item servery.PickerItem
			spawn = function(_picker, item, _action) item:spawn_new() end,
		},
	})
end

return M
