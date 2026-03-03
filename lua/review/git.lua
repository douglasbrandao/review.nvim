-- review/git.lua
-- Git integration functions for review.nvim

local M = {}

-- Store the current merge base for diff stats
M.current_merge_base = nil

--- Get the git root directory
---@return string|nil
function M.get_root()
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

--- Get the current branch name
---@return string|nil
function M.get_current_branch()
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

--- Get the default branch (main or master)
---@return string
function M.get_default_branch()
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

--- Get diff stats (additions/deletions) for a specific file
---@param filepath string Absolute path to the file
---@param merge_base string|nil The merge base commit
---@return table|nil {additions: number, deletions: number}
function M.get_file_diff_stats(filepath, merge_base)
	if not merge_base then
		return nil
	end

	local git_root = M.get_root()
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

--- Get diff stats for all files in a batch (more efficient)
---@param merge_base string|nil The merge base commit
---@return table Map of filepath to {additions: number, deletions: number}
function M.get_all_diff_stats(merge_base)
	if not merge_base then
		return {}
	end

	local git_root = M.get_root()
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

--- Get files modified in current branch compared to base branch
---@param base_branch string|nil Base branch to compare against
---@return table List of absolute file paths
function M.get_diff_files(base_branch)
	local git_root = M.get_root()
	if not git_root then
		vim.notify("Not in a git repository", vim.log.levels.ERROR)
		return {}
	end

	-- Use the provided base branch or detect the default
	base_branch = base_branch or M.get_default_branch()

	-- Get the merge base between current branch and base branch
	local merge_base_cmd = string.format("git merge-base %s HEAD 2>/dev/null", base_branch)
	local handle = io.popen(merge_base_cmd)
	if not handle then
		vim.notify("Failed to get merge base", vim.log.levels.ERROR)
		return {}
	end
	local merge_base = handle:read("*a"):gsub("%s+$", "")
	handle:close()

	if merge_base == "" then
		vim.notify(string.format("Could not find merge base with '%s'", base_branch), vim.log.levels.ERROR)
		return {}
	end

	-- Store the merge base for later use
	M.current_merge_base = merge_base

	-- Get the list of changed files
	local diff_cmd = string.format("git diff --name-only %s HEAD 2>/dev/null", merge_base)
	handle = io.popen(diff_cmd)
	if not handle then
		vim.notify("Failed to get diff", vim.log.levels.ERROR)
		return {}
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

return M
