-- review/config.lua
-- Default configuration for review.nvim

local M = {}

M.defaults = {
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
		show_help = true,
	},
	icons = {
		reviewed = "✓",
		not_reviewed = "○",
	},
	git = {
		default_base = nil, -- nil means auto-detect (main/master)
		show_diff_stats = true, -- Show +/- line stats in the list
	},
	persistence = {
		enable = true, -- Enable automatic state persistence
		filename = nil, -- nil stores state under stdpath("state")/review.nvim
		auto_save = true, -- Auto-save on buffer mark/unmark
		auto_load = true, -- Reuse progress when the compared commit is unchanged
	},
}

-- Current configuration (will be set by init.lua)
M.options = vim.deepcopy(M.defaults)

--- Setup configuration with user options
---@param user_config table|nil User configuration to merge with defaults
function M.setup(user_config)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_config or {})
	return M.options
end

return M
