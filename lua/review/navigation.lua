local state = require("review.state")

local M = {}

---@param direction 1|-1
local function navigate(direction)
	state.cleanup_invalid_buffers()
	local total = #state.buffers
	if total == 0 then
		vim.notify("No files in review list", vim.log.levels.WARN)
		return
	end

	local current = state.get_current_buffer_index()
	local index = current or (direction == 1 and 0 or total + 1)
	for _ = 1, total do
		index = ((index - 1 + direction) % total) + 1
		if not state.buffers[index].is_marked and state.open(index) then
			local stats = state.get_stats()
			vim.notify(
				string.format("[%d/%d] %s (%d remaining)", index, total, state.buffers[index].relative_path, stats.total - stats.reviewed),
				vim.log.levels.INFO
			)
			return
		end
	end
	vim.notify("All files have been reviewed", vim.log.levels.INFO)
end

function M.goto_next()
	navigate(1)
end

function M.goto_prev()
	navigate(-1)
end

return M
