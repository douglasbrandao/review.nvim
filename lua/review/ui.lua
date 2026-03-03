-- review/ui.lua
-- UI functions for review.nvim (floating window)

local config = require("review.config")
local state = require("review.state")

local M = {}

--- Create a floating window
---@param window_config table Window configuration
---@return table|nil {buf: number, win: number}
local function create_window(window_config)
	local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
	if not ok then
		vim.notify("Failed to create buffer: " .. tostring(buf), vim.log.levels.ERROR)
		return nil
	end

	local win
	ok, win = pcall(vim.api.nvim_open_win, buf, true, window_config.opts)
	if not ok then
		vim.notify("Failed to open window: " .. tostring(win), vim.log.levels.ERROR)
		return nil
	end

	return {
		buf = buf,
		win = win,
	}
end

--- Show the review list in a floating window
function M.show_buffers()
	state.cleanup_invalid_buffers()

	if #state.buffers == 0 then
		vim.notify("No buffers in review list", vim.log.levels.WARN)
		return
	end

	-- Get statistics
	local stats = state.get_stats()
	local percentage = math.floor((stats.reviewed / stats.total) * 100)

	-- Build title with optional diff stats
	local title = string.format(" Review List - %d/%d (%d%%) ", stats.reviewed, stats.total, percentage)
	if config.options.git.show_diff_stats and (stats.additions > 0 or stats.deletions > 0) then
		title = string.format(" Review List - %d/%d (%d%%) | +%d -%d ", stats.reviewed, stats.total, percentage, stats.additions, stats.deletions)
	end

	--- Window config
	local window_config = {
		opts = {
			relative = "editor",
			width = config.options.window.width,
			height = config.options.window.height,
			row = math.floor((vim.o.lines - config.options.window.height) / 2),
			col = math.floor((vim.o.columns - config.options.window.width) / 2),
			style = "minimal",
			border = config.options.window.border,
			title = title,
			title_pos = "center",
		},
	}

	--- Create window
	local window = create_window(window_config)
	if not window then
		vim.notify("Failed to create review window", vim.log.levels.ERROR)
		return
	end

	--- Build content with header and footer
	local lines = {}

	-- Add separator line
	table.insert(lines, string.rep("─", config.options.window.width - 2))

	-- List marked buffers
	for i, buffer in ipairs(state.buffers) do
		local ok, filename = pcall(vim.api.nvim_buf_get_name, buffer.buf_id)
		if not ok then
			filename = "[Invalid Buffer]"
		end
		local marked_icon = buffer.is_marked and config.options.icons.reviewed or config.options.icons.not_reviewed
		local short_name = filename:match("^.+/(.+)$") or filename

		-- Build the line with optional diff stats
		local line = string.format("%d: %s - %s", i, marked_icon, short_name)

		-- Add diff stats if available
		if config.options.git.show_diff_stats and buffer.diff_stats then
			local diff_stats = buffer.diff_stats
			local stats_str = string.format(" [+%d -%d]", diff_stats.additions, diff_stats.deletions)
			line = line .. stats_str
		end

		table.insert(lines, line)
	end

	-- Add separator line
	table.insert(lines, string.rep("─", config.options.window.width - 2))

	-- Add footer with help
	table.insert(lines, " <CR>: Jump to buffer  |  q: Close ")

	local ok, err = pcall(vim.api.nvim_buf_set_lines, window.buf, 0, -1, false, lines)
	if not ok then
		vim.notify("Failed to set buffer lines: " .. tostring(err), vim.log.levels.ERROR)
		pcall(vim.api.nvim_win_close, window.win, true)
		return
	end

	-- Window buf must be non-editable
	ok, err = pcall(function()
		vim.bo[window.buf].modifiable = false
		vim.bo[window.buf].readonly = true
	end)
	if not ok then
		vim.notify("Failed to set buffer options: " .. tostring(err), vim.log.levels.WARN)
	end

	--- Close window when press "q"
	vim.keymap.set("n", "q", function()
		local close_ok, close_err = pcall(vim.api.nvim_win_close, window.win, true)
		if not close_ok then
			vim.notify("Failed to close window: " .. tostring(close_err), vim.log.levels.WARN)
		end
	end, {
		buffer = window.buf,
	})

	vim.keymap.set("n", "<CR>", function()
		--- Get floating window current line
		local row_number, _ = unpack(vim.api.nvim_win_get_cursor(0))

		-- Calculate buffer index (accounting for separator line at top)
		local buffer_index = row_number - 1

		-- Check if it's a valid buffer line (not separator or footer)
		if buffer_index >= 1 and buffer_index <= #state.buffers then
			--- Close window
			local close_ok, close_err = pcall(vim.api.nvim_win_close, window.win, true)
			if not close_ok then
				vim.notify("Failed to close window: " .. tostring(close_err), vim.log.levels.WARN)
			end

			--- Set current buffer w/ selected line
			local buf_id = state.buffers[buffer_index].buf_id
			if state.is_valid_buffer(buf_id) then
				local set_ok, set_err = pcall(vim.api.nvim_set_current_buf, buf_id)
				if not set_ok then
					vim.notify("Failed to switch to buffer: " .. tostring(set_err), vim.log.levels.ERROR)
				end
			else
				vim.notify("Buffer is no longer valid", vim.log.levels.ERROR)
			end
		end
	end, {
		buffer = window.buf,
	})
end

return M
