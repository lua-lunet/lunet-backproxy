local M = {}

local CACHE_TTL = 30
local cache = {}

local function is_ipv4(s)
    if not s:match("^%d+%.%d+%.%d+%.%d+$") then
        return false
    end
    for part in s:gmatch("%d+") do
        local n = tonumber(part)
        if not n or n > 255 then
            return false
        end
    end
    return true
end

local function resolve_getent(name)
    local handle = io.popen("getent hosts '" .. name .. "' 2>/dev/null")
    if not handle then
        return nil
    end
    local output = handle:read("*a") or ""
    handle:close()
    for line in output:gmatch("[^\r\n]+") do
        for token in line:gmatch("%S+") do
            if is_ipv4(token) then
                return token
            end
        end
    end
    return nil
end

local function resolve_etc_hosts(name)
    local f = io.open("/etc/hosts", "r")
    if not f then
        return nil
    end
    local content = f:read("*a") or ""
    f:close()
    for line in content:gmatch("[^\r\n]+") do
        line = line:gsub("#.*$", "")
        local ip, rest = line:match("^%s*(%S+)%s+(.*)$")
        if ip and is_ipv4(ip) then
            for alias in rest:gmatch("%S+") do
                if alias == name then
                    return ip
                end
            end
        end
    end
    return nil
end

function M.resolve(host)
    if type(host) ~= "string" or host == "" then
        return nil, "invalid host"
    end
    if host:match("^%d+%.%d+%.%d+%.%d+$") then
        return host
    end
    if host == "localhost" then
        return "127.0.0.1"
    end

    local now = os.time()
    local entry = cache[host]
    if entry and (now - entry.at) < CACHE_TTL then
        return entry.ip
    end

    local ip
    if host:match("^[A-Za-z0-9._-]+$") then
        ip = resolve_getent(host)
    end
    if not ip then
        ip = resolve_etc_hosts(host)
    end
    if not ip then
        return nil, "cannot resolve host: " .. host
    end

    cache[host] = { ip = ip, at = now }
    return ip
end

return M
