io.stdout:setvbuf('no')
local lunet = require("lunet")
local socket = require("lunet.socket")
local log = require("app.common.log")
local config = require("app.config")
local broker = require("app.dmz.broker")
local ingress = require("app.dmz.http_ingress")

math.randomseed(os.time())

local sock_path = config.dmz.unix_socket
local http_transport = config.dmz.http_transport
local http_host = config.dmz.http_host
local http_port = config.dmz.http_port
local bf_host = config.dmz.backflow_host
local bf_port = config.dmz.backflow_port

lunet.spawn(function()
    local http_listener, herr
    if http_transport == "unix" then
        os.remove(sock_path)
        http_listener, herr = socket.listen("unix", sock_path, 0)
    else
        http_listener, herr = socket.listen("tcp", http_host, http_port)
    end
    if not http_listener then
        if http_transport == "unix" then
            log.err("DMZ", "failed to listen on unix %s: %s", sock_path, tostring(herr))
        else
            log.err("DMZ", "failed to listen on tcp %s:%d: %s", http_host, http_port, tostring(herr))
        end
        os.exit(1)
    end
    if http_transport == "unix" then
        log.info("DMZ", "http listener on unix socket %s", sock_path)
    else
        log.info("DMZ", "http listener on %s:%d", http_host, http_port)
    end

    local tcp_listener, terr = socket.listen("tcp", bf_host, bf_port)
    if not tcp_listener then
        log.err("DMZ", "failed to listen on tcp %s:%d: %s", bf_host, bf_port, tostring(terr))
        os.exit(1)
    end
    log.info("DMZ", "backflow listener on %s:%d", bf_host, bf_port)

    lunet.spawn(function()
        broker.accept_workers(tcp_listener, {
            max_workers_per_service = config.dmz.max_workers_per_service,
        })
    end)

    ingress.accept_http(http_listener, broker, config.internal.service_name, {
        max_header_lines = config.dmz.max_header_lines,
        max_header_bytes = config.dmz.max_header_bytes,
        max_line_bytes = config.dmz.max_line_bytes,
        max_body_bytes = config.dmz.max_body_bytes,
        peer_verify_mode = config.dmz.peer_verify_mode,
        peer_expect_transport = config.dmz.peer_expect_transport,
        peer_allowed_uids = config.dmz.peer_allowed_uids,
        peer_allowed_gids = config.dmz.peer_allowed_gids,
        peer_exe_prefixes = config.dmz.peer_exe_prefixes,
        peer_cmdline_prefixes = config.dmz.peer_cmdline_prefixes,
        peer_selectors = config.dmz.peer_selectors,
    })

    log.info("DMZ", "running. health: http://%s:%d/health", http_host, http_port)
end)
