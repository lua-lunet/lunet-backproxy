local socket = require("lunet.socket")
local log = require("app.common.log")
local frame = require("app.common.frame")
local http_rebuild = require("app.common.http_rebuild")
local BufferedReader = require("app.common.buffered_reader")

local M = {}

local function safe_handle(raw, handler)
    if type(handler) ~= "function" then
        return http_rebuild.build_response(
            "502 Bad Gateway",
            { ["Content-Type"] = "text/plain" },
            "internal handler not configured\n"
        )
    end

    local h = handler
    local ok, res = pcall(h, raw)
    if ok and type(res) == "string" and #res > 0 then
        return res
    end
    log.err("WORKER", "handler failed: %s", tostring(res))
    return http_rebuild.build_response("502 Bad Gateway", { ["Content-Type"]="text/plain" },
        "internal handler error\n")
end

function M.run_one_worker(dmz_host, dmz_port, service_name, handler)
    local conn, err = socket.connect(dmz_host, dmz_port)
    if not conn then
        return nil, "connect failed: " .. tostring(err)
    end

    local reader = BufferedReader.new(conn)

    local werr = socket.write(conn, "HELLO " .. service_name .. "\n")
    if werr then
        socket.close(conn)
        return nil, "hello write failed: " .. tostring(werr)
    end

    local ready, rerr = reader:read_line()
    if not ready then
        socket.close(conn)
        return nil, "ready read failed: " .. tostring(rerr)
    end
    if ready ~= "READY" then
        socket.close(conn)
        return nil, "expected READY, got: " .. tostring(ready)
    end

    log.info("WORKER", "connected to DMZ %s:%d as %s", dmz_host, dmz_port, service_name)

    while true do
        local fr, ferr = frame.read_frame(reader)
        if not fr then
            log.warn("WORKER", "dmz connection lost: %s", tostring(ferr))
            break
        end

        if fr.kind ~= "REQ" then
            log.warn("WORKER", "unexpected frame kind: %s", tostring(fr.kind))
            break
        end

        log.info("WORKER", "handling REQ id=%s bytes=%d", fr.id, #fr.payload)
        local resp_payload = safe_handle(fr.payload, handler)
        local ok2, werr2 = frame.write_frame(conn, "RES", fr.id, resp_payload)
        if not ok2 then
            log.warn("WORKER", "write RES failed: %s", tostring(werr2))
            break
        end
    end

    socket.close(conn)
    return true
end

return M
