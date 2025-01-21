local M = {}

function M.has_value(tbl, value)
	for _, v in pairs(tbl) do
		if v.buf_id == value then
			return true
		end
	end
	return false
end

function M.split(s, sep)
	local tbl = {}
	local idx = 1
	for str in string.gmatch(s, "([^" .. sep .. "]+)") do
		tbl[idx] = str
		idx = idx + 1
	end
	return tbl
end

return M
