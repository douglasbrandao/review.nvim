local function fail(message)
	error(message, 2)
end

local function equal(expected, actual, message)
	if not vim.deep_equal(expected, actual) then
		fail(string.format("%s\nexpected: %s\nactual:   %s", message or "values differ", vim.inspect(expected), vim.inspect(actual)))
	end
end

local function truthy(value, message)
	if not value then
		fail(message or "expected a truthy value")
	end
end

local function command(root, args)
	local cmd = { "git", "-C", root }
	vim.list_extend(cmd, args)
	local result = vim.system(cmd, { text = true }):wait()
	if result.code ~= 0 then
		fail(string.format("command failed: %s\n%s", table.concat(cmd, " "), result.stderr or ""))
	end
	return result.stdout
end

local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")

local ok, error_message = xpcall(function()
	command(temporary, { "init", "-b", "main" })
	command(temporary, { "config", "user.name", "review.nvim tests" })
	command(temporary, { "config", "user.email", "review@example.invalid" })
	vim.fn.writefile({ "before" }, temporary .. "/changed file.txt")
	vim.fn.writefile({ "renamed" }, temporary .. "/old name.txt")
	vim.fn.writefile({ "deleted" }, temporary .. "/gone.txt")
	command(temporary, { "add", "." })
	command(temporary, { "commit", "-m", "base" })
	command(temporary, { "checkout", "-b", "feature" })
	vim.fn.writefile({ "after", "another line" }, temporary .. "/changed file.txt")
	command(temporary, { "mv", "old name.txt", "new name.txt" })
	command(temporary, { "rm", "gone.txt" })
	command(temporary, { "add", "." })
	command(temporary, { "commit", "-m", "feature changes" })

	vim.cmd.cd(vim.fn.fnameescape(temporary))
	local review = require("review")
	review.setup({
		keymaps = { enable = false },
		persistence = { filename = ".git/review-test-state.json" },
	})

	local git = require("review.git")
	local entries, context = git.get_diff("main", temporary)
	truthy(entries, context)
	equal(3, #entries, "git diff should contain modified, renamed and deleted files")
	equal(temporary, context.root, "repository root should be normalized")
	equal("feature", git.get_current_branch(temporary), "current branch should be detected")

	local by_status = {}
	for _, entry in ipairs(entries) do
		by_status[entry.status] = entry
	end
	truthy(by_status.M and by_status.M.diff_stats, "modified file should have diff stats")
	equal(2, by_status.M.diff_stats.additions, "modified additions should be parsed")
	equal(1, by_status.M.diff_stats.deletions, "modified deletions should be parsed")
	equal("old name.txt", by_status.R.old_path, "rename source should be retained")
	equal("new name.txt", by_status.R.relative_path, "rename destination should be retained")
	equal("gone.txt", by_status.D.relative_path, "deleted files should remain reviewable")

	local state = require("review.state")
	state.buffers = entries
	state.context = context
	for _, entry in ipairs(state.buffers) do
		entry.is_marked = entry.status == "M"
	end
	truthy(state.save(), "state should save successfully")
	state.buffers = {}
	state.context = { root = temporary }
	truthy(state.restore({ silent = true }), "state should restore successfully")
	equal(3, #state.buffers, "all entries, including deletion, should restore")
	equal(1, state.get_stats().reviewed, "reviewed status should survive persistence")

	local deleted_index
	for index, entry in ipairs(state.buffers) do
		if entry.status == "D" then
			deleted_index = index
		end
	end
	truthy(state.open(deleted_index), "deleted file should open from the merge-base snapshot")
	equal("nofile", vim.bo.buftype, "deleted file should use a scratch buffer")
	equal("deleted", vim.api.nvim_buf_get_lines(0, 0, 1, false)[1], "deleted file should show its old contents")

	state.populate_from_git_diff("main")
	equal(1, state.get_stats().reviewed, "refreshing the same commit should retain progress")
	vim.fn.writefile({ "after", "another line", "new commit" }, temporary .. "/changed file.txt")
	command(temporary, { "add", "changed file.txt" })
	command(temporary, { "commit", "-m", "new revision" })
	state.populate_from_git_diff("main")
	equal(0, state.get_stats().reviewed, "a new HEAD should invalidate old reviewed marks")
	local modified_index
	for index, entry in ipairs(state.buffers) do
		if entry.status == "M" then
			modified_index = index
		end
	end
	truthy(state.open(modified_index), "a lazily-created file buffer should open")
	equal(temporary .. "/changed file.txt", vim.api.nvim_buf_get_name(0), "opened file should match the selected entry")
	require("review.ui").show_buffers()
	local window_config = vim.api.nvim_win_get_config(0)
	equal("editor", window_config.relative, "review list should open in a floating window")
	truthy(window_config.width <= vim.o.columns, "review list should fit the editor width")
	vim.api.nvim_win_close(0, true)

	local config = require("review.config")
	config.setup({ window = { width = 42 } })
	equal(42, config.options.window.width, "nested user configuration should override defaults")
	equal(30, config.options.window.height, "nested defaults should remain intact")
end, debug.traceback)

vim.fn.delete(temporary, "rf")
if not ok then
	vim.api.nvim_err_writeln(error_message)
	vim.cmd("cquit 1")
else
	print("review.nvim tests: OK")
	vim.cmd("qa!")
end
