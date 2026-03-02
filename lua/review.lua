local utils = require("utils")

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

local function create_window(config)
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, config.opts)
	return {
		buf = buf,
		win = win,
	}
end

local function show_buffers()
	if #buffers == 0 then
		vim.notify("No buffers in review list", vim.log.levels.WARN)
		return
	end

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
		},
	}

	--- Create window
	local window = create_window(window_config)

	--- List marked buffers
	local lines = {}
	for i, buffer in ipairs(buffers) do
		local filename = vim.api.nvim_buf_get_name(buffer.buf_id)
		local marked_icon = buffer.is_marked and M.config.icons.reviewed or M.config.icons.not_reviewed
		table.insert(lines, string.format("%d: %s - %s", i, marked_icon, filename:match("^.+/(.+)$")))
	end
	vim.api.nvim_buf_set_lines(window.buf, 0, -1, false, lines)

	-- Window buf must be non-editable
	vim.bo[window.buf].modifiable = false
	vim.bo[window.buf].readonly = true

	--- Close window when press "q"
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(window.win, true)
	end, {
		buffer = window.buf,
	})

	vim.keymap.set("n", "<CR>", function()
		--- Get floating window current line
		local row_number, _ = unpack(vim.api.nvim_win_get_cursor(0))
		--- Close window
		vim.api.nvim_win_close(window.win, true)
		--- Set current buffer w/ selected line
		local buf_id = buffers[row_number].buf_id
		vim.api.nvim_set_current_buf(buf_id)
	end, {
		buffer = window.buf,
	})
end

-- Setup function
function M.setup(user_config)
	-- Merge user config with default config
	M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

	-- Setup keymaps if enabled
	if M.config.keymaps.enable then
		vim.keymap.set("n", M.config.keymaps.insert, mark_buffer, { desc = "Review: Insert buffer" })
		vim.keymap.set("n", M.config.keymaps.remove, unmark_buffer, { desc = "Review: Remove buffer" })
		vim.keymap.set("n", M.config.keymaps.list, show_buffers, { desc = "Review: Show buffers" })
		vim.keymap.set("n", M.config.keymaps.toggle_reviewed, mark_file_as_reviewed, { desc = "Review: Toggle reviewed" })
	end
end

-- Expose public functions
M.mark_buffer = mark_buffer
M.unmark_buffer = unmark_buffer
M.show_buffers = show_buffers
M.mark_file_as_reviewed = mark_file_as_reviewed

return M
