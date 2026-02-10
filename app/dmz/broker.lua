local socket = require("lunet.socket")
local lunet = require("lunet")
local log = require("app.common.log")
local frame = require("app.common.frame")
local BufferedReader = require("app.common.buffered_reader")

local M = {}

local pools = {}
local idle_wait_ms = tonumber(os.getenv("BROKER_IDLE_WAIT_MS") or "10")
local idle_wait_attempts = tonumber(os.getenv("BROKER_IDLE_WAIT_ATTEMPTS") or "100")

local function add_worker(service, client, reader)
    pools[service] = pools[service] or {}
    table.insert(pools[service], {
        client = client,
        reader = reader,
        busy = false,
    })
    log.info("BROKER", "registered worker service=%s pool_size=%d", service, #pools[service])
end

local function remove_worker(service, w)
    local p = pools[service]
    if not p then return end
    for i, worker in ipairs(p) do
        if worker == w then
            table.remove(p, i)
            break
        end
    end
    socket.close(w.client)
    log.info("BROKER", "removed worker service=%s remaining=%d", service, p and #p or 0)
end

local function pick_idle(service)
    local p = pools[service]
    if not p or #p == 0 then return nil end
    for _, w in ipairs(p) do
        if not w.busy then return w end
    end
    return nil
end

function M.has_workers(service)
    local p = pools[service]
    return p ~= nil and #p > 0
end

local function wait_for_idle(service)
    for _ = 1, idle_wait_attempts do
        local w = pick_idle(service)
        if w then
            return w
        end
        lunet.sleep(idle_wait_ms)
    end
    return nil
end

function M.accept_workers(tcp_listener)
    while true do
        local client, aerr = socket.accept(tcp_listener)
        if not client then
            log.warn("BROKER", "tcp accept error: %s", tostring(aerr))
            return false, aerr
        end

        local reader = BufferedReader.new(client)
        local line, rerr = reader:read_line()
        if not line then
            log.warn("BROKER", "worker missing HELLO: %s", tostring(rerr))
            socket.close(client)
            goto continue
        end

        local svc = line:match("^HELLO%s+(%S+)$")
        if not svc then
            log.warn("BROKER", "bad HELLO: %s", line)
            socket.close(client)
            goto continue
        end

        local werr = socket.write(client, "READY\n")
        if werr then
            log.warn("BROKER", "failed to send READY: %s", tostring(werr))
            socket.close(client)
            goto continue
        end

        add_worker(svc, client, reader)

        ::continue::
    end
end

function M.dispatch(service, req_id, raw_http_request)
    for attempt = 1, 3 do
        local w = wait_for_idle(service)
        if not w then
            return nil, "no idle worker for service=" .. service
        end

        w.busy = true
        local success = false
        local payload = nil

        local ok, werr = frame.write_frame(w.client, "REQ", req_id, raw_http_request)
        if not ok then
            log.warn("BROKER", "worker write failed, removing: %s", tostring(werr))
            w.busy = false
            remove_worker(service, w)
        else
            local resp, rerr = frame.read_frame(w.reader)
            w.busy = false

            if not resp then
                log.warn("BROKER", "worker read failed, removing: %s", tostring(rerr))
                remove_worker(service, w)
            elseif resp.kind ~= "RES" or resp.id ~= req_id then
                log.warn("BROKER", "bad response frame (kind/id mismatch), removing")
                remove_worker(service, w)
                return nil, "bad response frame"
            else
                success = true
                payload = resp.payload
            end
        end

        if success then
            return payload, nil
        end
    end
    return nil, "all workers failed"
end

function M.pool_status()
    local out = {}
    for svc, p in pairs(pools) do
        local busy = 0
        for _, w in ipairs(p) do if w.busy then busy = busy + 1 end end
        table.insert(out, string.format("%s: %d total, %d busy", svc, #p, busy))
    end
    table.sort(out)
    if #out == 0 then return "no workers" end
    return table.concat(out, " | ")
end

return M
