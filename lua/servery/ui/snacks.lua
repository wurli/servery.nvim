---@diagnostic disable: param-type-mismatch
local M = {}

M.select = function()
	Snacks.picker.pick("servery_sessions", {
		finder = function()
			local new_items = require("servery").get_picker_items() --[[@as snacks.picker.finder.result]]
			for i, item in ipairs(new_items) do
				item.text = item:display_name()
				item.idx = i
			end
			return new_items
		end,
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
		sort = function(a, b) return a.idx < b.idx end,
		layout = { preview = false },
		win = {
			input = {
				keys = {
					["<cr>"] = { "servery_switch", mode = { "i", "n" } },
					["<c-g>"] = { "servery_switch_and_detach", mode = { "i", "n" } },
					["<c-s>"] = { "servery_spawn", mode = { "i", "n" } },
					["<c-x>"] = { "servery_detach", mode = { "i", "n" } },
				},
			},
		},
		actions = {
			---@param picker snacks.Picker
			---@param item servery.PickerItem
			servery_switch = function(picker, item, _action)
				item:switch()
				picker:close()
			end,
			---@param item servery.PickerItem
			servery_switch_and_detach = function(_picker, item, _action) item:switch(true) end,
			---@param picker snacks.Picker
			---@param item servery.PickerItem
			servery_spawn = function(picker, item, _action)
				item:spawn_new()
				vim.defer_fn(function() picker:refresh() end, 500)
			end,
			---@param picker snacks.Picker
			---@param item servery.PickerItem
			servery_detach = function(picker, item, _action)
				item:detach()
				vim.defer_fn(function() picker:refresh() end, 500)
			end,
		},
	})
end

return M
