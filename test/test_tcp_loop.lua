io.stdout:setvbuf('no')
local lunet = require("lunet")
local socket = require("lunet.socket")

local TCP_HOST = "127.0.0.1"
local TCP_PORT = 19000

lunet.spawn(function()
    local listener, err = socket.listen("tcp", TCP_HOST, TCP_PORT)
    if not listener then
        print("FAIL: tcp listen error: " .. tostring(err))
        os.exit(1)
    end
    print("OK: tcp listener created on " .. TCP_HOST .. ":" .. TCP_PORT)

    lunet.spawn(function()
        lunet.sleep(500)
        local client, cerr = socket.connect(TCP_HOST, TCP_PORT)
        if not client then
            print("FAIL: connect error: " .. tostring(cerr))
            os.exit(1)
        end
        print("OK: connected to tcp")
        socket.write(client, "HELLO conduit\n")
        print("OK: sent HELLO")
        local data = socket.read(client)
        print("OK: got response: " .. tostring(data))
        socket.close(client)
        
        socket.close(listener)
        print("PASS: tcp loop works")
        os.exit(0)
    end)

    local client, aerr = socket.accept(listener)
    if not client then
        print("FAIL: accept error: " .. tostring(aerr))
        os.exit(1)
    end
    print("OK: accepted tcp connection")
    
    local data = socket.read(client)
    print("OK: read from worker: " .. tostring(data))
    
    socket.write(client, "READY\n")
    socket.close(client)
    print("OK: sent READY")
end)
