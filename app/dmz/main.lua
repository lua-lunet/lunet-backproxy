io.stdout:setvbuf('no')
local lunet = require("lunet")
local socket = require("lunet.socket")
local log = require("app.common.log")
local config = require("app.config")
local broker = require("app.dmz.broker")
local ingress = require("app.dmz.http_ingress")

math.randomseed(os.time())

local sock_path = config.dmz.unix_socket
local http_host = config.dmz.http_host
local http_port = config.dmz.http_port
local bf_host = config.dmz.backflow_host
local bf_port = config.dmz.backflow_port

os.remove(sock_path)

lunet.spawn(function()
    local http_listener, herr = socket.listen("tcp", http_host, http_port)
    if not http_listener then
        log.err("DMZ", "failed to listen on tcp %s:%d: %s", http_host, http_port, tostring(herr))
        os.exit(1)
    end
    log.info("DMZ", "http listener on %s:%d", http_host, http_port)

    local tcp_listener, terr = socket.listen("tcp", bf_host, bf_port)
    if not tcp_listener then
        log.err("DMZ", "failed to listen on tcp %s:%d: %s", bf_host, bf_port, tostring(terr))
        os.exit(1)
    end
    log.info("DMZ", "backflow listener on %s:%d", bf_host, bf_port)

    lunet.spawn(function()
        broker.accept_workers(tcp_listener)
    end)

    ingress.accept_http(http_listener, broker, config.internal.service_name)

    log.info("DMZ", "running. health: http://%s:%d/health", http_host, http_port)
end)
