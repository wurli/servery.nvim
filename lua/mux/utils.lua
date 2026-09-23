local M = {}

---Get the elapsed time since `t` as a nicely formatted string
---@param t number
---@param finish? number
---@return string
M.time_since = function(t, finish)
	finish = finish or os.time()

	local seconds = math.floor(os.difftime(finish, t))
	local hh, mm, ss = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60

	if hh == 0 then
		return string.format("%02.f:%02.f", mm, ss)
	else
		return string.format("%02.f:%02.f:%02.f", hh, mm, ss)
	end
end

return M
