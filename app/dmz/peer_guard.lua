local socket = require("lunet.socket")

local M = {}

local function is_linux()
    local p = io.popen("uname -s 2>/dev/null")
    if not p then return false end
    local out = p:read("*l")
    p:close()
    return out == "Linux"
end

local function starts_with(value, prefix)
    return type(value) == "string" and type(prefix) == "string"
        and string.sub(value, 1, #prefix) == prefix
end

local function any_prefix_match(value, prefixes)
    if not prefixes or #prefixes == 0 then
        return true
    end
    for _, p in ipairs(prefixes) do
        if starts_with(value, p) then
            return true
        end
    end
    return false
end

local function in_int_list(value, allowed)
    if not allowed or #allowed == 0 then
        return true
    end
    if value == nil then
        return false
    end
    for _, n in ipairs(allowed) do
        if value == n then
            return true
        end
    end
    return false
end

local function read_linux_proc(pid)
    local info = { pid = pid }
    local exe = io.popen(string.format("readlink /proc/%d/exe 2>/dev/null", pid))
    if exe then
        info.exe = exe:read("*l") or ""
        exe:close()
    end

    local f = io.open(string.format("/proc/%d/cmdline", pid), "rb")
    if f then
        local raw = f:read("*a") or ""
        f:close()
        info.cmdline = raw:gsub("%z", " ")
    end
    return info
end

local function detect_peer_cred(client)
    if type(socket.getpeercred) ~= "function" then
        return nil, "socket.getpeercred unavailable in runtime"
    end

    local ok, a, b, c = pcall(socket.getpeercred, client)
    if not ok then
        return nil, tostring(a)
    end

    if type(a) == "table" then
        return {
            pid = tonumber(a.pid),
            uid = tonumber(a.uid),
            gid = tonumber(a.gid),
            source = "table",
        }, nil
    end

    if type(a) == "number" then
        return {
            pid = tonumber(a),
            uid = tonumber(b),
            gid = tonumber(c),
            source = "tuple",
        }, nil
    end

    return nil, "unrecognized getpeercred return shape"
end

local function mode_value(raw)
    raw = (raw or "off"):lower()
    if raw ~= "off" and raw ~= "log" and raw ~= "enforce" then
        return "off"
    end
    return raw
end

local function evaluate_peer(peer, opts, runtime)
    runtime = runtime or {}
    local mode = mode_value(opts.peer_verify_mode)
    if mode == "off" then
        return true, nil
    end

    local expect_transport = opts.peer_expect_transport
    if expect_transport and expect_transport ~= "" and peer.transport ~= expect_transport then
        return false, string.format("unexpected peer transport=%s expected=%s",
            tostring(peer.transport), tostring(expect_transport))
    end

    if not in_int_list(peer.uid, opts.peer_allowed_uids) then
        return false, string.format("peer uid not allowed uid=%s", tostring(peer.uid))
    end
    if not in_int_list(peer.gid, opts.peer_allowed_gids) then
        return false, string.format("peer gid not allowed gid=%s", tostring(peer.gid))
    end

    local needs_proc = (opts.peer_exe_prefixes and #opts.peer_exe_prefixes > 0)
        or (opts.peer_cmdline_prefixes and #opts.peer_cmdline_prefixes > 0)
    if needs_proc then
        local linux_check = runtime.is_linux
        local on_linux = (linux_check == nil) and is_linux() or (linux_check == true)
        if not on_linux then
            return false, "exe/cmdline peer checks require Linux /proc"
        end
        if not peer.pid then
            return false, "peer pid unavailable for Linux /proc checks"
        end
        local proc_reader = runtime.proc_reader or read_linux_proc
        local proc_info = proc_reader(peer.pid)
        peer.exe = proc_info and proc_info.exe or nil
        peer.cmdline = proc_info and proc_info.cmdline or nil

        if not any_prefix_match(peer.exe or "", opts.peer_exe_prefixes) then
            return false, string.format("peer exe prefix mismatch exe=%s", tostring(peer.exe))
        end
        if not any_prefix_match(peer.cmdline or "", opts.peer_cmdline_prefixes) then
            return false, string.format("peer cmdline prefix mismatch cmdline=%s", tostring(peer.cmdline))
        end
    end

    return true, nil
end

function M.authorize(client, opts, runtime)
    opts = opts or {}
    runtime = runtime or {}

    local peer_name, perr = socket.getpeername(client)
    local transport = "unknown"
    if peer_name == "unix" then
        transport = "unix"
    elseif type(peer_name) == "string" and peer_name:find(":") then
        transport = "tcp"
    end

    local cred, cerr = detect_peer_cred(client)
    local peer = {
        name = peer_name,
        transport = transport,
        pid = cred and cred.pid or nil,
        uid = cred and cred.uid or nil,
        gid = cred and cred.gid or nil,
        cred_error = cerr,
        peer_error = perr,
    }

    local ok, reason = evaluate_peer(peer, opts, runtime)
    local mode = mode_value(opts.peer_verify_mode)
    if ok then
        return true, peer, nil
    end

    if mode == "log" then
        return true, peer, reason
    end
    return false, peer, reason
end

function M._evaluate_for_test(peer, opts, runtime)
    return evaluate_peer(peer, opts or {}, runtime or {})
end

return M
