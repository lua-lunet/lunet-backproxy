io.stdout:setvbuf('no')
local lunet = require("lunet")
local socket = require("lunet.socket")

local SOCK_PATH = "/tmp/backproxy-integration-test.sock"
local TCP_HOST = "127.0.0.1"
local TCP_PORT = 19002
local HTTP_PORT = 19003
local TEST_DB = ".tmp/test_integration.sqlite3"

os.remove(SOCK_PATH)
os.remove(TEST_DB)

os.execute("mkdir -p .tmp")
local rc = os.execute("sqlite3 " .. TEST_DB .. ' ".read app/conduit/schema_sqlite.sql"')
if rc ~= 0 and rc ~= true then
    print("FAIL: could not create test database")
    os.exit(1)
end
print("OK: test database created")

-- DB_PATH must be set via env before launching this script
-- (db_config.lua reads os.getenv at require time)

local frame = require("app.common.frame")
local BufferedReader = require("app.common.buffered_reader")
local broker = require("app.dmz.broker")
local ingress = require("app.dmz.http_ingress")
local request_handler = require("app.conduit.request_handler")
local conduit_config = require("app.conduit.conduit_config")
local http_rebuild = require("app.common.http_rebuild")

local test_count = 0
local pass_count = 0

local function check(name, condition, detail)
    test_count = test_count + 1
    if condition then
        pass_count = pass_count + 1
        print("PASS: " .. name)
    else
        print("FAIL: " .. name .. " -- " .. (detail or ""))
    end
end

