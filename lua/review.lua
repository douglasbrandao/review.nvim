local utils = require("utils")

local buffers = {}

local function mark_buffer()
	local current_buffer = vim.api.nvim_get_current_buf()
	if not utils.has_value(buffers, current_buffer) then
		local buffer = { buf_id = current_buffer, is_marked = false }
		table.insert(buffers, buffer)
	end
end

local function unmark_buffer()
	local current_buffer = vim.api.nvim_get_current_buf()
	for i, v in pairs(buffers) do
		if v.buf_id == current_buffer then
			table.remove(buffers, i)
			break
		end
	end
end

local function mark_file_as_reviewed()
	local current_buffer = vim.api.nvim_get_current_buf()
	for _, v in pairs(buffers) do
		if v.buf_id == current_buffer then
			if v.is_marked == true then
				v.is_marked = false
			else
				v.is_marked = true
			end
			break
		end
	end
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
	--- Window config
	local width = 100
	local height = 30
	local window_config = {
		opts = {
			relative = "editor",
			width = width,
			height = height,
			row = math.floor((vim.o.lines - height) / 2),
			col = math.floor((vim.o.columns - width) / 2),
			style = "minimal",
			border = "rounded", -- Optional: Add a border
		},
	}

	--- Create window
	local window = create_window(window_config)

	--- List marked buffers
	local lines = {}
	for i, buffer in ipairs(buffers) do
		local filename = vim.api.nvim_buf_get_name(buffer.buf_id)
		local marked_icon = "❌"
		if buffer.is_marked then
			marked_icon = "✅"
		end
		table.insert(lines, string.format("%d: %s - %s", i, marked_icon, filename:match("^.+/(.+)$")))
	end
	vim.api.nvim_buf_set_lines(window.buf, 0, -1, false, lines)

	-- Window buf must be non-editable
	vim.api.nvim_buf_set_option(window.buf, "modifiable", false)
	vim.api.nvim_buf_set_option(window.buf, "readonly", true)

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

vim.keymap.set("n", "<leader>ri", mark_buffer, { desc = "Insert buffer" })
vim.keymap.set("n", "<leader>rr", unmark_buffer, { desc = "Remove buffer" })
vim.keymap.set("n", "<leader>rl", show_buffers, { desc = "Show buffers" })
vim.keymap.set("n", "<leader>rx", mark_file_as_reviewed, { desc = "Review file" })
