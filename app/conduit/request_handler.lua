local http = require("app.conduit.lib.http")
local json = require("app.conduit.lib.json")
local db = require("app.conduit.lib.db")
local auth = require("app.conduit.lib.auth")

local handlers = {
    users = require("app.conduit.handlers.users"),
    profiles = require("app.conduit.handlers.profiles"),
    articles = require("app.conduit.handlers.articles"),
    comments = require("app.conduit.handlers.comments"),
    tags = require("app.conduit.handlers.tags"),
}

local routes = {
    {method = "POST", pattern = "/api/users/login", handler = handlers.users.login},
    {method = "POST", pattern = "/api/users", handler = handlers.users.register},
    {method = "GET", pattern = "/api/user", handler = handlers.users.current},
    {method = "PUT", pattern = "/api/user", handler = handlers.users.update},

    {method = "GET", pattern = "/api/profiles/:username", handler = handlers.profiles.get},
    {method = "POST", pattern = "/api/profiles/:username/follow", handler = handlers.profiles.follow},
    {method = "DELETE", pattern = "/api/profiles/:username/follow", handler = handlers.profiles.unfollow},

    {method = "GET", pattern = "/api/articles/feed", handler = handlers.articles.feed},
    {method = "GET", pattern = "/api/articles", handler = handlers.articles.list},
    {method = "GET", pattern = "/api/articles/:slug", handler = handlers.articles.get},
    {method = "POST", pattern = "/api/articles", handler = handlers.articles.create},
    {method = "PUT", pattern = "/api/articles/:slug", handler = handlers.articles.update},
    {method = "DELETE", pattern = "/api/articles/:slug", handler = handlers.articles.delete},
    {method = "POST", pattern = "/api/articles/:slug/favorite", handler = handlers.articles.favorite},
    {method = "DELETE", pattern = "/api/articles/:slug/favorite", handler = handlers.articles.unfavorite},

    {method = "GET", pattern = "/api/articles/:slug/comments", handler = handlers.comments.list},
    {method = "POST", pattern = "/api/articles/:slug/comments", handler = handlers.comments.create},
    {method = "DELETE", pattern = "/api/articles/:slug/comments/:id", handler = handlers.comments.delete},

    {method = "GET", pattern = "/api/tags", handler = handlers.tags.list},
}

local function match_route(method, path)
    for _, route in ipairs(routes) do
        if route.method == method then
            local pattern_parts = {}
            for part in route.pattern:gmatch("[^/]+") do
                pattern_parts[#pattern_parts + 1] = part
            end

            local path_parts = {}
            for part in path:gmatch("[^/]+") do
                path_parts[#path_parts + 1] = part
            end

            if #pattern_parts == #path_parts then
                local params = {}
                local match = true
                for i, pp in ipairs(pattern_parts) do
                    if pp:sub(1, 1) == ":" then
                        params[pp:sub(2)] = path_parts[i]
                    elseif pp ~= path_parts[i] then
                        match = false
                        break
                    end
                end
                if match then
                    return route.handler, params
                end
            end
        end
    end
    return nil, nil
end

local function handle_request(request)
    if request.method == "OPTIONS" then
        return http.options_response()
    end

    auth.middleware(request)

    local handler, params = match_route(request.method, request.path)
    if not handler then
        return http.error_response(404, {body = {"Not found"}})
    end

    request.params = params or {}

    if request.body and request.headers and
       request.headers["content-type"] and
       request.headers["content-type"]:find("application/json") then
        local ok, parsed = pcall(json.decode, request.body)
        if ok then
            request.json = parsed
        end
    end

    local ok, response = pcall(handler, request)
    if not ok then
        print("Handler error: " .. tostring(response))
        return http.error_response(500, {body = {"Internal server error"}})
    end

    if type(response) ~= "string" then
        print("Handler returned non-string response: " .. type(response))
        return http.error_response(500, {body = {"Internal server error"}})
    end

    local cors = http.cors_headers()
    for k, v in pairs(cors) do
        response = response:gsub("\r\n\r\n", "\r\n" .. k .. ": " .. v .. "\r\n\r\n", 1)
    end

    return response
end

local M = {}

function M.init(conduit_config)
    db.set_config(conduit_config.db)
    auth.set_config(conduit_config)
    local ok, err = db.init()
    if not ok then
        return nil, "database init failed: " .. tostring(err)
    end
    return true
end

function M.handle(raw_http)
    local request, parse_err = http.parse_request(raw_http)
    if not request then
        return http.error_response(400, {body = {parse_err or "Bad request"}})
    end

    local ok, response = pcall(handle_request, request)
    if not ok then
        print("Request handler error: " .. tostring(response))
        return http.error_response(500, {body = {"Internal server error"}})
    end

    return response
end

return M
