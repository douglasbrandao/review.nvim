-- review/navigation.lua
-- Navigation functions for review.nvim

local state = require("review.state")

local M = {}

--- Go to the next unreviewed file
function M.goto_next()
	state.cleanup_invalid_buffers()

	if #state.buffers == 0 then
		vim.notify("No buffers in review list", vim.log.levels.WARN)
		return
	end

	local current_index = state.get_current_buffer_index() or 0
	local start_index = current_index
	local checked = 0

	-- Search forward from current position
	while checked < #state.buffers do
		current_index = current_index + 1
		if current_index > #state.buffers then
			current_index = 1 -- Wrap around
		end

		local buffer = state.buffers[current_index]
		if not buffer.is_marked and state.is_valid_buffer(buffer.buf_id) then
			local ok, err = pcall(vim.api.nvim_set_current_buf, buffer.buf_id)
			if ok then
				local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer.buf_id), ":t")
				local remaining = 0
				for _, b in ipairs(state.buffers) do
					if not b.is_marked then
						remaining = remaining + 1
					end
				end
				vim.notify(string.format("[%d/%d] %s (%d remaining)", current_index, #state.buffers, filename, remaining), vim.log.levels.INFO)
				return
			else
				vim.notify("Failed to switch buffer: " .. tostring(err), vim.log.levels.ERROR)
				return
			end
		end

		checked = checked + 1
		if current_index == start_index then
			break
		end
	end

	vim.notify("✅ All files have been reviewed!", vim.log.levels.INFO)
end

--- Go to the previous unreviewed file
function M.goto_prev()
	state.cleanup_invalid_buffers()

	if #state.buffers == 0 then
		vim.notify("No buffers in review list", vim.log.levels.WARN)
		return
	end

	local current_index = state.get_current_buffer_index() or (#state.buffers + 1)
	local start_index = current_index
	local checked = 0

	-- Search backward from current position
	while checked < #state.buffers do
		current_index = current_index - 1
		if current_index < 1 then
			current_index = #state.buffers -- Wrap around
		end

		local buffer = state.buffers[current_index]
		if not buffer.is_marked and state.is_valid_buffer(buffer.buf_id) then
			local ok, err = pcall(vim.api.nvim_set_current_buf, buffer.buf_id)
			if ok then
				local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer.buf_id), ":t")
				local remaining = 0
				for _, b in ipairs(state.buffers) do
					if not b.is_marked then
						remaining = remaining + 1
					end
				end
				vim.notify(string.format("[%d/%d] %s (%d remaining)", current_index, #state.buffers, filename, remaining), vim.log.levels.INFO)
				return
			else
				vim.notify("Failed to switch buffer: " .. tostring(err), vim.log.levels.ERROR)
				return
			end
		end

		checked = checked + 1
		if current_index == start_index then
			break
		end
	end

	vim.notify("✅ All files have been reviewed!", vim.log.levels.INFO)
end

return M