local function send_http(path, method, headers_extra, body)
    method = method or "GET"
    body = body or ""
    headers_extra = headers_extra or {}

    local lines = {}
    lines[#lines + 1] = method .. " " .. path .. " HTTP/1.1"
    lines[#lines + 1] = "Host: localhost"
    if #body > 0 then
        lines[#lines + 1] = "Content-Length: " .. #body
    end
    for k, v in pairs(headers_extra) do
        lines[#lines + 1] = k .. ": " .. v
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = body
    return table.concat(lines, "\r\n")
end

local function read_full_response(client)
    local reader = BufferedReader.new(client)
    local header_lines = {}
    while true do
        local line, err = reader:read_line()
        if not line then return nil, err end
        header_lines[#header_lines + 1] = line
        if line == "" then break end
    end
    local cl = 0
    for _, line in ipairs(header_lines) do
        local k, v = line:match("^(.-):%s*(.*)$")
        if k and k:lower() == "content-length" then cl = tonumber(v) or 0 end
    end
    local body = ""
    if cl > 0 then
        body = reader:read_exact(cl) or ""
    end
    local raw = table.concat(header_lines, "\r\n") .. "\r\n" .. body
    return raw, body
end

lunet.spawn(function()
    -- 1. Init conduit (DB + auth)
    local ok, err = request_handler.init(conduit_config)
    check("conduit init", ok, tostring(err))
    if not ok then os.exit(1) end

    -- 2. Start backproxy listeners
    local unix_listener, uerr = socket.listen("tcp", TCP_HOST, HTTP_PORT)
    check("http listener", unix_listener ~= nil, tostring(uerr))
    if not unix_listener then os.exit(1) end

    local tcp_listener, terr = socket.listen("tcp", TCP_HOST, TCP_PORT)
    check("tcp listener", tcp_listener ~= nil, tostring(terr))
    if not tcp_listener then os.exit(1) end

    broker.accept_workers(tcp_listener)
    ingress.accept_http(unix_listener, broker, "conduit")

    -- 3. Connect a worker (simulating the Conduit worker connecting OUT)
    lunet.spawn(function()
        local conn, cerr = socket.connect(TCP_HOST, TCP_PORT)
        if not conn then
            print("FAIL: worker connect: " .. tostring(cerr))
            os.exit(1)
        end

        socket.write(conn, "HELLO conduit\n")
        local reader = BufferedReader.new(conn)
        local ready = reader:read_line()
        check("worker HELLO/READY", ready == "READY", tostring(ready))

        while true do
            local fr, ferr = frame.read_frame(reader)
            if not fr then break end
            if fr.kind == "REQ" then
                local resp = request_handler.handle(fr.payload)
                frame.write_frame(conn, "RES", fr.id, resp)
            end
        end
        socket.close(conn)
    end)

    -- Give worker time to register
    lunet.sleep(300)

    -- =====================
    -- TEST SUITE
    -- =====================

    -- TEST: 503 before workers (we already have one, so test health instead)
    local function http_request(path, method, headers, body)
        local c = socket.connect(TCP_HOST, HTTP_PORT)
        if not c then return nil, "connect failed" end
        socket.write(c, send_http(path, method, headers, body))
        local raw, rbody = read_full_response(c)
        socket.close(c)
        return raw, rbody
    end

    -- TEST: Health endpoint shows worker pool
    do
        local raw, body = http_request("/health")
        check("health returns 200", raw and raw:match("200"), raw and raw:sub(1, 40))
        check("health shows workers", body and body:match("conduit: 1 total"), body)
    end

    -- TEST: GET /api/tags on empty DB
    do
        local raw, body = http_request("/api/tags")
        check("tags returns 200", raw and raw:match("200"), raw and raw:sub(1, 40))
        check("tags returns empty array", body and body:match('"tags":%[%]'), body)
    end

    -- TEST: Register a user
    local token = nil
    do
        local req_body = '{"user":{"username":"testuser","email":"test@example.com","password":"password123"}}'
        local raw, body = http_request("/api/users", "POST",
            {["Content-Type"] = "application/json"}, req_body)
        check("register returns 201", raw and raw:match("201"), raw and raw:sub(1, 40))
        check("register returns username", body and body:match('"username":"testuser"'), body)
        token = body and body:match('"token":"([^"]+)"')
        check("register returns JWT token", token ~= nil, body)
    end

    -- TEST: Login
    do
        local req_body = '{"user":{"email":"test@example.com","password":"password123"}}'
        local raw, body = http_request("/api/users/login", "POST",
            {["Content-Type"] = "application/json"}, req_body)
        check("login returns 200", raw and raw:match("200"), raw and raw:sub(1, 40))
        check("login returns username", body and body:match('"username":"testuser"'), body)
        local login_token = body and body:match('"token":"([^"]+)"')
        check("login returns JWT token", login_token ~= nil, body)
        token = login_token or token
    end

    -- TEST: Get current user (authenticated)
    do
        local raw, body = http_request("/api/user", "GET",
            {["Authorization"] = "Token " .. (token or "")})
        check("get user returns 200", raw and raw:match("200"), raw and raw:sub(1, 40))
        check("get user returns email", body and body:match('"email":"test@example.com"'), body)
    end

    -- TEST: Create article (authenticated, DB write)
    local slug = nil
    do
        local req_body = '{"article":{"title":"Integration Test Article","description":"Testing the full backflow chain","body":"Request went: client -> unix socket -> backproxy -> framing -> worker -> conduit handler -> DB. Response came back the same way.","tagList":["backflow","integration","test"]}}'
        local raw, body = http_request("/api/articles", "POST",
            {["Content-Type"] = "application/json", ["Authorization"] = "Token " .. (token or "")},
            req_body)
        check("create article returns 201", raw and raw:match("201"), raw and raw:sub(1, 40))
        check("article has title", body and body:match('"title":"Integration Test Article"'), body and body:sub(1, 120))
        check("article has author", body and body:match('"username":"testuser"'), body and body:sub(1, 120))
        slug = body and body:match('"slug":"([^"]+)"')
        check("article has slug", slug ~= nil, body and body:sub(1, 120))
    end

    -- TEST: Tags now populated from article creation
    do
        local raw, body = http_request("/api/tags")
        check("tags now has entries", body and body:match('"tags":%['), body)
        check("tags contains backflow", body and body:match('"backflow"'), body)
        check("tags contains integration", body and body:match('"integration"'), body)
        check("tags contains test", body and body:match('"test"'), body)
    end

    -- TEST: Get article by slug (DB read)
    if slug then
        local raw, body = http_request("/api/articles/" .. slug)
        check("get article returns 200", raw and raw:match("200"), raw and raw:sub(1, 40))
        check("get article has body text", body and body:match("backflow chain"), body and body:sub(1, 120))
    end

    -- TEST: 404 for unknown route
    do
        local raw, body = http_request("/api/nonexistent")
        check("unknown route returns 404", raw and raw:match("404"), raw and raw:sub(1, 40))
    end

    -- =====================
    -- SUMMARY
    -- =====================
    print("")
    print(string.format("========== %d/%d tests passed ==========", pass_count, test_count))
    if pass_count == test_count then
        print("ALL TESTS PASSED")
    else
        print("SOME TESTS FAILED")
    end

    -- Cleanup
    socket.close(unix_listener)
    socket.close(tcp_listener)
    os.remove(SOCK_PATH)
    os.remove(TEST_DB)

    if pass_count == test_count then
        os.exit(0)
    else
        os.exit(1)
    end
end)
