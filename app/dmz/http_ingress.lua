local socket = require("lunet.socket")
local lunet = require("lunet")
local log = require("app.common.log")
local http_rebuild = require("app.common.http_rebuild")
local BufferedReader = require("app.common.buffered_reader")

local M = {}

local function read_http_request(reader)
    local header_lines = {}
    while true do
        local line, err = reader:read_line()
        if not line then return nil, nil, err end
        table.insert(header_lines, line)
        if line == "" then break end
    end

    local cl = 0
    local path = nil
    for i, line in ipairs(header_lines) do
        if i == 1 then
            local _, p = line:match("^(%S+)%s+(%S+)")
            path = p
        end
        local k, v = line:match("^(.-):%s*(.*)$")
        if k and k:lower() == "content-length" then
            cl = tonumber(v) or 0
        end
    end

    local body = ""
    if cl > 0 then
        local b, err = reader:read_exact(cl)
        if not b then return nil, nil, "failed to read body: " .. tostring(err) end
        body = b
    end

    local raw = table.concat(header_lines, "\r\n") .. "\r\n" .. body
    return raw, path
end

function M.accept_http(listener, broker, service_name)
    lunet.spawn(function()
        while true do
            local client, aerr = socket.accept(listener)
            if not client then
                log.warn("INGRESS", "accept error: %s", tostring(aerr))
                break
            end
            local ok, err = pcall(function()
                local reader = BufferedReader.new(client)
                local raw, path, rerr = read_http_request(reader)
                if not raw then
                    log.warn("INGRESS", "http read failed: %s", tostring(rerr))
                    socket.close(client)
                    return
                end

                if path == "/health" then
                    local body = "ok\npools: " .. broker.pool_status() .. "\n"
                    local resp = http_rebuild.build_response("200 OK", { ["Content-Type"] = "text/plain" }, body)
                    socket.write(client, resp)
                    socket.close(client)
                    return
                end

                if not broker.has_workers(service_name) then
                    local resp = http_rebuild.build_response("503 Service Unavailable",
                        { ["Content-Type"] = "text/plain" },
                        "no backend workers connected\n")
                    socket.write(client, resp)
                    socket.close(client)
                    return
                end

                local req_id = tostring(math.random(100000000000, 999999999999))
                local resp_payload, derr = broker.dispatch(service_name, req_id, raw)

                if not resp_payload then
                    log.warn("INGRESS", "dispatch failed: %s", tostring(derr))
                    local resp = http_rebuild.build_response("503 Service Unavailable",
                        { ["Content-Type"] = "text/plain" },
                        "dispatch failed: " .. tostring(derr) .. "\n")
                    socket.write(client, resp)
                    socket.close(client)
                    return
                end

                socket.write(client, resp_payload)
                socket.close(client)
            end)
            if not ok then
                log.err("INGRESS", "handler crashed: %s", tostring(err))
                pcall(socket.close, client)
            end
        end
    end)
end

return M
