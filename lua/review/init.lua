local config = require("review.config")
local git = require("review.git")
local navigation = require("review.navigation")
local state = require("review.state")
local ui = require("review.ui")

local M = { config = config.options }
local installed_keymaps = {}

local function clear_keymaps()
	for _, lhs in ipairs(installed_keymaps) do
		pcall(vim.keymap.del, "n", lhs)
	end
	installed_keymaps = {}
end

---@param lhs string|false|nil
---@param callback function
---@param description string
local function map(lhs, callback, description)
	if type(lhs) ~= "string" or lhs == "" then
		return
	end
	vim.keymap.set("n", lhs, callback, { desc = description, silent = true })
	table.insert(installed_keymaps, lhs)
end

---@param callback function
---@param action string
---@return function
local function protected(callback, action)
	return function()
		local ok, error_message = pcall(callback)
		if not ok then
			vim.notify(string.format("Review: failed to %s: %s", action, error_message), vim.log.levels.ERROR)
		end
	end
end

---@param user_config table|nil
function M.setup(user_config)
	vim.g.review_configured = true
	config.setup(user_config)
	M.config = config.options
	clear_keymaps()
	if not config.options.keymaps.enable then
		return M.config
	end

	local keys = config.options.keymaps
	map(keys.insert, protected(state.add_buffer, "add file"), "Review: add file")
	map(keys.remove, protected(state.remove_buffer, "remove file"), "Review: remove file")
	map(keys.list, protected(ui.show_buffers, "show files"), "Review: show files")
	map(keys.toggle_reviewed, protected(state.toggle_reviewed, "toggle reviewed state"), "Review: toggle reviewed state")
	map(keys.git_diff, protected(function()
		state.populate_from_git_diff(config.options.git.default_base)
	end, "load git diff"), "Review: load git diff")
	map(keys.next_unreviewed, protected(navigation.goto_next, "open next file"), "Review: next unreviewed file")
	map(keys.prev_unreviewed, protected(navigation.goto_prev, "open previous file"), "Review: previous unreviewed file")
	return M.config
end

M.mark_buffer = state.add_buffer
M.unmark_buffer = state.remove_buffer
M.show_buffers = ui.show_buffers
M.mark_file_as_reviewed = state.toggle_reviewed
M.clear_all_buffers = state.clear_all
M.populate_from_git_diff = state.populate_from_git_diff
M.get_git_diff_files = git.get_diff_files
M.get_current_branch = git.get_current_branch
M.get_default_branch = git.get_default_branch
M.goto_next_unreviewed = navigation.goto_next
M.goto_prev_unreviewed = navigation.goto_prev
M.save_state = state.save
M.load_state = state.restore
M.clear_state = state.clear

return M
