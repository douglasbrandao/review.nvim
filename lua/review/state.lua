local config = require("review.config")
local git = require("review.git")
local utils = require("review.utils")

local M = {
	buffers = {}, -- Kept as the public name for backward compatibility.
	context = {},
}

---@param buf_id number|nil
---@return boolean
function M.is_valid_buffer(buf_id)
	return type(buf_id) == "number" and vim.api.nvim_buf_is_valid(buf_id)
end

---Forget dead buffer handles without dropping files from the review.
function M.cleanup_invalid_buffers()
	for _, entry in ipairs(M.buffers) do
		if entry.buf_id and not M.is_valid_buffer(entry.buf_id) then
			entry.buf_id = nil
		end
	end
end

---@param root string
---@return string
local function get_state_file_path(root)
	local filename = config.options.persistence.filename
	if filename and filename ~= "" then
		if utils.is_absolute(filename) then
			return vim.fs.normalize(filename)
		end
		return vim.fs.normalize(root .. "/" .. filename)
	end
	local directory = vim.fn.stdpath("state") .. "/review.nvim"
	return directory .. "/" .. vim.fn.sha256(utils.normalize(root)) .. ".json"
end

---@param root string|nil
---@return string|nil
local function resolve_root(root)
	return root or M.context.root or git.get_root()
end

---@return boolean
function M.save()
	if not config.options.persistence.enable then
		return false
	end
	local root = resolve_root()
	if not root then
		vim.notify("Cannot save review state outside a git repository", vim.log.levels.ERROR)
		return false
	end

	local files = {}
	for _, entry in ipairs(M.buffers) do
		table.insert(files, {
			path = entry.relative_path or utils.relative(entry.filepath, root),
			old_path = entry.old_path,
			status = entry.status,
			reviewed = entry.is_marked == true,
			diff_stats = entry.diff_stats,
		})
	end
	local payload = {
		version = 2,
		root = root,
		base = M.context.base,
		merge_base = M.context.merge_base,
		head = M.context.head,
		files = files,
	}
	local encoded_ok, encoded = pcall(vim.json.encode, payload)
	if not encoded_ok then
		vim.notify("Failed to serialize review state: " .. tostring(encoded), vim.log.levels.ERROR)
		return false
	end

	local state_file = get_state_file_path(root)
	local directory = vim.fs.dirname(state_file)
	if vim.fn.mkdir(directory, "p") == 0 and vim.fn.isdirectory(directory) == 0 then
		vim.notify("Failed to create review state directory: " .. directory, vim.log.levels.ERROR)
		return false
	end
	local temporary = state_file .. ".tmp." .. vim.fn.getpid()
	local write_ok, write_error = pcall(vim.fn.writefile, { encoded }, temporary, "b")
	if not write_ok then
		vim.notify("Failed to save review state: " .. tostring(write_error), vim.log.levels.ERROR)
		return false
	end
	local renamed, rename_error = os.rename(temporary, state_file)
	if not renamed then
		os.remove(temporary)
		vim.notify("Failed to finalize review state: " .. tostring(rename_error), vim.log.levels.ERROR)
		return false
	end
	return true
end

---@param root string|nil
---@return table|nil
function M.load(root)
	if not config.options.persistence.enable then
		return nil
	end
	root = resolve_root(root)
	if not root then
		return nil
	end
	local state_file = get_state_file_path(root)
	local read_ok, lines = pcall(vim.fn.readfile, state_file, "b")
	if not read_ok or #lines == 0 then
		-- Read version 1's old default location as a migration path.
		if config.options.persistence.filename == nil then
			read_ok, lines = pcall(vim.fn.readfile, root .. "/.review-state.json", "b")
		end
		if not read_ok or #lines == 0 then
			return nil
		end
	end
	local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok or type(decoded) ~= "table" or type(decoded.files) ~= "table" then
		vim.notify("Failed to parse review state file", vim.log.levels.WARN)
		return nil
	end
	return decoded
end

---@param saved table
---@param context table
---@return boolean
local function same_revision(saved, context)
	return saved.merge_base == context.merge_base and saved.head == context.head
end

---@param files table[]
---@return table<string, boolean>
local function reviewed_by_path(files)
	local reviewed = {}
	for _, file in ipairs(files or {}) do
		local path = file.path or file.relative_path or file.filepath
		if path then
			reviewed[path] = file.reviewed == true or file.is_marked == true
		end
	end
	return reviewed
end

