local utils = require("review.utils")

local M = {}

M.config = {
	keymaps = {
		enable = true,
		insert = "<leader>ri",
		remove = "<leader>rr",
		list = "<leader>rl",
		toggle_reviewed = "<leader>rx",
		git_diff = "<leader>rg",
		next_unreviewed = "<leader>rn",
		prev_unreviewed = "<leader>rp",
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
	git = {
		default_base = nil, -- nil means auto-detect (main/master)
		show_diff_stats = true, -- Show +/- line stats in the list
	},
	persistence = {
		enable = true, -- Enable automatic state persistence
		filename = ".review-state.json", -- State file name (relative to git root)
		auto_save = true, -- Auto-save on buffer mark/unmark
		auto_load = true, -- Auto-load state when git diff is populated
	},
}

local buffers = {}

-- Store the current merge base for diff stats
local current_merge_base = nil

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
		local filepath = vim.api.nvim_buf_get_name(current_buffer)
		local buffer = { 
			buf_id = current_buffer, 
			is_marked = false,
			filepath = filepath,
			diff_stats = nil, -- Will be nil for manually added buffers
		}
		table.insert(buffers, buffer)
		vim.notify("Buffer added to review list", vim.log.levels.INFO)
		auto_save_state()
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
			auto_save_state()
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
			auto_save_state()
			return
		end
	end
	vim.notify("Buffer is not in the review list", vim.log.levels.WARN)
end

local function clear_all_buffers()
	local count = #buffers
	buffers = {}
	vim.notify(string.format("Cleared %d buffer(s) from review list", count), vim.log.levels.INFO)
	auto_save_state()
end

-- Persistence functions

-- Get the state file path (relative to git root)
local function get_state_file_path()
	local git_root = nil
	local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
	if handle then
		local result = handle:read("*a")
		handle:close()
		if result and result ~= "" then
			git_root = result:gsub("%s+$", "")
		end
	end
	
	if not git_root then
		-- Fallback to current working directory
		git_root = vim.fn.getcwd()
	end
	
	return git_root .. "/" .. M.config.persistence.filename
end

-- Save the current review state to a JSON file
local function save_state()
	if not M.config.persistence.enable then
		return false
	end
	
	local state_file = get_state_file_path()
	
	-- Build state data (only serializable data, not buf_id)
	local state = {
		version = 1,
		merge_base = current_merge_base,
		files = {},
	}
	
	for _, buffer in ipairs(buffers) do
		table.insert(state.files, {
			filepath = buffer.filepath,
			is_marked = buffer.is_marked,
			diff_stats = buffer.diff_stats,
		})
	end
	
	-- Serialize to JSON
	local ok, json = pcall(vim.fn.json_encode, state)
	if not ok then
		vim.notify("Failed to serialize review state: " .. tostring(json), vim.log.levels.ERROR)
		return false
	end
	
	-- Write to file
	local file, err = io.open(state_file, "w")
	if not file then
		vim.notify("Failed to save review state: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	
	file:write(json)
	file:close()
	
	return true
end

-- Load the review state from a JSON file
local function load_state()
	if not M.config.persistence.enable then
		return false
	end
	
	local state_file = get_state_file_path()
	
	-- Check if file exists
	local file = io.open(state_file, "r")
	if not file then
		return nil -- No state file exists
	end
	
	local content = file:read("*a")
	file:close()
	
	if not content or content == "" then
		return nil
	end
	
	-- Parse JSON
	local ok, state = pcall(vim.fn.json_decode, content)
	if not ok or not state then
		vim.notify("Failed to parse review state file", vim.log.levels.WARN)
		return nil
	end
	
	return state
end

-- Restore buffers from saved state
local function restore_state()
	local state = load_state()
	if not state or not state.files then
		vim.notify("No saved review state found", vim.log.levels.INFO)
		return false
	end
	
	-- Clear current buffers
	buffers = {}
	current_merge_base = state.merge_base
	
	local loaded_count = 0
	local skipped_count = 0
	
	for _, file_state in ipairs(state.files) do
		local filepath = file_state.filepath
		
		-- Check if file exists
		if vim.fn.filereadable(filepath) == 1 then
			-- Find or create buffer for this file
			local buf_id = vim.fn.bufnr(filepath, true) -- true = create if not exists
			
			-- Set buffer as listed (so it appears in buffer list)
			vim.bo[buf_id].buflisted = true
			
			table.insert(buffers, {
				buf_id = buf_id,
				is_marked = file_state.is_marked or false,
				filepath = filepath,
				diff_stats = file_state.diff_stats,
			})
			loaded_count = loaded_count + 1
		else
			skipped_count = skipped_count + 1
		end
	end
	
	local msg = string.format("Restored %d file(s) from review state", loaded_count)
	if skipped_count > 0 then
		msg = msg .. string.format(" (%d skipped - no longer exist)", skipped_count)
	end
	vim.notify(msg, vim.log.levels.INFO)
	
	return true
end

-- Delete the state file
local function clear_state()
	local state_file = get_state_file_path()
	os.remove(state_file)
	vim.notify("Review state cleared", vim.log.levels.INFO)
end

-- Auto-save wrapper (called after state changes)
local function auto_save_state()
	if M.config.persistence.enable and M.config.persistence.auto_save then
		save_state()
	end
end

-- Navigation functions

-- Get the index of the current buffer in the review list
local function get_current_buffer_index()
	local current_buffer = vim.api.nvim_get_current_buf()
	for i, v in ipairs(buffers) do
		if v.buf_id == current_buffer then
			return i
		end
	end
	return nil
end

-- Go to the next unreviewed file
local function goto_next_unreviewed()
	cleanup_invalid_buffers()
	
	if #buffers == 0 then
		vim.notify("No buffers in review list", vim.log.levels.WARN)
		return
	end
	
	local current_index = get_current_buffer_index() or 0
	local start_index = current_index
	local checked = 0
	
	-- Search forward from current position
	while checked < #buffers do
		current_index = current_index + 1
		if current_index > #buffers then
			current_index = 1 -- Wrap around
		end
		
		local buffer = buffers[current_index]
		if not buffer.is_marked and is_valid_buffer(buffer.buf_id) then
			local ok, err = pcall(vim.api.nvim_set_current_buf, buffer.buf_id)
			if ok then
				local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer.buf_id), ":t")
				local remaining = 0
				for _, b in ipairs(buffers) do
					if not b.is_marked then
						remaining = remaining + 1
					end
				end
				vim.notify(string.format("[%d/%d] %s (%d remaining)", current_index, #buffers, filename, remaining), vim.log.levels.INFO)
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

-- Go to the previous unreviewed file
local function goto_prev_unreviewed()
	cleanup_invalid_buffers()
	
	if #buffers == 0 then
		vim.notify("No buffers in review list", vim.log.levels.WARN)
		return
	end
	
	local current_index = get_current_buffer_index() or (#buffers + 1)
	local start_index = current_index
	local checked = 0
	
	-- Search backward from current position
	while checked < #buffers do
		current_index = current_index - 1
		if current_index < 1 then
			current_index = #buffers -- Wrap around
		end
		
		local buffer = buffers[current_index]
		if not buffer.is_marked and is_valid_buffer(buffer.buf_id) then
			local ok, err = pcall(vim.api.nvim_set_current_buf, buffer.buf_id)
			if ok then
				local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer.buf_id), ":t")
				local remaining = 0
				for _, b in ipairs(buffers) do
					if not b.is_marked then
						remaining = remaining + 1
					end
				end
				vim.notify(string.format("[%d/%d] %s (%d remaining)", current_index, #buffers, filename, remaining), vim.log.levels.INFO)
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

-- Git integration functions

-- Get the git root directory
local function get_git_root()
	local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
	if not handle then
		return nil
	end
	local result = handle:read("*a")
	handle:close()
	
	if result and result ~= "" then
		return result:gsub("%s+$", "") -- Trim whitespace
	end
	return nil
end

-- Get diff stats (additions/deletions) for a specific file
local function get_file_diff_stats(filepath, merge_base)
	if not merge_base then
		return nil
	end
	
	local git_root = get_git_root()
	if not git_root then
		return nil
	end
	
	-- Get relative path from git root
	local rel_path = filepath:gsub("^" .. vim.pesc(git_root) .. "/", "")
	
	-- Get numstat for the specific file
	local cmd = string.format("git diff --numstat %s HEAD -- '%s' 2>/dev/null", merge_base, rel_path)
	local handle = io.popen(cmd)
	if not handle then
		return nil
	end
	
	local result = handle:read("*a")
	handle:close()
	
	if not result or result == "" then
		return nil
	end
	
	-- Parse numstat output: "additions\tdeletions\tfilename"
	local additions, deletions = result:match("^(%d+)%s+(%d+)")
	if additions and deletions then
		return {
			additions = tonumber(additions) or 0,
			deletions = tonumber(deletions) or 0,
		}
	end
	
	return nil
end

-- Get diff stats for all files in a batch (more efficient)
local function get_all_diff_stats(merge_base)
	if not merge_base then
		return {}
	end
	
	local git_root = get_git_root()
	if not git_root then
		return {}
	end
	
	local cmd = string.format("git diff --numstat %s HEAD 2>/dev/null", merge_base)
	local handle = io.popen(cmd)
	if not handle then
		return {}
	end
	
	local stats = {}
	for line in handle:lines() do
		local additions, deletions, filename = line:match("^(%d+)%s+(%d+)%s+(.+)$")
		if additions and deletions and filename then
			local abs_path = git_root .. "/" .. filename
			stats[abs_path] = {
				additions = tonumber(additions) or 0,
				deletions = tonumber(deletions) or 0,
			}
		end
	end
	handle:close()
	
	return stats
end

-- Get the current branch name
local function get_current_branch()
	local handle = io.popen("git branch --show-current 2>/dev/null")
	if not handle then
		return nil
	end
	local result = handle:read("*a")
	handle:close()
	
	if result and result ~= "" then
		return result:gsub("%s+$", "")
	end
	return nil
end

-- Get the default branch (main or master)
local function get_default_branch()
	-- Try to get the default branch from remote
	local handle = io.popen("git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'")
	if handle then
		local result = handle:read("*a")
		handle:close()
		if result and result ~= "" then
			return result:gsub("%s+$", "")
		end
	end
	
	-- Fallback: check if main or master exists
	handle = io.popen("git show-ref --verify --quiet refs/heads/main 2>/dev/null && echo main || echo master")
	if handle then
		local result = handle:read("*a")
		handle:close()
		if result and result ~= "" then
			return result:gsub("%s+$", "")
		end
	end
	
	return "main"
end

-- Get files modified in current branch compared to base branch
local function get_git_diff_files(base_branch)
	local git_root = get_git_root()
	if not git_root then
		vim.notify("Not in a git repository", vim.log.levels.ERROR)
		return {}, nil
	end
	
	-- Use the provided base branch or detect the default
	base_branch = base_branch or get_default_branch()
	
	-- Get the merge base between current branch and base branch
	local merge_base_cmd = string.format("git merge-base %s HEAD 2>/dev/null", base_branch)
	local handle = io.popen(merge_base_cmd)
	if not handle then
		vim.notify("Failed to get merge base", vim.log.levels.ERROR)
		return {}, nil
	end
	local merge_base = handle:read("*a"):gsub("%s+$", "")
	handle:close()
	
	if merge_base == "" then
		vim.notify(string.format("Could not find merge base with '%s'", base_branch), vim.log.levels.ERROR)
		return {}, nil
	end
	
	-- Store the merge base for later use
	current_merge_base = merge_base
	
	-- Get the list of changed files
	local diff_cmd = string.format("git diff --name-only %s HEAD 2>/dev/null", merge_base)
	handle = io.popen(diff_cmd)
	if not handle then
		vim.notify("Failed to get diff", vim.log.levels.ERROR)
		return {}, merge_base
	end
	
	local files = {}
	for line in handle:lines() do
		if line and line ~= "" then
			-- Convert to absolute path
			local abs_path = git_root .. "/" .. line
			table.insert(files, abs_path)
		end
	end
	handle:close()
	
	return files
end

-- Internal function to populate review list from git diff
local function populate_from_git_diff_internal(base_branch)
	local files = get_git_diff_files(base_branch)
	
	if #files == 0 then
		vim.notify("No changed files found", vim.log.levels.WARN)
		return
	end
	
	-- Clear existing buffers
	buffers = {}
	
	-- Get diff stats for all files in one batch (more efficient)
	local all_stats = {}
	if M.config.git.show_diff_stats and current_merge_base then
		all_stats = get_all_diff_stats(current_merge_base)
	end
	
	local added_count = 0
	local skipped_count = 0
	
	for _, filepath in ipairs(files) do
		-- Check if file exists
		local file_exists = vim.fn.filereadable(filepath) == 1
		if file_exists then
			-- Open or get buffer for the file
			local buf_id = vim.fn.bufadd(filepath)
			vim.fn.bufload(buf_id)
			
			-- Get diff stats for this file
			local stats = all_stats[filepath]
			
			-- Add to review list with stats
			if not utils.has_value(buffers, buf_id) then
				table.insert(buffers, { 
					buf_id = buf_id, 
					is_marked = false,
					filepath = filepath,
					diff_stats = stats,
				})
				added_count = added_count + 1
			end
		else
			skipped_count = skipped_count + 1
		end
	end
	
	local current_branch = get_current_branch() or "current"
	local base = base_branch or get_default_branch()
	
	local message = string.format(
		"Added %d file(s) to review (%s → %s)",
		added_count,
		base,
		current_branch
	)
	
	if skipped_count > 0 then
		message = message .. string.format(" | %d file(s) skipped (deleted)", skipped_count)
	end
	
	vim.notify(message, vim.log.levels.INFO)
	
	-- Auto-save the new state
	auto_save_state()
end

-- Populate review list from git diff
local function populate_from_git_diff(base_branch)
	-- Check if we should auto-load existing state
	if M.config.persistence.enable and M.config.persistence.auto_load then
		local existing_state = load_state()
		if existing_state and existing_state.files and #existing_state.files > 0 then
			-- Ask user if they want to restore or start fresh
			vim.ui.select(
				{ "Restore previous review", "Start fresh" },
				{ prompt = "Found saved review state:" },
				function(choice)
					if choice == "Restore previous review" then
						restore_state()
					else
						-- Continue with fresh git diff
						populate_from_git_diff_internal(base_branch)
					end
				end
			)
			return
		end
	end
	
	populate_from_git_diff_internal(base_branch)
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
	local total_additions = 0
	local total_deletions = 0
	
	for _, buffer in ipairs(buffers) do
		if buffer.is_marked then
			reviewed = reviewed + 1
		end
		-- Sum up diff stats
		if buffer.diff_stats then
			total_additions = total_additions + buffer.diff_stats.additions
			total_deletions = total_deletions + buffer.diff_stats.deletions
		end
	end
	local percentage = math.floor((reviewed / total) * 100)
	
	-- Build title with optional diff stats
	local title = string.format(" Review List - %d/%d (%d%%) ", reviewed, total, percentage)
	if M.config.git.show_diff_stats and (total_additions > 0 or total_deletions > 0) then
		title = string.format(" Review List - %d/%d (%d%%) | +%d -%d ", reviewed, total, percentage, total_additions, total_deletions)
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
	table.insert(lines, string.rep("─", M.config.window.width - 2))
	
	-- List marked buffers
	for i, buffer in ipairs(buffers) do
		local ok, filename = pcall(vim.api.nvim_buf_get_name, buffer.buf_id)
		if not ok then
			filename = "[Invalid Buffer]"
		end
		local marked_icon = buffer.is_marked and M.config.icons.reviewed or M.config.icons.not_reviewed
		local short_name = filename:match("^.+/(.+)$") or filename
		
		-- Build the line with optional diff stats
		local line = string.format("%d: %s - %s", i, marked_icon, short_name)
		
		-- Add diff stats if available
		if M.config.git.show_diff_stats and buffer.diff_stats then
			local stats = buffer.diff_stats
			local stats_str = string.format(" [+%d -%d]", stats.additions, stats.deletions)
			line = line .. stats_str
		end
		
		table.insert(lines, line)
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
	-- Mark that the plugin has been configured
	vim.g.review_configured = true
	
	-- Merge user config with default config
	M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

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
		
		vim.keymap.set("n", M.config.keymaps.git_diff, function()
			local ok, err = pcall(populate_from_git_diff, M.config.git.default_base)
			if not ok then
				vim.notify("Failed to load git diff: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Load files from git diff" })
		
		vim.keymap.set("n", M.config.keymaps.next_unreviewed, function()
			local ok, err = pcall(goto_next_unreviewed)
			if not ok then
				vim.notify("Failed to go to next file: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Go to next unreviewed file" })
		
		vim.keymap.set("n", M.config.keymaps.prev_unreviewed, function()
			local ok, err = pcall(goto_prev_unreviewed)
			if not ok then
				vim.notify("Failed to go to previous file: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Go to previous unreviewed file" })
	end
end

-- Expose public functions
M.mark_buffer = mark_buffer
M.unmark_buffer = unmark_buffer
M.show_buffers = show_buffers
M.mark_file_as_reviewed = mark_file_as_reviewed
M.clear_all_buffers = clear_all_buffers
M.populate_from_git_diff = populate_from_git_diff
M.get_git_diff_files = get_git_diff_files
M.get_current_branch = get_current_branch
M.get_default_branch = get_default_branch
M.goto_next_unreviewed = goto_next_unreviewed
M.goto_prev_unreviewed = goto_prev_unreviewed
M.save_state = save_state
M.load_state = restore_state
M.clear_state = clear_state

return M
