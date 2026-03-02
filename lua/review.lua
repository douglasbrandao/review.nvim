local utils = require("review.utils")

local M = {}

M.config = {
	keymaps = {
		enable = true,
		insert = "<leader>ri",
		remove = "<leader>rr",
		list = "<leader>rl",
		toggle_reviewed = "<leader>rx",
	},
	window = {
		width = 100,
		height = 30,
		border = "rounded",
	},
	icons = {
		reviewed = "✅",
		not_reviewed = "❌",
	},
}

local buffers = {}

-- Helper function to check if buffer is valid
local function is_valid_buffer(buf_id)
	local ok, is_valid = pcall(vim.api.nvim_buf_is_valid, buf_id)
	if not ok then
		return false
	end
	
	local ok2, is_loaded = pcall(vim.api.nvim_buf_is_loaded, buf_id)
	if not ok2 then
		return false
	end
	
	return is_valid and is_loaded
end

-- Clean up invalid buffers from the list
local function cleanup_invalid_buffers()
	local valid_buffers = {}
	for _, buffer in ipairs(buffers) do
		if is_valid_buffer(buffer.buf_id) then
			table.insert(valid_buffers, buffer)
		end
	end
	buffers = valid_buffers
end

local function mark_buffer()
	local current_buffer = vim.api.nvim_get_current_buf()
	if not utils.has_value(buffers, current_buffer) then
		local buffer = { buf_id = current_buffer, is_marked = false }
		table.insert(buffers, buffer)
		vim.notify("Buffer added to review list", vim.log.levels.INFO)
	else
		vim.notify("Buffer is already in the list", vim.log.levels.WARN)
	end
end

local function unmark_buffer()
	local current_buffer = vim.api.nvim_get_current_buf()
	for i, v in pairs(buffers) do
		if v.buf_id == current_buffer then
			table.remove(buffers, i)
			vim.notify("Buffer removed from review list", vim.log.levels.INFO)
			return
		end
	end
	vim.notify("Buffer is not in the list", vim.log.levels.WARN)
end

local function mark_file_as_reviewed()
	cleanup_invalid_buffers()
	local current_buffer = vim.api.nvim_get_current_buf()
	for _, v in pairs(buffers) do
		if v.buf_id == current_buffer then
			v.is_marked = not v.is_marked
			local status = v.is_marked and "reviewed" or "not reviewed"
			vim.notify("File marked as " .. status, vim.log.levels.INFO)
			return
		end
	end
	vim.notify("Buffer is not in the review list", vim.log.levels.WARN)
end

local function clear_all_buffers()
	local count = #buffers
	buffers = {}
	vim.notify(string.format("Cleared %d buffer(s) from review list", count), vim.log.levels.INFO)
end

local function create_window(config)
	local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
	if not ok then
		vim.notify("Failed to create buffer: " .. tostring(buf), vim.log.levels.ERROR)
		return nil
	end
	
	ok, win = pcall(vim.api.nvim_open_win, buf, true, config.opts)
	if not ok then
		vim.notify("Failed to open window: " .. tostring(win), vim.log.levels.ERROR)
		return nil
	end
	
	return {
		buf = buf,
		win = win,
	}
end

