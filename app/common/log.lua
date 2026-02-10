local M = {}

local function now()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function M.info(tag, msg, ...)
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    io.stdout:write(string.format("%s [INFO] [%s] %s\n", now(), tag, msg))
    io.stdout:flush()
end

function M.warn(tag, msg, ...)
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    io.stdout:write(string.format("%s [WARN] [%s] %s\n", now(), tag, msg))
    io.stdout:flush()
end

function M.err(tag, msg, ...)
    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end
    io.stderr:write(string.format("%s [ERR ] [%s] %s\n", now(), tag, msg))
    io.stderr:flush()
end

return M
