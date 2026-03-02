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
