local socket = require("lunet.socket")

local M = {}

function M.write_frame(client, kind, id, payload)
    local header = string.format("%s %s %d\n", kind, id, #payload)
    local err = socket.write(client, header)
    if err then return false, err end
    
    err = socket.write(client, payload)
    if err then return false, err end
    
    return true
end

function M.read_frame(reader)
    local line, err = reader:read_line()
    if not line then return nil, err end

    local kind, id, len_str = line:match("^(%S+)%s+(%S+)%s+(%d+)$")
    if not kind then
        return nil, "bad header: " .. tostring(line)
    end

    local len = tonumber(len_str)
    local payload, perr = reader:read_exact(len)
    if not payload then return nil, perr end

    return { kind = kind, id = id, payload = payload }
end

return M
