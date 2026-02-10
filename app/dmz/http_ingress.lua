local socket = require("lunet.socket")
local lunet = require("lunet")
local log = require("app.common.log")
local http_rebuild = require("app.common.http_rebuild")
local BufferedReader = require("app.common.buffered_reader")

local M = {}

local function read_http_request(reader, limits)
    limits = limits or {}
    local max_header_lines = limits.max_header_lines or 128
    local max_header_bytes = limits.max_header_bytes or (16 * 1024)
    local max_line_bytes = limits.max_line_bytes or 4096
    local max_body_bytes = limits.max_body_bytes or (1024 * 1024)

    local header_lines = {}
    local header_bytes = 0
    while true do
        local line, err = reader:read_line(max_line_bytes)
        if not line then
            if err == "line too long" then
                return nil, nil, err, 431
            end
            return nil, nil, err, 400
        end
        table.insert(header_lines, line)
        if max_header_lines > 0 and #header_lines > max_header_lines then
            return nil, nil, "too many header lines", 431
        end

        header_bytes = header_bytes + #line + 2
        if max_header_bytes > 0 and header_bytes > max_header_bytes then
            return nil, nil, "headers too large", 431
        end

        if line == "" then break end
    end

    local cl = 0
    local path = nil
    local request_line = header_lines[1]
    if not request_line then
        return nil, nil, "missing request line", 400
    end

    local method, parsed_path = request_line:match("^(%S+)%s+(%S+)%s+HTTP/%d%.%d$")
    if not method or not parsed_path then
        return nil, nil, "bad request line", 400
    end
    path = parsed_path

    for i, line in ipairs(header_lines) do
        local k, v = line:match("^(.-):%s*(.*)$")
        if k and k:lower() == "content-length" then
            cl = tonumber(v)
            if not cl or cl < 0 then
                return nil, nil, "invalid content-length", 400
            end
            if max_body_bytes > 0 and cl > max_body_bytes then
                return nil, nil, "payload too large", 413
            end
        end
    end

    local body = ""
    if cl > 0 then
        local b, err = reader:read_exact(cl)
        if not b then return nil, nil, "failed to read body: " .. tostring(err), 400 end
        body = b
    end

    local raw = table.concat(header_lines, "\r\n") .. "\r\n" .. body
    return raw, path
end

local function status_text(code)
    local map = {
        [400] = "400 Bad Request",
        [413] = "413 Payload Too Large",
        [431] = "431 Request Header Fields Too Large",
    }
    return map[code] or "400 Bad Request"
end

function M.accept_http(listener, broker, service_name, limits)
    lunet.spawn(function()
        while true do
            local client, aerr = socket.accept(listener)
            if not client then
                log.warn("INGRESS", "accept error: %s", tostring(aerr))
                break
            end
            local ok, err = pcall(function()
                local reader = BufferedReader.new(client)
                local raw, path, rerr, rcode = read_http_request(reader, limits)
                if not raw then
                    log.warn("INGRESS", "http read failed: %s", tostring(rerr))
                    if rcode then
                        local resp = http_rebuild.build_response(status_text(rcode),
                            { ["Content-Type"] = "text/plain" },
                            tostring(rerr) .. "\n")
                        socket.write(client, resp)
                    end
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
