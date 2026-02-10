io.stdout:setvbuf('no')
local lunet = require("lunet")
local log = require("app.common.log")
local config = require("app.config")
local conduit_config = require("app.conduit.conduit_config")
local request_handler = require("app.conduit.request_handler")
local worker = require("app.internal.worker")

math.randomseed(os.time())

local function worker_loop(id)
    while true do
        local ok, err = worker.run_one_worker(
            config.internal.dmz_host,
            config.internal.dmz_port,
            config.internal.service_name
        )
        if not ok then
            log.warn("MAIN", "worker %d error: %s", id, tostring(err))
        else
            log.info("MAIN", "worker %d disconnected cleanly", id)
        end

        local ms = math.random(1000, 3000)
        log.info("MAIN", "worker %d reconnecting in %d ms", id, ms)
        lunet.sleep(ms)
    end
end

lunet.spawn(function()
    log.info("MAIN", "initialising conduit (DB, auth)...")
    local ok, err = request_handler.init(conduit_config)
    if not ok then
        log.err("MAIN", "conduit init failed: %s", tostring(err))
        os.exit(1)
    end
    log.info("MAIN", "conduit ready")

    log.info("MAIN", "starting %d workers -> %s:%d",
        config.internal.workers,
        config.internal.dmz_host,
        config.internal.dmz_port)

    for i = 1, config.internal.workers do
        lunet.spawn(function()
            worker_loop(i)
        end)
    end
end)
