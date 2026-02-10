io.stdout:setvbuf("no")
local lunet = require("lunet")
local log = require("app.common.log")
local config = require("app.config")
local worker = require("app.internal.worker")
local http_parse = require("app.common.http_parse")
local http_rebuild = require("app.common.http_rebuild")

math.randomseed(os.time())

local function echo_handler(raw_http)
    local req, err = http_parse.parse_request(raw_http)
    if not req then
        return http_rebuild.build_response(
            "400 Bad Request",
            { ["Content-Type"] = "text/plain" },
            "bad request: " .. tostring(err) .. "\n"
        )
    end

    local body = table.concat({
        "echo service",
        "method=" .. req.method,
        "path=" .. req.path,
        "body_bytes=" .. tostring(#(req.body or "")),
        "",
    }, "\n")

    return http_rebuild.build_response(
        "200 OK",
        { ["Content-Type"] = "text/plain" },
        body
    )
end

local function worker_loop(id)
    while true do
        local ok, err = worker.run_one_worker(
            config.internal.dmz_host,
            config.internal.dmz_port,
            config.internal.service_name,
            echo_handler
        )
        if not ok then
            log.warn("ECHO", "worker %d error: %s", id, tostring(err))
        else
            log.info("ECHO", "worker %d disconnected cleanly", id)
        end

        local ms = math.random(500, 1500)
        log.info("ECHO", "worker %d reconnecting in %d ms", id, ms)
        lunet.sleep(ms)
    end
end

lunet.spawn(function()
    log.info("ECHO", "starting %d workers -> %s:%d",
        config.internal.workers,
        config.internal.dmz_host,
        config.internal.dmz_port)

    for i = 1, config.internal.workers do
        lunet.spawn(function()
            worker_loop(i)
        end)
    end
end)
