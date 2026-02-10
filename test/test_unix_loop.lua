io.stdout:setvbuf('no')
local lunet = require("lunet")
local socket = require("lunet.socket")

local SOCK_PATH = "/tmp/backproxy-test-unix.sock"

os.remove(SOCK_PATH)

lunet.spawn(function()
    local listener, err = socket.listen("unix", SOCK_PATH, 0)
    if not listener then
        print("FAIL: unix listen error: " .. tostring(err))
        os.exit(1)
    end
    print("OK: unix listener created on " .. SOCK_PATH)

    lunet.spawn(function()
        lunet.sleep(500)
        local client, cerr = socket.connect(SOCK_PATH, 0)
        if not client then
            print("FAIL: connect error: " .. tostring(cerr))
            os.exit(1)
        end
        print("OK: connected to unix socket")
        socket.write(client, "GET /health HTTP/1.0\r\nHost: localhost\r\n\r\n")
        print("OK: wrote request")
        local data = socket.read(client)
        print("OK: got response: " .. tostring(data))
        socket.close(client)
        
        socket.close(listener)
        os.remove(SOCK_PATH)
        print("PASS: unix socket loop works")
        os.exit(0)
    end)

    local client, aerr = socket.accept(listener)
    if not client then
        print("FAIL: accept error: " .. tostring(aerr))
        os.exit(1)
    end
    print("OK: accepted connection")
    
    local data = socket.read(client)
    print("OK: read from client: " .. tostring(data):sub(1, 50))
    
    socket.write(client, "HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok")
    socket.close(client)
    print("OK: sent response")
end)
