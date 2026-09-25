local M = {}

local function ansi_hl(s, group)
	local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
	if not hl.fg then
		return s
	end
	local r = bit.rshift(bit.band(hl.fg, 0xFF0000), 16)
	local g = bit.rshift(bit.band(hl.fg, 0x00FF00), 8)
	local b = bit.band(hl.fg, 0x0000FF)
	return string.format("\27[38;2;%d;%d;%dm%s\27[0m", r, g, b, s)
end

local time = -99
local items = {} --[[@as servery.PickerItem[] ]]

---@param item servery.PickerItem
---@param hl? boolean
---@return string
local format_item = function(item, hl)
	local icon = item:icon()
	local active_time = item:time_since_active(time)
	local status = item:status()

	local pieces = {
		{ icon, "ServeryIcon" .. status },
		{ "  " },
		{ item:display_name(), "ServeryLine" .. status },
		active_time and { "  " },
		active_time and { active_time, "ServeryTime" },
	}

	local out = ""
	for _, p in ipairs(pieces) do
		out = out .. (hl and p[2] and ansi_hl(p[1], p[2]) or p[1])
	end
	return out
end

---@return servery.PickerItem?
local get_item = function(text)
	for _, item in ipairs(items) do
		if format_item(item) == text then
			return item
		end
	end
end

M.select = function()
	local servery = require("servery")
	items = servery.get_picker_items()
	time = os.time()
	local lines = vim.tbl_map(function(item) return format_item(item, true) end, items)

	---@type fzf-lua.config.Base | {}
	local opts = {
		prompt = "Switch Nvim Sessions> ",
		actions = {
			---@param picker snacks.Picker
			---@param item servery.PickerItem
			["ctrl-s"] = {
				fn = function(selection, _opts, _ctx)
					for _, text in ipairs(selection) do
						local item = get_item(text)
						if item then
							item:spawn_new()
							-- vim.defer_fn(function() picker:refresh() end, 500)
						end
					end
				end,
			},
			---@param picker snacks.Picker
			---@param item servery.PickerItem
			["ctrl-x"] = {
				fn = function(selection, _opts, _ctx)
					for _, text in ipairs(selection) do
						local item = get_item(text)
						if item then
							item:detach()
							vim.uv.sleep(500)
							-- vim.defer_fn(function() picker:refresh() end, 500)
						end
					end
				end,
				reload = true,
			},
		},
	}

	FzfLua.fzf_exec(lines, opts)
end

M.select()
return M
