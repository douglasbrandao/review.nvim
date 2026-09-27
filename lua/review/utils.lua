local M = {}

---@param path string
---@return boolean
function M.is_absolute(path)
	return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil or path:sub(1, 2) == "\\\\"
end

---Normalize a filesystem path without requiring it to exist.
---@param path string
---@return string
function M.normalize(path)
	if path == "" then
		return ""
	end
	local absolute = vim.fn.fnamemodify(path, ":p")
	local normalized = vim.fs.normalize(absolute)
	if normalized == "/" or normalized:match("^%a:/$") then
		return normalized
	end
	return normalized:gsub("/$", "")
end

---Return a path relative to root, or the original path when it is outside root.
---@param path string
---@param root string
---@return string
function M.relative(path, root)
	path = M.normalize(path)
	root = M.normalize(root)
	if path == root then
		return "."
	end
	local prefix = root .. "/"
	if path:sub(1, #prefix) == prefix then
		return path:sub(#prefix + 1)
	end
	return path
end

---Split a string while preserving empty fields.
---@param value string
---@param separator string
---@return string[]
function M.split(value, separator)
	local result = {}
	local start = 1
	while true do
		local first, last = value:find(separator, start, true)
		if not first then
			table.insert(result, value:sub(start))
			break
		end
		table.insert(result, value:sub(start, first - 1))
		start = last + 1
	end
	return result
end

---@param value string
---@return string
function M.trim(value)
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param value string
---@param max_width number
---@return string
function M.truncate(value, max_width)
	if max_width <= 0 then
		return ""
	end
	if vim.fn.strdisplaywidth(value) <= max_width then
		return value
	end
	if max_width == 1 then
		return "…"
	end
	local available = max_width - 1
	local output = ""
	for character in value:gmatch("[\1-\127\194-\244][\128-\191]*") do
		if vim.fn.strdisplaywidth(output .. character) > available then
			break
		end
		output = output .. character
	end
	return output .. "…"
end

return M
