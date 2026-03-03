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

-- Current configuration (will be set by init.lua)
M.options = vim.deepcopy(M.defaults)

--- Setup configuration with user options
---@param user_config table|nil User configuration to merge with defaults
function M.setup(user_config)
	M.options = vim.tbl_deep_extend("force", M.defaults, user_config or {})
end

return M
