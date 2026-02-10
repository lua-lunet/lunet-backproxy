io.stdout:setvbuf('no')
local lunet = require("lunet")
local socket = require("lunet.socket")

local SOCK_PATH = "/tmp/backproxy-test-combined.sock"
local TCP_HOST = "127.0.0.1"
local TCP_PORT = 19001

os.remove(SOCK_PATH)

lunet.spawn(function()
    -- Start unix listener (simulates NGINX -> backproxy)
    local unix_listener, uerr = socket.listen("unix", SOCK_PATH, 0)
    if not unix_listener then
        print("FAIL: unix listen: " .. tostring(uerr))
        os.exit(1)
    end
    print("OK: unix listener on " .. SOCK_PATH)

    -- Start tcp listener (simulates backflow worker connections)
    local tcp_listener, terr = socket.listen("tcp", TCP_HOST, TCP_PORT)
    if not tcp_listener then
        print("FAIL: tcp listen: " .. tostring(terr))
        os.exit(1)
    end
    print("OK: tcp listener on " .. TCP_HOST .. ":" .. TCP_PORT)

    -- Track connected workers
    local workers = {}

    -- Accept TCP workers in background
    lunet.spawn(function()
        while true do
            local client, aerr = socket.accept(tcp_listener)
            if not client then break end
            lunet.spawn(function()
                local data = socket.read(client)
                if data and data:match("^HELLO") then
                    socket.write(client, "READY\n")
                    table.insert(workers, client)
                    print("OK: worker registered, total=" .. #workers)
                else
                    socket.close(client)
                end
            end)
        end
    end)

    -- Accept unix connections (HTTP from NGINX) in background
    lunet.spawn(function()
        while true do
            local client, aerr = socket.accept(unix_listener)
            if not client then break end
            lunet.spawn(function()
                local data = socket.read(client)
                if not data then
                    socket.close(client)
                    return
                end
                
                if #workers == 0 then
                    socket.write(client, "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 18\r\n\r\nno workers ready\r\n")
                    socket.close(client)
                    print("OK: returned 503 (no workers)")
                else
                    socket.write(client, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
                    socket.close(client)
                    print("OK: returned 200 (workers available)")
                end
            end)
        end
    end)

    -- Test sequence
    lunet.spawn(function()
        lunet.sleep(300)

        -- Test 1: HTTP request with no workers -> expect 503
        print("TEST 1: request with no workers connected")
        local c1, e1 = socket.connect(SOCK_PATH, 0)
        if not c1 then print("FAIL: connect: " .. tostring(e1)); os.exit(1) end
        socket.write(c1, "GET /api/test HTTP/1.1\r\nHost: localhost\r\n\r\n")
        local resp1 = socket.read(c1)
        socket.close(c1)
        if resp1 and resp1:match("503") then
            print("PASS: got 503 when no workers")
        else
            print("FAIL: expected 503, got: " .. tostring(resp1):sub(1, 60))
            os.exit(1)
        end

        -- Connect a worker
        print("TEST 2: connect a worker then request")
        local w1, we1 = socket.connect(TCP_HOST, TCP_PORT)
        if not w1 then print("FAIL: worker connect: " .. tostring(we1)); os.exit(1) end
        socket.write(w1, "HELLO conduit\n")
        local wready = socket.read(w1)
        if not wready or not wready:match("READY") then
            print("FAIL: no READY: " .. tostring(wready))
            os.exit(1)
        end
        print("OK: worker connected and got READY")

        lunet.sleep(100)

        -- Test 3: HTTP request with worker available -> expect 200
        local c2, e2 = socket.connect(SOCK_PATH, 0)
        if not c2 then print("FAIL: connect: " .. tostring(e2)); os.exit(1) end
        socket.write(c2, "GET /api/test HTTP/1.1\r\nHost: localhost\r\n\r\n")
        local resp2 = socket.read(c2)
        socket.close(c2)
        if resp2 and resp2:match("200") then
            print("PASS: got 200 when workers available")
        else
            print("FAIL: expected 200, got: " .. tostring(resp2):sub(1, 60))
            os.exit(1)
        end

        -- Cleanup
        socket.close(w1)
        socket.close(unix_listener)
        socket.close(tcp_listener)
        os.remove(SOCK_PATH)
        print("PASS: combined dual-loop test passed")
        os.exit(0)
    end)
end)
