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

M.dmz = {
    unix_socket = os.getenv("UNIX_SOCKET") or "/tmp/backproxy.sock",
    http_host = os.getenv("HTTP_HOST") or "127.0.0.1",
    http_port = tonumber(os.getenv("HTTP_PORT") or "8080"),
    backflow_host = os.getenv("BACKFLOW_HOST") or "127.0.0.1",
    backflow_port = tonumber(os.getenv("BACKFLOW_PORT") or "9000"),
}

M.internal = {
    dmz_host = os.getenv("DMZ_HOST") or "127.0.0.1",
    dmz_port = tonumber(os.getenv("BACKFLOW_PORT") or "9000"),
    workers = tonumber(os.getenv("WORKERS") or tostring(default_workers)),
    service_name = os.getenv("SERVICE_NAME") or "conduit",
}

return M
