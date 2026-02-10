local M = {}

M.dmz = {
    unix_socket = os.getenv("UNIX_SOCKET") or "/tmp/backproxy.sock",
    http_host = os.getenv("HTTP_HOST") or "127.0.0.1",
    http_port = tonumber(os.getenv("HTTP_PORT") or "8080"),
    backflow_host = os.getenv("BACKFLOW_HOST") or "127.0.0.1",
    backflow_port = tonumber(os.getenv("BACKFLOW_PORT") or "9000"),
}

M.internal = {
    dmz_host = os.getenv("DMZ_HOST") or "127.0.0.1",
    dmz_port = tonumber(os.getenv("BACKFLOW_PORT") or "9000"),
    workers = tonumber(os.getenv("WORKERS") or "4"),
    service_name = os.getenv("SERVICE_NAME") or "conduit",
}

return M
