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

local function split_csv(raw)
    local out = {}
    if not raw or raw == "" then
        return out
    end
    for part in string.gmatch(raw, "([^,]+)") do
        local v = part:match("^%s*(.-)%s*$")
        if v and v ~= "" then
            table.insert(out, v)
        end
    end
    return out
end

local function csv_ints(raw)
    local out = {}
    for _, s in ipairs(split_csv(raw)) do
        local n = tonumber(s)
        if n then
            table.insert(out, n)
        end
    end
    return out
end

local function load_selector_policy(path)
    if not path or path == "" then
        return nil, nil
    end

    local chunk, lerr = loadfile(path)
    if not chunk then
        return nil, "failed loading selector policy file: " .. tostring(lerr)
    end

    local ok, result = pcall(chunk)
    if not ok then
        return nil, "failed executing selector policy file: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return nil, "selector policy file must return a Lua table"
    end
    return result, nil
end

local selector_policy_file = os.getenv("HTTP_PEER_SELECTOR_POLICY_FILE") or ""
local selector_policy, selector_policy_err = load_selector_policy(selector_policy_file)
if selector_policy_err then
    error(selector_policy_err)
end

M.dmz = {
    unix_socket = os.getenv("UNIX_SOCKET") or "/tmp/backproxy.sock",
    http_transport = os.getenv("DMZ_HTTP_TRANSPORT") or "tcp",
    http_host = os.getenv("HTTP_HOST") or "127.0.0.1",
    http_port = env_int("HTTP_PORT", 8080),
    backflow_host = os.getenv("BACKFLOW_HOST") or "127.0.0.1",
    backflow_port = env_int("BACKFLOW_PORT", 9000),
    max_header_lines = env_int("HTTP_MAX_HEADER_LINES", 256),
    max_header_bytes = env_int("HTTP_MAX_HEADER_BYTES", 65536),
    max_line_bytes = env_int("HTTP_MAX_LINE_BYTES", 8192),
    max_body_bytes = env_int("HTTP_MAX_BODY_BYTES", 1048576),
    max_workers_per_service = env_int("BROKER_MAX_WORKERS_PER_SERVICE", 1024),
    peer_verify_mode = os.getenv("HTTP_PEER_VERIFY_MODE")
        or (selector_policy and selector_policy.mode)
        or "off",
    peer_expect_transport = os.getenv("HTTP_PEER_EXPECT_TRANSPORT") or "",
    peer_allowed_uids = csv_ints(os.getenv("HTTP_PEER_ALLOWED_UIDS")),
    peer_allowed_gids = csv_ints(os.getenv("HTTP_PEER_ALLOWED_GIDS")),
    peer_exe_prefixes = split_csv(os.getenv("HTTP_PEER_EXE_PREFIXES")),
    peer_cmdline_prefixes = split_csv(os.getenv("HTTP_PEER_CMDLINE_PREFIXES")),
    peer_selector_policy_file = selector_policy_file,
    peer_selectors = (selector_policy and selector_policy.selectors) or {},
}

M.internal = {
    dmz_host = os.getenv("DMZ_HOST") or "127.0.0.1",
    dmz_port = env_int("BACKFLOW_PORT", 9000),
    workers = env_int("WORKERS", default_workers),
    service_name = os.getenv("SERVICE_NAME") or "conduit",
}

return M
