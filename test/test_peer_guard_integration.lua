io.stdout:setvbuf("no")
local lunet = require("lunet")
local socket = require("lunet.socket")
local guard = require("app.dmz.peer_guard")

local test_count = 0
local pass_count = 0

local function check(name, condition, detail)
    test_count = test_count + 1
    if condition then
        pass_count = pass_count + 1
        print("PASS: " .. name)
    else
        print("FAIL: " .. name .. " -- " .. tostring(detail or ""))
    end
end

local function is_linux()
    local p = io.popen("uname -s 2>/dev/null")
    if not p then return false end
    local out = p:read("*l")
    p:close()
    return out == "Linux"
end

local function is_darwin()
    local p = io.popen("uname -s 2>/dev/null")
    if not p then return false end
    local out = p:read("*l")
    p:close()
    return out == "Darwin"
end

-- Platform detection
do
    local on_linux = is_linux()
    local on_darwin = is_darwin()
    print("Platform: " .. (on_linux and "Linux" or on_darwin and "Darwin" or "Unknown"))
    check("platform detection", on_linux or on_darwin, "should be Linux or Darwin")
end

local sock_path = "/tmp/test_peer_guard_" .. os.time() .. ".sock"
os.remove(sock_path)

lunet.spawn(function()
    local listener, err = socket.listen("unix", sock_path, 0)
    if not listener then
        check("unix socket listen", false, err)
        os.exit(1)
    end
    check("unix socket listen created", true)

    lunet.spawn(function()
        lunet.sleep(100)
        local client, cerr = socket.connect(sock_path, 0)
        if not client then
            check("unix socket connect", false, cerr)
            os.exit(1)
        end
        check("unix socket connect successful", true)
        socket.close(client)
    end)

    -- Accept connection
    local peer, aerr = socket.accept(listener)
    if not peer then
        check("unix socket accept", false, aerr)
        os.exit(1)
    end
    check("unix socket accept successful", true)

    -- Test: Get peer name
    local peer_name, perr = socket.getpeername(peer)
    local is_unix_transport = peer_name == "unix"
    check("getpeername returns unix", is_unix_transport, peer_name)

    -- Test: Get peer credentials
    if socket.getpeercred then
        local cred, cerr = socket.getpeercred(peer)
        if cred then
            check("getpeercred succeeded", true)

            -- Show what we got
            if type(cred) == "table" then
                print("  >> cred.pid=" .. tostring(cred.pid))
                print("  >> cred.uid=" .. tostring(cred.uid))
                print("  >> cred.gid=" .. tostring(cred.gid))
            elseif type(cred) == "number" then
                print("  >> pid=" .. tostring(cred))
            end
        else
            check("getpeercred succeeded", false, cerr)
        end
    else
        check("getpeercred available", false, "not available in this runtime")
    end

    -- Test: Call authorize with enforcement disabled
    local authorized, peer_info, reason = guard.authorize(peer, {
        peer_verify_mode = "off",
    })
    check("authorize with mode=off allows all", authorized == true, reason)
    if peer_info then
        print("  >> peer.transport=" .. tostring(peer_info.transport))
        print("  >> peer.uid=" .. tostring(peer_info.uid))
        print("  >> peer.gid=" .. tostring(peer_info.gid))
        print("  >> peer.pid=" .. tostring(peer_info.pid))
    end

    -- Test: Call authorize with transport enforcement
    local authorized, peer_info, reason = guard.authorize(peer, {
        peer_verify_mode = "enforce",
        peer_expect_transport = "unix",
    })
    check("authorize enforces transport=unix", authorized == true, reason)

    -- Test: Call authorize with wrong transport expectation
    local authorized, peer_info, reason = guard.authorize(peer, {
        peer_verify_mode = "enforce",
        peer_expect_transport = "tcp",
    })
    check("authorize rejects transport=tcp when unix", authorized == false, reason)

    -- Test: Call authorize with UID allowlist
    if peer_info and peer_info.uid then
        print("  >> testing UID allowlist with uid=" .. peer_info.uid)
        local authorized, peer_info2, reason = guard.authorize(peer, {
            peer_verify_mode = "enforce",
            peer_allowed_uids = { peer_info.uid },
        })
        check("authorize allows current UID", authorized == true, reason)

        -- Test: Deny a different UID
        local authorized, peer_info3, reason = guard.authorize(peer, {
            peer_verify_mode = "enforce",
            peer_allowed_uids = { peer_info.uid + 1000 },
        })
        check("authorize denies different UID", authorized == false, reason)
    end

    -- Test: Log mode returns true but with reason
    local authorized, peer_info4, reason = guard.authorize(peer, {
        peer_verify_mode = "log",
        peer_allowed_uids = { 9999 },
    })
    check("authorize log mode returns true on mismatch", authorized == true, reason)
    check("authorize log mode provides reason", reason ~= nil, reason)

    socket.close(peer)
    socket.close(listener)
    os.remove(sock_path)

    print(string.format("========== %d/%d tests passed ==========", pass_count, test_count))
    if pass_count == test_count then
        os.exit(0)
    else
        os.exit(1)
    end
end)
