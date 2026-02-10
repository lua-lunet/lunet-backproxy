local M = {}

local function split_lines(s)
    local t = {}
    for line in s:gmatch("([^\r\n]*)\r?\n") do
        table.insert(t, line)
    end
    return t
end

function M.parse_request(raw)
    local head_end, body_start = raw:find("\r?\n\r?\n")
    if not head_end then
        return nil, "malformed http (no header terminator)"
    end

    local head = raw:sub(1, head_end)
    local body = raw:sub(body_start + 1)

    local lines = split_lines(head .. "\n")
    local request_line = lines[1]
    if not request_line then return nil, "missing request line" end

    local method, path, version = request_line:match("^(%S+)%s+(%S+)%s+(HTTP/%d%.%d)$")
    if not method then return nil, "bad request line: " .. request_line end

    local headers = {}
    for i = 2, #lines do
        local k, v = lines[i]:match("^(.-):%s*(.*)$")
        if k then headers[k:lower()] = v end
    end

    return {
        method = method,
        path = path,
        version = version,
        headers = headers,
        body = body or "",
        raw = raw,
    }
end

return M
