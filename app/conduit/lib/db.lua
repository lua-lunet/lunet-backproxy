-- Database abstraction for RealWorld API
-- Dynamically loads the appropriate driver based on config
local config = require("app.conduit.db_config")

local driver_modules = {
    sqlite = "lunet.sqlite3",
    sqlite3 = "lunet.sqlite3",
    mysql = "lunet.mysql",
    postgres = "lunet.postgres",
}

local driver_name = driver_modules[config.driver] or "lunet.sqlite3"
local native = require(driver_name)

local db = {}

-- Connection pool
local pool = {}
local pool_size = tonumber(os.getenv("DB_POOL_SIZE")) or 100

-- Expose native functions
db.open = native.open
db.close = native.close
db.query_raw = native.query
db.exec_raw = native.exec
db.query_params = native.query_params
db.exec_params = native.exec_params

function db.set_config(cfg)
    if not cfg then return end
    for k, v in pairs(cfg) do
        config[k] = v
    end
end

-- Initialize connection pool
function db.init_pool()
    for i = 1, pool_size do
        local conn, err = native.open(config)
        if conn then
            table.insert(pool, conn)
        else
            -- If we can't create connections, that's ok - we'll create on demand
            break
        end
    end
end

-- Get connection from pool (or create new one)
local function get_conn()
    if #pool > 0 then
        return table.remove(pool, 1)
    end
    -- Pool empty, create new connection
    return native.open(config)
end

-- Return connection to pool
local function release_conn(conn)
    if #pool < pool_size then
        table.insert(pool, conn)
    else
        -- Pool full, close connection (let GC handle for MySQL)
        if config.driver ~= "mysql" then
            native.close(conn)
        end
    end
end

-- Connection management (legacy - creates new connection)
function db.connect()
    return native.open(config)
end

-- Escape function
function db.escape(value)
    if value == nil then
        return "NULL"
    elseif type(value) == "number" then
        return tostring(value)
    elseif type(value) == "boolean" then
        return value and "1" or "0"
    else
        return "'" .. native.escape(tostring(value)) .. "'"
    end
end

-- Interpolate: replace ? with escaped values
function db.interpolate(sql, ...)
    local args = {...}
    local idx = 0
    return sql:gsub("%?", function()
        idx = idx + 1
        return db.escape(args[idx])
    end)
end

-- Higher level query (handles connection and parameters)
function db.query(sql, ...)
    local conn, err = get_conn()
    if not conn then
        return nil, err
    end

    local result, query_err
    if select("#", ...) > 0 then
        -- Postgres and MySQL query_params don't support parameters yet, so interpolate manually
        if config.driver == "postgres" or config.driver == "mysql" then
            local interpolated = db.interpolate(sql, ...)
            result, query_err = db.query_raw(conn, interpolated)
        else
            result, query_err = db.query_params(conn, sql, ...)
        end
    else
        result, query_err = db.query_raw(conn, sql)
    end
    
    release_conn(conn)
    
    if not result then
        return nil, query_err or "query failed"
    end

    return result
end

function db.exec(sql, ...)
    local conn, err = get_conn()
    if not conn then
        return nil, err
    end

    local result, exec_err
    if select("#", ...) > 0 then
        -- Postgres and MySQL exec_params don't support parameters yet, so interpolate manually
        if config.driver == "postgres" or config.driver == "mysql" then
            local interpolated = db.interpolate(sql, ...)
            result, exec_err = db.exec_raw(conn, interpolated)
        else
            result, exec_err = db.exec_params(conn, sql, ...)
        end
    else
        result, exec_err = db.exec_raw(conn, sql)
    end
    
    release_conn(conn)
    
    if not result then
        return nil, exec_err or "exec failed"
    end

    return result
end

function db.query_one(sql, ...)
    local result, err = db.query(sql, ...)
    if not result then return nil, err end
    if #result == 0 then return nil end
    return result[1]
end

-- Table helpers
function db.insert(table_name, data)
    local columns = {}
    local values = {}
    for col, val in pairs(data) do
        columns[#columns + 1] = col
        values[#values + 1] = db.escape(val)
    end
    
    -- PostgreSQL needs RETURNING to get the inserted id
    if config.driver == "postgres" then
        local sql = string.format(
            "INSERT INTO %s (%s) VALUES (%s) RETURNING id",
            table_name,
            table.concat(columns, ", "),
            table.concat(values, ", ")
        )
        local rows, err = db.query(sql)
        if not rows or #rows == 0 then
            return nil, err
        end
        return { last_insert_id = rows[1].id, affected_rows = 1 }
    end
    
    local sql = string.format(
        "INSERT INTO %s (%s) VALUES (%s)",
        table_name,
        table.concat(columns, ", "),
        table.concat(values, ", ")
    )
    return db.exec(sql)
end

function db.update(table_name, data, where, ...)
    local sets = {}
    for col, val in pairs(data) do
        sets[#sets + 1] = col .. " = " .. db.escape(val)
    end
    local sql = string.format(
        "UPDATE %s SET %s WHERE %s",
        table_name,
        table.concat(sets, ", "),
        db.interpolate(where, ...)
    )
    return db.exec(sql)
end

function db.delete(table_name, where, ...)
    local sql = string.format(
        "DELETE FROM %s WHERE %s",
        table_name,
        db.interpolate(where, ...)
    )
    return db.exec(sql)
end

function db.init()
    if config.driver == "sqlite" or config.driver == "sqlite3" then
        -- Ensure .tmp directory exists
        os.execute("mkdir -p .tmp")
        
        local conn, err = db.connect()
        if not conn then return nil, err end
        
        -- Read schema from app directory
        local schema_paths = {
            "app/conduit/schema_sqlite.sql",
            "app/schema_sqlite.sql",
            "app/schema.sql"
        }
        
        local f
        for _, path in ipairs(schema_paths) do
            f = io.open(path, "rb")
            if f then break end
        end
        
        if f then
            local schema = f:read("*a")
            f:close()
            db.exec_raw(conn, schema)
        end
        db.close(conn)
    end
    
    -- Initialize connection pool
    db.init_pool()
    
    return true
end

return db
