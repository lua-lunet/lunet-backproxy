local M = {}

local function read_int_from_cmd(cmd)
    local p = io.popen(cmd)
    if not p then return nil end
    local out = p:read("*l")
    p:close()
    local n = tonumber(out or "")
    if n and n > 0 then return n end
    return nil
end

local function detect_cores()
    return read_int_from_cmd("getconf _NPROCESSORS_ONLN 2>/dev/null")
        or read_int_from_cmd("nproc 2>/dev/null")
        or read_int_from_cmd("sysctl -n hw.ncpu 2>/dev/null")
        or 2
end

local default_workers = math.max(2, detect_cores() * 2)
local function env_int(name, default)
    local raw = os.getenv(name)
    if not raw or raw == "" then
        return default
    end
    local n = tonumber(raw)
    if n == nil then
        return default
    end
    return n
end

M.dmz = {
    unix_socket = os.getenv("UNIX_SOCKET") or "/tmp/backproxy.sock",
    http_host = os.getenv("HTTP_HOST") or "127.0.0.1",
    http_port = env_int("HTTP_PORT", 8080),
    backflow_host = os.getenv("BACKFLOW_HOST") or "127.0.0.1",
    backflow_port = env_int("BACKFLOW_PORT", 9000),
    max_header_lines = env_int("HTTP_MAX_HEADER_LINES", 256),
    max_header_bytes = env_int("HTTP_MAX_HEADER_BYTES", 65536),
    max_line_bytes = env_int("HTTP_MAX_LINE_BYTES", 8192),
    max_body_bytes = env_int("HTTP_MAX_BODY_BYTES", 1048576),
    max_workers_per_service = env_int("BROKER_MAX_WORKERS_PER_SERVICE", 1024),
}

M.internal = {
    dmz_host = os.getenv("DMZ_HOST") or "127.0.0.1",
    dmz_port = env_int("BACKFLOW_PORT", 9000),
    workers = env_int("WORKERS", default_workers),
    service_name = os.getenv("SERVICE_NAME") or "conduit",
}

return M
