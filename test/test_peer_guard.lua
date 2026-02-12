io.stdout:setvbuf("no")
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

do
    local ok, reason = guard._evaluate_for_test({
        transport = "tcp",
    }, {
        peer_verify_mode = "off",
    })
    check("mode off allows", ok == true, reason)
end

do
    local ok, reason = guard._evaluate_for_test({
        transport = "tcp",
    }, {
        peer_verify_mode = "enforce",
        peer_expect_transport = "unix",
    })
    check("transport mismatch denied", ok == false, reason)
end

do
    local ok, reason = guard._evaluate_for_test({
        transport = "unix",
        uid = 2000,
    }, {
        peer_verify_mode = "enforce",
        peer_allowed_uids = { 1000, 1001 },
    })
    check("uid allowlist denied", ok == false, reason)
end

do
    local ok, reason = guard._evaluate_for_test({
        transport = "unix",
        uid = 1000,
        gid = 1000,
    }, {
        peer_verify_mode = "enforce",
        peer_allowed_uids = { 1000 },
        peer_allowed_gids = { 1000 },
    })
    check("uid gid allowlist pass", ok == true, reason)
end

do
    local ok, reason = guard._evaluate_for_test({
        transport = "unix",
        pid = 4242,
    }, {
        peer_verify_mode = "enforce",
        peer_exe_prefixes = { "/usr/sbin/nginx" },
        peer_cmdline_prefixes = { "nginx: worker process" },
    }, {
        is_linux = true,
        proc_reader = function(_)
            return {
                exe = "/usr/sbin/nginx",
                cmdline = "nginx: worker process",
            }
        end,
    })
    check("linux proc prefix pass", ok == true, reason)
end

do
    local ok, reason = guard._evaluate_for_test({
        transport = "unix",
        pid = 4242,
    }, {
        peer_verify_mode = "enforce",
        peer_exe_prefixes = { "/usr/sbin/nginx" },
    }, {
        is_linux = true,
        proc_reader = function(_)
            return { exe = "/usr/bin/curl", cmdline = "curl /" }
        end,
    })
    check("linux proc prefix deny", ok == false, reason)
end

do
    local ok, reason = guard._evaluate_for_test({
        transport = "unix",
        uid = 33,
        gid = 33,
        pid = 111,
    }, {
        peer_verify_mode = "enforce",
        peer_selectors = {
            "unix:transport:unix",
            "unix:uid:33",
            "unix:gid:33",
            "unix:path_prefix:/usr/sbin/nginx",
            "unix:cmdline_prefix:nginx: worker process",
            "unix:sha256:deadbeef",
        },
    }, {
        is_linux = true,
        proc_reader = function(_)
            return {
                exe = "/usr/sbin/nginx",
                cmdline = "nginx: worker process /usr/sbin/nginx -g daemon off;",
            }
        end,
        sha256_file = function(_)
            return "deadbeef"
        end,
    })
    check("spire-like selectors pass", ok == true, reason)
end

do
    local ok, reason = guard._evaluate_for_test({
        transport = "unix",
        uid = 1000,
        gid = 1000,
    }, {
        peer_verify_mode = "enforce",
        peer_selectors = {
            "unix:uid:1001",
        },
    }, {
        is_linux = true,
    })
    check("spire-like selector mismatch denied", ok == false, reason)
end

do
    local ok, reason = guard._evaluate_for_test({
        transport = "unix",
    }, {
        peer_verify_mode = "enforce",
        peer_selectors = {
            "unix:nonRoot:true",
        },
    })
    check("unsupported selector key denied", ok == false, reason)
end

print(string.format("========== %d/%d tests passed ==========", pass_count, test_count))
if pass_count == test_count then
    os.exit(0)
else
    os.exit(1)
end