local function show_buffers()
	cleanup_invalid_buffers()
	
	if #buffers == 0 then
		vim.notify("No buffers in review list", vim.log.levels.WARN)
		return
	end

	-- Calculate statistics
	local total = #buffers
	local reviewed = 0
	for _, buffer in ipairs(buffers) do
		if buffer.is_marked then
			reviewed = reviewed + 1
		end
	end
	local percentage = math.floor((reviewed / total) * 100)

	--- Window config
	local window_config = {
		opts = {
			relative = "editor",
			width = M.config.window.width,
			height = M.config.window.height,
			row = math.floor((vim.o.lines - M.config.window.height) / 2),
			col = math.floor((vim.o.columns - M.config.window.width) / 2),
			style = "minimal",
			border = M.config.window.border,
			title = string.format(" Review List - %d/%d (%d%%) ", reviewed, total, percentage),
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
	table.insert(lines, string.rep("─", M.config.window.width - 2))
	
	-- List marked buffers
	for i, buffer in ipairs(buffers) do
		local ok, filename = pcall(vim.api.nvim_buf_get_name, buffer.buf_id)
		if not ok then
			filename = "[Invalid Buffer]"
		end
		local marked_icon = buffer.is_marked and M.config.icons.reviewed or M.config.icons.not_reviewed
		table.insert(lines, string.format("%d: %s - %s", i, marked_icon, filename:match("^.+/(.+)$") or filename))
	end
	
	-- Add separator line
	table.insert(lines, string.rep("─", M.config.window.width - 2))
	
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
		local ok, err = pcall(vim.api.nvim_win_close, window.win, true)
		if not ok then
			vim.notify("Failed to close window: " .. tostring(err), vim.log.levels.WARN)
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
		if buffer_index >= 1 and buffer_index <= #buffers then
			--- Close window
			local ok, err = pcall(vim.api.nvim_win_close, window.win, true)
			if not ok then
				vim.notify("Failed to close window: " .. tostring(err), vim.log.levels.WARN)
			end
			
			--- Set current buffer w/ selected line
			local buf_id = buffers[buffer_index].buf_id
			if is_valid_buffer(buf_id) then
				ok, err = pcall(vim.api.nvim_set_current_buf, buf_id)
				if not ok then
					vim.notify("Failed to switch to buffer: " .. tostring(err), vim.log.levels.ERROR)
				end
			else
				vim.notify("Buffer is no longer valid", vim.log.levels.ERROR)
			end
		end
	end, {
		buffer = window.buf,
	})
end

-- Setup function
function M.setup(user_config)
	-- Merge user config with default config
	M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

	-- Create user commands with error handling
	vim.api.nvim_create_user_command("ReviewAdd", function()
		local ok, err = pcall(mark_buffer)
		if not ok then
			vim.notify("ReviewAdd failed: " .. tostring(err), vim.log.levels.ERROR)
		end
	end, {
		desc = "Add current buffer to review list",
	})

	vim.api.nvim_create_user_command("ReviewRemove", function()
		local ok, err = pcall(unmark_buffer)
		if not ok then
			vim.notify("ReviewRemove failed: " .. tostring(err), vim.log.levels.ERROR)
		end
	end, {
		desc = "Remove current buffer from review list",
	})

	vim.api.nvim_create_user_command("ReviewList", function()
		local ok, err = pcall(show_buffers)
		if not ok then
			vim.notify("ReviewList failed: " .. tostring(err), vim.log.levels.ERROR)
		end
	end, {
		desc = "Show all buffers in review list",
	})

	vim.api.nvim_create_user_command("ReviewToggle", function()
		local ok, err = pcall(mark_file_as_reviewed)
		if not ok then
			vim.notify("ReviewToggle failed: " .. tostring(err), vim.log.levels.ERROR)
		end
	end, {
		desc = "Toggle reviewed status of current buffer",
	})

	vim.api.nvim_create_user_command("ReviewClear", function()
		local ok, err = pcall(clear_all_buffers)
		if not ok then
			vim.notify("ReviewClear failed: " .. tostring(err), vim.log.levels.ERROR)
		end
	end, {
		desc = "Clear all buffers from review list",
	})

	-- Setup keymaps if enabled
	if M.config.keymaps.enable then
		vim.keymap.set("n", M.config.keymaps.insert, function()
			local ok, err = pcall(mark_buffer)
			if not ok then
				vim.notify("Failed to add buffer: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Insert buffer" })
		
		vim.keymap.set("n", M.config.keymaps.remove, function()
			local ok, err = pcall(unmark_buffer)
			if not ok then
				vim.notify("Failed to remove buffer: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Remove buffer" })
		
		vim.keymap.set("n", M.config.keymaps.list, function()
			local ok, err = pcall(show_buffers)
			if not ok then
				vim.notify("Failed to show buffers: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Show buffers" })
		
		vim.keymap.set("n", M.config.keymaps.toggle_reviewed, function()
			local ok, err = pcall(mark_file_as_reviewed)
			if not ok then
				vim.notify("Failed to toggle review status: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Toggle reviewed" })
	end
end

-- Expose public functions
M.mark_buffer = mark_buffer
M.unmark_buffer = unmark_buffer
M.show_buffers = show_buffers
M.mark_file_as_reviewed = mark_file_as_reviewed
M.clear_all_buffers = clear_all_buffers

return M
