local utils = require("review.utils")

local M = {
	current_merge_base = nil,
	current_base = nil,
	current_root = nil,
	current_head = nil,
}

---@param args string[]
---@param cwd string|nil
---@return boolean, string, string
local function run(args, cwd)
	local command = { "git" }
	if cwd and cwd ~= "" then
		vim.list_extend(command, { "-C", cwd })
	end
	vim.list_extend(command, args)

	if vim.system then
		local result = vim.system(command, { text = false }):wait()
		return result.code == 0, result.stdout or "", result.stderr or ""
	end

	local output = vim.fn.system(command)
	return vim.v.shell_error == 0, output or "", ""
end

---@param path string|nil
---@return string
local function working_directory(path)
	if not path or path == "" then
		local buffer_path = vim.api.nvim_buf_get_name(0)
		path = buffer_path ~= "" and buffer_path or vim.fn.getcwd()
	end
	path = utils.normalize(path)
	if vim.fn.isdirectory(path) == 0 then
		path = vim.fs.dirname(path)
	end
	return path
end

---Get the repository root containing path (or the current buffer/cwd).
---@param path string|nil
---@return string|nil
function M.get_root(path)
	local ok, stdout = run({ "rev-parse", "--show-toplevel" }, working_directory(path))
	if not ok then
		return nil
	end
	local root = utils.trim(stdout)
	return root ~= "" and utils.normalize(root) or nil
end

---@param root string|nil
---@return string|nil
function M.get_current_branch(root)
	root = root or M.get_root()
	if not root then
		return nil
	end
	local ok, stdout = run({ "branch", "--show-current" }, root)
	if not ok then
		return nil
	end
	local branch = utils.trim(stdout)
	return branch ~= "" and branch or nil
end

---@param root string
---@param ref string
---@return boolean
local function ref_exists(root, ref)
	local ok = run({ "rev-parse", "--verify", "--quiet", "--end-of-options", ref }, root)
	return ok
end

---Detect the remote default branch, with local main/master fallbacks.
---@param root string|nil
---@return string
function M.get_default_branch(root)
	root = root or M.get_root()
	if not root then
		return "main"
	end

	local ok, stdout = run({ "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" }, root)
	local remote_default = utils.trim(stdout)
	if ok and remote_default ~= "" then
		return remote_default
	end

	for _, candidate in ipairs({ "main", "master", "origin/main", "origin/master" }) do
		if ref_exists(root, candidate) then
			return candidate
		end
	end
	return "main"
end

---@param root string|nil
---@return string[]
function M.get_branches(root)
	root = root or M.get_root()
	if not root then
		return {}
	end
	local ok, stdout = run({ "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes" }, root)
	if not ok then
		return {}
	end
	local branches = {}
	local seen = {}
	for line in stdout:gmatch("[^\r\n]+") do
		if not line:match("/HEAD$") and not seen[line] then
			seen[line] = true
			table.insert(branches, line)
		end
	end
	table.sort(branches)
	return branches
end

---@param stdout string
---@return table<string, table>
local function parse_numstat(stdout)
	local stats = {}
	local fields = utils.split(stdout, "\0")
	local index = 1
	while index <= #fields do
		local header = fields[index]
		index = index + 1
		if header == "" then
			break
		end
		local additions, deletions, path = header:match("^([^\t]+)\t([^\t]+)\t(.*)$")
		if additions then
			if path == "" then
				index = index + 1 -- old path
				path = fields[index] or ""
				index = index + 1
			end
			stats[path] = {
				additions = tonumber(additions) or 0,
				deletions = tonumber(deletions) or 0,
				binary = additions == "-" or deletions == "-",
			}
		end
	end
	return stats
end

---@param stdout string
---@param root string
---@param stats table<string, table>
---@return table[]
local function parse_name_status(stdout, root, stats)
	local entries = {}
	local fields = utils.split(stdout, "\0")
	local index = 1
	while index <= #fields do
		local status = fields[index]
		index = index + 1
		if status == "" then
			break
		end
		local old_path
		local path = fields[index]
		index = index + 1
		if status:sub(1, 1) == "R" or status:sub(1, 1) == "C" then
			old_path = path
			path = fields[index]
			index = index + 1
		end
		if path and path ~= "" then
			table.insert(entries, {
				filepath = utils.normalize(root .. "/" .. path),
				relative_path = path,
				old_path = old_path,
				status = status:sub(1, 1),
				diff_stats = stats[path],
			})
		end
	end
	return entries
end

---Return the branch diff and the immutable context used to produce it.
---@param base_branch string|nil
---@param path string|nil
---@return table[]|nil, table|string
function M.get_diff(base_branch, path)
	local root = M.get_root(path)
	if not root then
		return nil, "Not in a git repository"
	end
	local base = base_branch or M.get_default_branch(root)
	local base_ok, base_stdout = run({ "rev-parse", "--verify", "--quiet", "--end-of-options", base .. "^{commit}" }, root)
	local base_commit = utils.trim(base_stdout)
	if not base_ok or base_commit == "" then
		return nil, string.format("Unknown base revision '%s'", base)
	end
	local ok, merge_stdout, merge_stderr = run({ "merge-base", base_commit, "HEAD" }, root)
	local merge_base = utils.trim(merge_stdout)
	if not ok or merge_base == "" then
		local detail = utils.trim(merge_stderr)
		return nil, string.format("Could not find a merge base with '%s'%s", base, detail ~= "" and (": " .. detail) or "")
	end

	local head_ok, head_stdout = run({ "rev-parse", "HEAD" }, root)
	if not head_ok then
		return nil, "Could not resolve HEAD"
	end
	local head = utils.trim(head_stdout)
	local range = merge_base .. ".." .. head
	local stat_ok, stat_stdout, stat_stderr = run({ "diff", "--numstat", "-z", "--find-renames", range, "--" }, root)
	if not stat_ok then
		return nil, "Failed to read diff statistics: " .. utils.trim(stat_stderr)
	end
	local names_ok, names_stdout, names_stderr = run({ "diff", "--name-status", "-z", "--find-renames", range, "--" }, root)
	if not names_ok then
		return nil, "Failed to read changed files: " .. utils.trim(names_stderr)
	end

	local context = { root = root, base = base, merge_base = merge_base, head = head }
	M.current_root = root
	M.current_base = base
	M.current_merge_base = merge_base
	M.current_head = head
	return parse_name_status(names_stdout, root, parse_numstat(stat_stdout)), context
end

---Backward-compatible list of changed absolute paths.
---@param base_branch string|nil
---@return string[]
function M.get_diff_files(base_branch)
	local entries, error_message = M.get_diff(base_branch)
	if not entries then
		vim.notify(error_message, vim.log.levels.ERROR)
		return {}
	end
	local files = {}
	for _, entry in ipairs(entries) do
		table.insert(files, entry.filepath)
	end
	return files
end

---@param root string
---@param revision string
---@param relative_path string
---@return string|nil, string|nil
function M.show_file(root, revision, relative_path)
	local ok, stdout, stderr = run({ "show", revision .. ":" .. relative_path }, root)
	if not ok then
		return nil, utils.trim(stderr)
	end
	return stdout, nil
end

return M
