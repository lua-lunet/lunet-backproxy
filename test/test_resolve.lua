io.stdout:setvbuf("no")
local resolve = require("app.common.resolve")

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

do
    local ip, err = resolve.resolve("10.1.2.3")
    check("ipv4 passthrough", ip == "10.1.2.3" and err == nil, tostring(ip) .. " " .. tostring(err))
end

do
    local ip, err = resolve.resolve("localhost")
    check("localhost special case", ip == "127.0.0.1" and err == nil, tostring(ip) .. " " .. tostring(err))
end

do
    local ip, err = resolve.resolve(nil)
    check("nil host rejected", ip == nil and err ~= nil, tostring(err))
end

do
    local ip, err = resolve.resolve("")
    check("empty host rejected", ip == nil and err ~= nil, tostring(err))
end

do
    local ip, err = resolve.resolve("bad;host")
    check("shell metachar host rejected", ip == nil and err ~= nil, tostring(err))
end

do
    local ip, err = resolve.resolve("../x")
    check("path-like host rejected", ip == nil and err ~= nil, tostring(err))
end

do
    local ip, err = resolve.resolve("a b")
    check("space host rejected", ip == nil and err ~= nil, tostring(err))
end

do
    local ip, err = resolve.resolve("nonexistent.invalid")
    check("unresolvable host rejected", ip == nil and err ~= nil, tostring(ip))
end

do
    local ip1, err1 = resolve.resolve("localhost")
    local ip2, err2 = resolve.resolve("localhost")
    check("repeat resolution stable", ip1 == ip2 and err1 == nil and err2 == nil,
        tostring(ip1) .. " " .. tostring(ip2))
end

print(string.format("========== %d/%d tests passed ==========", pass_count, test_count))
if pass_count == test_count then
    os.exit(0)
else
    os.exit(1)
end
