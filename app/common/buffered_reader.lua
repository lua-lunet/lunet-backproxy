local socket = require("lunet.socket")

local BufferedReader = {}
BufferedReader.__index = BufferedReader

function BufferedReader.new(client)
    return setmetatable({
        client = client,
        buffer = "",
    }, BufferedReader)
end

function BufferedReader:fill_buffer()
    local chunk, err = socket.read(self.client)
    if not chunk then
        return nil, err
    end
    self.buffer = self.buffer .. chunk
    return true
end

function BufferedReader:read_line(max_bytes)
    if max_bytes and max_bytes <= 0 then
        max_bytes = nil
    end

    while true do
        local nl_pos = self.buffer:find("\n")
        if nl_pos then
            local line = self.buffer:sub(1, nl_pos - 1)
            -- Handle optional \r
            if line:sub(-1) == "\r" then
                line = line:sub(1, -2)
            end
            if max_bytes and #line > max_bytes then
                return nil, "line too long"
            end
            self.buffer = self.buffer:sub(nl_pos + 1)
            return line
        end

        if max_bytes and #self.buffer > max_bytes then
            return nil, "line too long"
        end

        local ok, err = self:fill_buffer()
        if not ok then
            return nil, err
        end
    end
end

function BufferedReader:read_exact(n)
    while #self.buffer < n do
        local ok, err = self:fill_buffer()
        if not ok then
            return nil, err
        end
    end

    local data = self.buffer:sub(1, n)
    self.buffer = self.buffer:sub(n + 1)
    return data
end

return BufferedReader
