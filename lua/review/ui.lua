local config = require("review.config")
local state = require("review.state")
local utils = require("review.utils")

local M = {}
local namespace = vim.api.nvim_create_namespace("review.nvim")

local status_labels = {
	A = "A",
	C = "C",
	D = "D",
	M = "M",
	R = "R",
	T = "T",
	U = "U",
}

local function set_default_highlights()
	vim.api.nvim_set_hl(0, "ReviewDone", { default = true, link = "DiagnosticOk" })
	vim.api.nvim_set_hl(0, "ReviewPending", { default = true, link = "Comment" })
	vim.api.nvim_set_hl(0, "ReviewAdded", { default = true, link = "DiffAdd" })
	vim.api.nvim_set_hl(0, "ReviewDeleted", { default = true, link = "DiffDelete" })
	vim.api.nvim_set_hl(0, "ReviewHelp", { default = true, link = "Comment" })
end

---@return number, number
local function dimensions()
	local max_width = math.max(1, vim.o.columns - 4)
	local max_height = math.max(1, vim.o.lines - 4)
	local width = math.max(1, math.min(config.options.window.width, max_width))
	local wanted_height = #state.buffers + (config.options.window.show_help and 2 or 0)
	local height = math.max(1, math.min(config.options.window.height, max_height, wanted_height))
	return width, height
end

---@param width number
---@return string
local function window_title(width)
	local stats = state.get_stats()
	local percentage = stats.total == 0 and 0 or math.floor((stats.reviewed / stats.total) * 100)
	local title = string.format(" Review %d/%d · %d%% ", stats.reviewed, stats.total, percentage)
	if config.options.git.show_diff_stats and (stats.additions > 0 or stats.deletions > 0) then
		title = string.format(" Review %d/%d · %d%% · +%d -%d ", stats.reviewed, stats.total, percentage, stats.additions, stats.deletions)
	end
	return utils.truncate(title, math.max(1, width - 4))
end

---@param entry table
---@param width number
---@return string, number, number
local function entry_line(entry, width)
	local icon = entry.is_marked and config.options.icons.reviewed or config.options.icons.not_reviewed
	local status = status_labels[entry.status] or "?"
	local prefix = string.format(" %s  %s  ", icon, status)
	local suffix = ""
	if config.options.git.show_diff_stats and entry.diff_stats then
		if entry.diff_stats.binary then
			suffix = "  binary "
		else
			suffix = string.format("  +%d -%d ", entry.diff_stats.additions, entry.diff_stats.deletions)
		end
	end
	local display_path = entry.relative_path
	if entry.old_path then
		display_path = entry.old_path .. " → " .. entry.relative_path
	end
	display_path = display_path:gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
	local path_width = math.max(1, width - vim.fn.strdisplaywidth(prefix) - vim.fn.strdisplaywidth(suffix))
	local path = utils.truncate(display_path, path_width)
	local padding = string.rep(" ", math.max(0, path_width - vim.fn.strdisplaywidth(path)))
	return prefix .. path .. padding .. suffix, #prefix, #prefix + #path
end

---@param buffer number
---@param window number
---@param width number
local function render(buffer, window, width)
	local lines = {}
	local highlights = {}
	for index, entry in ipairs(state.buffers) do
		local line, _, path_end = entry_line(entry, width)
		table.insert(lines, line)
		table.insert(highlights, {
			row = index - 1,
			group = entry.is_marked and "ReviewDone" or "ReviewPending",
			start_col = 1,
			end_col = path_end,
		})
		if entry.diff_stats and not entry.diff_stats.binary then
			local plus = line:find("+%d+", path_end + 1)
			local minus = line:find("%-%d+", path_end + 1)
			if plus then
				table.insert(highlights, { row = index - 1, group = "ReviewAdded", start_col = plus - 1, end_col = minus and minus - 2 or #line })
			end
			if minus then
				table.insert(highlights, { row = index - 1, group = "ReviewDeleted", start_col = minus - 1, end_col = #line })
			end
		end
	end
	if config.options.window.show_help then
		table.insert(lines, "")
		table.insert(lines, utils.truncate(" <CR> open   x/Space toggle   q/Esc close", width))
	end

	vim.bo[buffer].modifiable = true
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
	vim.bo[buffer].modifiable = false
	vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
	for _, highlight in ipairs(highlights) do
		vim.api.nvim_buf_set_extmark(buffer, namespace, highlight.row, highlight.start_col, {
			end_col = highlight.end_col,
			hl_group = highlight.group,
		})
	end
	if config.options.window.show_help then
		vim.api.nvim_buf_set_extmark(buffer, namespace, #lines - 1, 0, { end_col = #lines[#lines], hl_group = "ReviewHelp" })
	end
	pcall(vim.api.nvim_win_set_config, window, { title = window_title(width), title_pos = "center" })
end

function M.show_buffers()
	state.cleanup_invalid_buffers()
	if #state.buffers == 0 then
		vim.notify("No files in review list", vim.log.levels.WARN)
		return
	end
	set_default_highlights()
	local width, height = dimensions()
	local buffer = vim.api.nvim_create_buf(false, true)
	local window = vim.api.nvim_open_win(buffer, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		style = "minimal",
		border = config.options.window.border,
		title = window_title(width),
		title_pos = "center",
	})

	vim.bo[buffer].bufhidden = "wipe"
	vim.bo[buffer].buftype = "nofile"
	vim.bo[buffer].filetype = "review"
	vim.bo[buffer].swapfile = false
	vim.wo[window].cursorline = true
	vim.wo[window].wrap = false
	render(buffer, window, width)
	local current = state.get_current_buffer_index() or 1
	pcall(vim.api.nvim_win_set_cursor, window, { current, 0 })

	local function selected_index()
		local row = vim.api.nvim_win_get_cursor(window)[1]
		return row >= 1 and row <= #state.buffers and row or nil
	end
	local function close()
		if vim.api.nvim_win_is_valid(window) then
			vim.api.nvim_win_close(window, true)
		end
	end
	local map_options = { buffer = buffer, nowait = true, silent = true }
	for _, key in ipairs({ "q", "<Esc>" }) do
		vim.keymap.set("n", key, close, map_options)
	end
	vim.keymap.set("n", "<CR>", function()
		local index = selected_index()
		if index then
			close()
			state.open(index)
		end
	end, map_options)
	for _, key in ipairs({ "x", "<Space>" }) do
		vim.keymap.set("n", key, function()
			local index = selected_index()
			if index and state.toggle_index(index, { silent = true }) then
				render(buffer, window, width)
			end
		end, map_options)
	end
end

return M
