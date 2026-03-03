-- review/state.lua
-- State management for review.nvim (buffers, persistence)

local config = require("review.config")
local git = require("review.git")
local utils = require("review.utils")

local M = {}

-- Internal state
M.buffers = {}

--- Check if buffer is valid
---@param buf_id number Buffer ID
---@return boolean
function M.is_valid_buffer(buf_id)
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

--- Clean up invalid buffers from the list
function M.cleanup_invalid_buffers()
	local valid_buffers = {}
	for _, buffer in ipairs(M.buffers) do
		if M.is_valid_buffer(buffer.buf_id) then
			table.insert(valid_buffers, buffer)
		end
	end
	M.buffers = valid_buffers
end

--- Get the state file path (relative to git root)
---@return string
local function get_state_file_path()
	local git_root = git.get_root()

	if not git_root then
		-- Fallback to current working directory
		git_root = vim.fn.getcwd()
	end

	return git_root .. "/" .. config.options.persistence.filename
end

--- Save the current review state to a JSON file
---@return boolean Success
function M.save()
	if not config.options.persistence.enable then
		return false
	end

	local state_file = get_state_file_path()

	-- Build state data (only serializable data, not buf_id)
	local state = {
		version = 1,
		merge_base = git.current_merge_base,
		files = {},
	}

	for _, buffer in ipairs(M.buffers) do
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

--- Load the review state from a JSON file
---@return table|nil Loaded state or nil
function M.load()
	if not config.options.persistence.enable then
		return nil
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

--- Restore buffers from saved state
---@return boolean Success
function M.restore()
	local state = M.load()
	if not state or not state.files then
		vim.notify("No saved review state found", vim.log.levels.INFO)
		return false
	end

	-- Clear current buffers
	M.buffers = {}
	git.current_merge_base = state.merge_base

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

			table.insert(M.buffers, {
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

--- Delete the state file
function M.clear()
	local state_file = get_state_file_path()
	os.remove(state_file)
	vim.notify("Review state cleared", vim.log.levels.INFO)
end

--- Auto-save wrapper (called after state changes)
function M.auto_save()
	if config.options.persistence.enable and config.options.persistence.auto_save then
		M.save()
	end
end

--- Add current buffer to review list
function M.add_buffer()
	local current_buffer = vim.api.nvim_get_current_buf()
	if not utils.has_value(M.buffers, current_buffer) then
		local filepath = vim.api.nvim_buf_get_name(current_buffer)
		local buffer = {
			buf_id = current_buffer,
			is_marked = false,
			filepath = filepath,
			diff_stats = nil, -- Will be nil for manually added buffers
		}
		table.insert(M.buffers, buffer)
		vim.notify("Buffer added to review list", vim.log.levels.INFO)
		M.auto_save()
	else
		vim.notify("Buffer is already in the list", vim.log.levels.WARN)
	end
end

--- Remove current buffer from review list
function M.remove_buffer()
	local current_buffer = vim.api.nvim_get_current_buf()
	for i, v in pairs(M.buffers) do
		if v.buf_id == current_buffer then
			table.remove(M.buffers, i)
			vim.notify("Buffer removed from review list", vim.log.levels.INFO)
			M.auto_save()
			return
		end
	end
	vim.notify("Buffer is not in the list", vim.log.levels.WARN)
end

--- Toggle reviewed status for current buffer
function M.toggle_reviewed()
	M.cleanup_invalid_buffers()
	local current_buffer = vim.api.nvim_get_current_buf()
	for _, v in pairs(M.buffers) do
		if v.buf_id == current_buffer then
			v.is_marked = not v.is_marked
			local status = v.is_marked and "reviewed" or "not reviewed"
			vim.notify("File marked as " .. status, vim.log.levels.INFO)
			M.auto_save()
			return
		end
	end
	vim.notify("Buffer is not in the review list", vim.log.levels.WARN)
end

--- Clear all buffers from review list
function M.clear_all()
	local count = #M.buffers
	M.buffers = {}
	vim.notify(string.format("Cleared %d buffer(s) from review list", count), vim.log.levels.INFO)
	M.auto_save()
end

--- Populate review list from git diff (internal)
---@param base_branch string|nil Base branch to compare against
function M.populate_from_git_diff_internal(base_branch)
	local files = git.get_diff_files(base_branch)

	if #files == 0 then
		vim.notify("No changed files found", vim.log.levels.WARN)
		return
	end

	-- Clear existing buffers
	M.buffers = {}

	-- Get diff stats for all files in one batch (more efficient)
	local all_stats = {}
	if config.options.git.show_diff_stats and git.current_merge_base then
		all_stats = git.get_all_diff_stats(git.current_merge_base)
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
			if not utils.has_value(M.buffers, buf_id) then
				table.insert(M.buffers, {
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

	local current_branch = git.get_current_branch() or "current"
	local base = base_branch or git.get_default_branch()

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
	M.auto_save()
end

--- Populate review list from git diff
---@param base_branch string|nil Base branch to compare against
function M.populate_from_git_diff(base_branch)
	-- Check if we should auto-load existing state
	if config.options.persistence.enable and config.options.persistence.auto_load then
		local existing_state = M.load()
		if existing_state and existing_state.files and #existing_state.files > 0 then
			-- Ask user if they want to restore or start fresh
			vim.ui.select(
				{ "Restore previous review", "Start fresh" },
				{ prompt = "Found saved review state:" },
				function(choice)
					if choice == "Restore previous review" then
						M.restore()
					else
						-- Continue with fresh git diff
						M.populate_from_git_diff_internal(base_branch)
					end
				end
			)
			return
		end
	end

	M.populate_from_git_diff_internal(base_branch)
end

--- Get the index of the current buffer in the review list
---@return number|nil
function M.get_current_buffer_index()
	local current_buffer = vim.api.nvim_get_current_buf()
	for i, v in ipairs(M.buffers) do
		if v.buf_id == current_buffer then
			return i
		end
	end
	return nil
end

--- Get review statistics
---@return table {total: number, reviewed: number, additions: number, deletions: number}
function M.get_stats()
	local total = #M.buffers
	local reviewed = 0
	local total_additions = 0
	local total_deletions = 0

	for _, buffer in ipairs(M.buffers) do
		if buffer.is_marked then
			reviewed = reviewed + 1
		end
		if buffer.diff_stats then
			total_additions = total_additions + buffer.diff_stats.additions
			total_deletions = total_deletions + buffer.diff_stats.deletions
		end
	end

	return {
		total = total,
		reviewed = reviewed,
		additions = total_additions,
		deletions = total_deletions,
	}
end

return M
