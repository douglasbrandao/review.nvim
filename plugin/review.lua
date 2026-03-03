-- plugin/review.lua
-- This file is loaded automatically by Neovim

-- Guard to prevent loading the plugin twice
if vim.g.loaded_review then
	return
end
vim.g.loaded_review = true

-- Create user commands that lazy-load the plugin
vim.api.nvim_create_user_command("ReviewAdd", function()
	require("review").mark_buffer()
end, {
	desc = "Add current buffer to review list",
})

vim.api.nvim_create_user_command("ReviewRemove", function()
	require("review").unmark_buffer()
end, {
	desc = "Remove current buffer from review list",
})

vim.api.nvim_create_user_command("ReviewList", function()
	require("review").show_buffers()
end, {
	desc = "Show all buffers in review list",
})

vim.api.nvim_create_user_command("ReviewToggle", function()
	require("review").mark_file_as_reviewed()
end, {
	desc = "Toggle reviewed status of current buffer",
})

vim.api.nvim_create_user_command("ReviewClear", function()
	require("review").clear_all_buffers()
end, {
	desc = "Clear all buffers from review list",
})

vim.api.nvim_create_user_command("ReviewGitDiff", function(opts)
	local base_branch = opts.args ~= "" and opts.args or nil
	require("review").populate_from_git_diff(base_branch)
end, {
	desc = "Populate review list from git diff (optional: specify base branch)",
	nargs = "?",
	complete = function()
		-- Provide branch name completion
		local handle = io.popen("git branch --format='%(refname:short)' 2>/dev/null")
		if not handle then
			return {}
		end
		local branches = {}
		for line in handle:lines() do
			table.insert(branches, line)
		end
		handle:close()
		return branches
	end,
})

vim.api.nvim_create_user_command("ReviewNext", function()
	require("review").goto_next_unreviewed()
end, {
	desc = "Go to next unreviewed file",
})

vim.api.nvim_create_user_command("ReviewPrev", function()
	require("review").goto_prev_unreviewed()
end, {
	desc = "Go to previous unreviewed file",
})

vim.api.nvim_create_user_command("ReviewSave", function()
	require("review").save_state()
	vim.notify("Review state saved", vim.log.levels.INFO)
end, {
	desc = "Save review state to file",
})

vim.api.nvim_create_user_command("ReviewLoad", function()
	require("review").load_state()
end, {
	desc = "Load review state from file",
})

vim.api.nvim_create_user_command("ReviewClearState", function()
	require("review").clear_state()
end, {
	desc = "Clear saved review state file",
})

-- Auto-setup with default config if user doesn't call setup() manually
vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		-- Only auto-setup if user hasn't configured it yet
		if not vim.g.review_configured then
			require("review").setup()
		end
	end,
})
