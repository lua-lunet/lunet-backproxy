io.stdout:setvbuf("no")
local lunet = require("lunet")
local socket = require("lunet.socket")
local broker = require("app.dmz.broker")
local ingress = require("app.dmz.http_ingress")
local BufferedReader = require("app.common.buffered_reader")

local HOST = "127.0.0.1"
local HTTP_PORT = 19120
local WORKER_PORT = 19121

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

local function status_code(raw)
    return raw and raw:match("^HTTP/%d%.%d%s+(%d+)")
end

local function http_request(raw_request)
    local c, cerr = socket.connect(HOST, HTTP_PORT)
    if not c then return nil, cerr end
    local werr = socket.write(c, raw_request)
    if werr then
        socket.close(c)
        return nil, werr
    end
    local resp, rerr = socket.read(c)
    socket.close(c)
    return resp, rerr
end

lunet.spawn(function()
    local fake_broker = {
        pool_status = function() return "no workers" end,
        has_workers = function() return false end,
        dispatch = function() return nil, "no workers" end,
    }

    local http_listener, herr = socket.listen("tcp", HOST, HTTP_PORT)
    check("hardening http listener", http_listener ~= nil, herr)
    if not http_listener then os.exit(1) end

    ingress.accept_http(http_listener, fake_broker, "conduit", {
        max_header_lines = 16,
        max_header_bytes = 128,
        max_line_bytes = 64,
        max_body_bytes = 32,
    })

    lunet.sleep(200)

    do
        local req = table.concat({
            "GET /api/tags HTTP/1.1",
            "Host: localhost",
            "X-Long: " .. string.rep("a", 120),
            "",
            "",
        }, "\r\n")
        local raw = http_request(req)
        check("oversized header rejected", status_code(raw) == "431", raw and raw:sub(1, 40))
    end

    do
        local body = string.rep("x", 64)
        local req = table.concat({
            "POST /api/tags HTTP/1.1",
            "Host: localhost",
            "Content-Length: " .. tostring(#body),
            "",
            body,
        }, "\r\n")
        local raw = http_request(req)
        check("oversized body rejected", status_code(raw) == "413", raw and raw:sub(1, 40))
    end

    socket.close(http_listener)

    local worker_listener, werr = socket.listen("tcp", HOST, WORKER_PORT)
    check("hardening worker listener", worker_listener ~= nil, werr)
    if not worker_listener then os.exit(1) end

    lunet.spawn(function()
        broker.accept_workers(worker_listener, { max_workers_per_service = 1 })
    end)
    lunet.sleep(100)

    local w1, e1 = socket.connect(HOST, WORKER_PORT)
    check("worker1 connected", w1 ~= nil, e1)
    if not w1 then os.exit(1) end
    socket.write(w1, "HELLO conduit\n")
    local r1 = BufferedReader.new(w1)
    local line1 = r1:read_line()
    check("worker1 accepted", line1 == "READY", line1)

    local w2, e2 = socket.connect(HOST, WORKER_PORT)
    check("worker2 connected", w2 ~= nil, e2)
    if not w2 then os.exit(1) end
    socket.write(w2, "HELLO conduit\n")
    local r2 = BufferedReader.new(w2)
    local line2 = r2:read_line()
    check("worker2 rejected at cap", line2 == "BUSY", line2)

    local pools = broker.pool_status()
    check("pool remains capped", pools and pools:match("conduit:%s+1 total"), pools)

    socket.close(w1)
    socket.close(w2)
    socket.close(worker_listener)

    print(string.format("========== %d/%d tests passed ==========", pass_count, test_count))
    if pass_count == test_count then
        os.exit(0)
    else
        os.exit(1)
    end
end)
