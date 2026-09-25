---@diagnostic disable: param-type-mismatch
local M = {}

---@type table<servery.action, table>
local snacks_actions = {
	switch = { "servery_switch", mode = { "i", "n" } },
	switch_and_detach = { "servery_switch_and_detach", mode = { "i", "n" } },
	spawn = { "servery_spawn", mode = { "i", "n" } },
	detach = { "servery_detach", mode = { "i", "n" } },
}

M.select = function()
	if not Snacks then
		vim.notify(
			'[Servery] `Snacks` not found. `ui = "snacks"` requires snacks.nvim to be installed!',
			vim.log.levels.ERROR
		)
		return
	end

	local servery = require("servery")
	local cfg = servery.get_cfg()

	local keys = {}
	for key, action in pairs(cfg.ui.actions) do
		keys[key] = snacks_actions[action]
			or vim.notify(
				string.format("[Servery] Action '%s' is not available for the snacks provider", action),
				vim.log.levels.WARN
			)
	end

	Snacks.picker.pick("servery_sessions", {
		title = cfg.ui.prompt,
		finder = function()
			local new_items = servery.get_picker_items() --[[@as snacks.picker.finder.result]]
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
		win = { input = { keys = keys } },
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
