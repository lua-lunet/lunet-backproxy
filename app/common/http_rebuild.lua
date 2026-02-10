local M = {}

function M.build_response(status, headers, body)
    headers = headers or {}
    body = body or ""
    
    -- Ensure keys are lower case for consistency if needed, but standard HTTP is case-insensitive.
    -- We just blindly insert.
    if not headers["content-length"] and not headers["Content-Length"] then
        headers["Content-Length"] = tostring(#body)
    end
    
    if not headers["content-type"] and not headers["Content-Type"] then
        headers["Content-Type"] = "text/plain"
    end

    local lines = {}
    table.insert(lines, "HTTP/1.1 " .. status)
    for k, v in pairs(headers) do
        table.insert(lines, k .. ": " .. v)
    end
    table.insert(lines, "")
    table.insert(lines, body)

    return table.concat(lines, "\r\n")
end

return M