---@param opts table|nil
---@return boolean
function M.restore(opts)
	opts = opts or {}
	local root = resolve_root(opts.root)
	local saved = M.load(root)
	if not saved then
		if not opts.silent then
			vim.notify("No saved review state found", vim.log.levels.INFO)
		end
		return false
	end
	if saved.root and utils.normalize(saved.root) ~= utils.normalize(root) then
		if not opts.silent then
			vim.notify("Saved review state belongs to a different repository", vim.log.levels.WARN)
		end
		return false
	end

	local restored = {}
	local skipped = 0
	for _, file in ipairs(saved.files) do
		local relative_path = file.path or file.relative_path
		if not relative_path and file.filepath then
			relative_path = utils.relative(file.filepath, root)
		end
		if relative_path then
			local filepath = utils.is_absolute(relative_path) and relative_path or (root .. "/" .. relative_path)
			filepath = utils.normalize(filepath)
			if file.status == "D" or vim.fn.filereadable(filepath) == 1 then
				local existing = vim.fn.bufnr(filepath)
				table.insert(restored, {
					buf_id = existing > 0 and existing or nil,
					filepath = filepath,
					relative_path = relative_path,
					old_path = file.old_path,
					status = file.status or "M",
					is_marked = file.reviewed == true or file.is_marked == true,
					diff_stats = file.diff_stats,
				})
			else
				skipped = skipped + 1
			end
		end
	end
	M.buffers = restored
	M.context = {
		root = root,
		base = saved.base,
		merge_base = saved.merge_base,
		head = saved.head,
	}
	git.current_root = root
	git.current_base = saved.base
	git.current_merge_base = saved.merge_base
	git.current_head = saved.head

	if not opts.silent then
		local message = string.format("Restored %d file(s) from review state", #restored)
		if skipped > 0 then
			message = message .. string.format(" (%d missing file(s) skipped)", skipped)
		end
		vim.notify(message, vim.log.levels.INFO)
	end
	return true
end

function M.clear()
	local root = resolve_root()
	if not root then
		vim.notify("No repository found", vim.log.levels.WARN)
		return
	end
	local files = { get_state_file_path(root) }
	if config.options.persistence.filename == nil then
		table.insert(files, root .. "/.review-state.json")
	end
	for _, state_file in ipairs(files) do
		if vim.fn.filereadable(state_file) == 1 then
			local removed, error_message = os.remove(state_file)
			if not removed then
				vim.notify("Failed to clear review state: " .. tostring(error_message), vim.log.levels.ERROR)
				return
			end
		end
	end
	vim.notify("Review state cleared", vim.log.levels.INFO)
end

function M.auto_save()
	if config.options.persistence.enable and config.options.persistence.auto_save then
		M.save()
	end
end

---@param entry table
---@return number|nil, string|nil
function M.ensure_buffer(entry)
	if M.is_valid_buffer(entry.buf_id) then
		return entry.buf_id, nil
	end
	if entry.status == "D" then
		local relative_path = entry.old_path or entry.relative_path
		local content
		if entry.diff_stats and entry.diff_stats.binary then
			content = string.format("Binary file deleted: %s", relative_path)
		else
			local error_message
			content, error_message = git.show_file(M.context.root, M.context.merge_base, relative_path)
			if not content then
				return nil, error_message or "Could not load deleted file"
			end
		end
		local buffer = vim.api.nvim_create_buf(true, true)
		local name = string.format("review://%s/%s", (M.context.merge_base or "base"):sub(1, 8), relative_path)
		pcall(vim.api.nvim_buf_set_name, buffer, name)
		local lines = vim.split(content, "\n", { plain = true })
		if lines[#lines] == "" then
			table.remove(lines)
		end
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
		vim.bo[buffer].buftype = "nofile"
		vim.bo[buffer].bufhidden = "wipe"
		vim.bo[buffer].swapfile = false
		vim.bo[buffer].modifiable = false
		vim.bo[buffer].readonly = true
		local filetype = vim.filetype.match({ filename = relative_path })
		if filetype then
			vim.bo[buffer].filetype = filetype
		end
		entry.buf_id = buffer
		return buffer, nil
	end
	if vim.fn.filereadable(entry.filepath) ~= 1 then
		return nil, "File no longer exists: " .. entry.relative_path
	end
	local buffer = vim.fn.bufadd(entry.filepath)
	vim.bo[buffer].buflisted = true
	entry.buf_id = buffer
	return buffer, nil
end

---@param index number
---@return boolean
function M.open(index)
	local entry = M.buffers[index]
	if not entry then
		return false
	end
	local buffer, error_message = M.ensure_buffer(entry)
	if not buffer then
		vim.notify(error_message, vim.log.levels.ERROR)
		return false
	end
	local ok, set_error = pcall(vim.api.nvim_set_current_buf, buffer)
	if not ok then
		vim.notify("Failed to open review file: " .. tostring(set_error), vim.log.levels.ERROR)
		return false
	end
	return true
end

function M.add_buffer()
	local current_buffer = vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(current_buffer)
	if filepath == "" or vim.bo[current_buffer].buftype ~= "" then
		vim.notify("Only file buffers can be added to a review", vim.log.levels.WARN)
		return
	end
	filepath = utils.normalize(filepath)
	for _, entry in ipairs(M.buffers) do
		if entry.filepath == filepath then
			vim.notify("File is already in the review list", vim.log.levels.WARN)
			return
		end
	end
	local root = git.get_root(filepath) or vim.fn.getcwd()
	if not M.context.root then
		M.context.root = root
	end
	table.insert(M.buffers, {
		buf_id = current_buffer,
		is_marked = false,
		filepath = filepath,
		relative_path = utils.relative(filepath, M.context.root),
		status = "M",
	})
	vim.notify("File added to review list", vim.log.levels.INFO)
	M.auto_save()
end

function M.remove_buffer()
	local index = M.get_current_buffer_index()
	if not index then
		vim.notify("File is not in the review list", vim.log.levels.WARN)
		return
	end
	table.remove(M.buffers, index)
	vim.notify("File removed from review list", vim.log.levels.INFO)
	M.auto_save()
end

---@param index number
---@param opts table|nil
---@return boolean
function M.toggle_index(index, opts)
	local entry = M.buffers[index]
	if not entry then
		return false
	end
	entry.is_marked = not entry.is_marked
	M.auto_save()
	if not (opts and opts.silent) then
		vim.notify("File marked as " .. (entry.is_marked and "reviewed" or "not reviewed"), vim.log.levels.INFO)
	end
	return true
end

function M.toggle_reviewed()
	local index = M.get_current_buffer_index()
	if not index then
		vim.notify("File is not in the review list", vim.log.levels.WARN)
		return
	end
	M.toggle_index(index)
end

function M.clear_all()
	local count = #M.buffers
	M.buffers = {}
	vim.notify(string.format("Cleared %d file(s) from review list", count), vim.log.levels.INFO)
	M.auto_save()
end

---@param base_branch string|nil
function M.populate_from_git_diff(base_branch)
	local repository_hint
	if vim.bo.buftype == "" then
		local current_path = vim.api.nvim_buf_get_name(0)
		repository_hint = current_path ~= "" and current_path or nil
	end
	repository_hint = repository_hint or M.context.root
	local entries, context_or_error = git.get_diff(base_branch, repository_hint)
	if not entries then
		vim.notify(context_or_error, vim.log.levels.ERROR)
		return
	end
	local context = context_or_error
	local progress = {}
	if M.context.merge_base == context.merge_base and M.context.head == context.head then
		progress = reviewed_by_path(M.buffers)
	elseif config.options.persistence.enable and config.options.persistence.auto_load then
		local saved = M.load(context.root)
		if saved and same_revision(saved, context) then
			progress = reviewed_by_path(saved.files)
		end
	end

	for _, entry in ipairs(entries) do
		entry.is_marked = progress[entry.relative_path] == true
		local existing = entry.status ~= "D" and vim.fn.bufnr(entry.filepath) or -1
		entry.buf_id = existing > 0 and existing or nil
	end
	M.buffers = entries
	M.context = context
	M.auto_save()

	local branch = git.get_current_branch(context.root) or context.head:sub(1, 8)
	if #entries == 0 then
		vim.notify(string.format("No changes found between %s and %s", context.base, branch), vim.log.levels.INFO)
		return
	end
	vim.notify(string.format("Loaded %d file(s) for review (%s → %s)", #entries, context.base, branch), vim.log.levels.INFO)
end

---@return number|nil
function M.get_current_buffer_index()
	M.cleanup_invalid_buffers()
	local current_buffer = vim.api.nvim_get_current_buf()
	local current_path = vim.api.nvim_buf_get_name(current_buffer)
	if current_path ~= "" and vim.bo[current_buffer].buftype == "" then
		current_path = utils.normalize(current_path)
	end
	for index, entry in ipairs(M.buffers) do
		if entry.buf_id == current_buffer or (current_path ~= "" and entry.filepath == current_path) then
			return index
		end
	end
	return nil
end

---@return table
function M.get_stats()
	local result = { total = #M.buffers, reviewed = 0, additions = 0, deletions = 0 }
	for _, entry in ipairs(M.buffers) do
		if entry.is_marked then
			result.reviewed = result.reviewed + 1
		end
		if entry.diff_stats and not entry.diff_stats.binary then
			result.additions = result.additions + entry.diff_stats.additions
			result.deletions = result.deletions + entry.diff_stats.deletions
		end
	end
	return result
end

return M
