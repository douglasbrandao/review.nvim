-- review/init.lua
-- Main module for review.nvim

local config = require("review.config")
local state = require("review.state")
local git = require("review.git")
local navigation = require("review.navigation")
local ui = require("review.ui")

local M = {}

-- Re-export config for backward compatibility
M.config = config.options

--- Setup function
---@param user_config table|nil User configuration
function M.setup(user_config)
	-- Mark that the plugin has been configured
	vim.g.review_configured = true

	-- Setup configuration
	config.setup(user_config)

	-- Update M.config reference
	M.config = config.options

	-- Setup keymaps if enabled
	if config.options.keymaps.enable then
		vim.keymap.set("n", config.options.keymaps.insert, function()
			local ok, err = pcall(state.add_buffer)
			if not ok then
				vim.notify("Failed to add buffer: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Insert buffer" })

		vim.keymap.set("n", config.options.keymaps.remove, function()
			local ok, err = pcall(state.remove_buffer)
			if not ok then
				vim.notify("Failed to remove buffer: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Remove buffer" })

		vim.keymap.set("n", config.options.keymaps.list, function()
			local ok, err = pcall(ui.show_buffers)
			if not ok then
				vim.notify("Failed to show buffers: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Show buffers" })

		vim.keymap.set("n", config.options.keymaps.toggle_reviewed, function()
			local ok, err = pcall(state.toggle_reviewed)
			if not ok then
				vim.notify("Failed to toggle review status: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Toggle reviewed" })

		vim.keymap.set("n", config.options.keymaps.git_diff, function()
			local ok, err = pcall(state.populate_from_git_diff, config.options.git.default_base)
			if not ok then
				vim.notify("Failed to load git diff: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Load files from git diff" })

		vim.keymap.set("n", config.options.keymaps.next_unreviewed, function()
			local ok, err = pcall(navigation.goto_next)
			if not ok then
				vim.notify("Failed to go to next file: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Go to next unreviewed file" })

		vim.keymap.set("n", config.options.keymaps.prev_unreviewed, function()
			local ok, err = pcall(navigation.goto_prev)
			if not ok then
				vim.notify("Failed to go to previous file: " .. tostring(err), vim.log.levels.ERROR)
			end
		end, { desc = "Review: Go to previous unreviewed file" })
	end
end

-- Public API (delegates to submodules)

--- Add current buffer to review list
M.mark_buffer = state.add_buffer

--- Remove current buffer from review list
M.unmark_buffer = state.remove_buffer

--- Show review list in floating window
M.show_buffers = ui.show_buffers

--- Toggle reviewed status for current buffer
M.mark_file_as_reviewed = state.toggle_reviewed

--- Clear all buffers from review list
M.clear_all_buffers = state.clear_all

--- Populate review list from git diff
M.populate_from_git_diff = state.populate_from_git_diff

--- Get files from git diff
M.get_git_diff_files = git.get_diff_files

--- Get current git branch
M.get_current_branch = git.get_current_branch

--- Get default git branch
M.get_default_branch = git.get_default_branch

--- Go to next unreviewed file
M.goto_next_unreviewed = navigation.goto_next

--- Go to previous unreviewed file
M.goto_prev_unreviewed = navigation.goto_prev

--- Save review state
M.save_state = state.save

--- Load/restore review state
M.load_state = state.restore

--- Clear saved state
M.clear_state = state.clear

return M
