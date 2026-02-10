set_project("lunet-backproxy")
set_version("0.1.0")

local function find_lunet_bin()
    local env_bin = os.getenv("LUNET_BIN")
    if env_bin and os.isfile(env_bin) then
        return env_bin
    end

    for _, f in ipairs(os.files(path.join(".tmp", "runtime", "lunet-*", "bin", "lunet"))) do
        return f
    end
    for _, f in ipairs(os.files(path.join(".tmp", "runtime", "lunet-*", "bin", "lunet-run"))) do
        return f
    end
    return nil
end

local function ensure_lunet_runtime()
    local lunet_bin = find_lunet_bin()
    if lunet_bin then
        return lunet_bin
    end

    os.execv("bash", {"scripts/setup-lunet.sh"})
    lunet_bin = find_lunet_bin()
    if not lunet_bin then
        raise("Lunet runtime not found after setup-lunet. Expected .tmp/runtime/lunet-*/bin/lunet")
    end
    return lunet_bin
end

task("setup-lunet")
    on_run(function ()
        os.execv("bash", {"scripts/setup-lunet.sh"})
    end)
    set_menu {
        usage = "xmake setup-lunet",
        description = "Download/build pinned lunet runtime from github.com/lua-lunet/lunet (default v0.1.0)"
    }
task_end()

task("build-lunet")
    on_run(function ()
        os.execv("xmake", {"setup-lunet"})
    end)
    set_menu {
        usage = "xmake build-lunet",
        description = "Alias for setup-lunet (kept for compatibility)"
    }
task_end()

task("init-db")
    on_run(function ()
        os.mkdir(".tmp")
        local db_path = os.getenv("DB_PATH") or ".tmp/conduit.sqlite3"
        if os.isfile(db_path) then
            print("Database already exists: " .. db_path)
        else
            print("Creating database: " .. db_path)
            os.execv("sqlite3", {db_path, ".read app/conduit/schema_sqlite.sql"})
            print("Database initialised.")
        end
    end)
    set_menu {
        usage = "xmake init-db",
        description = "Initialise the SQLite database"
    }
task_end()

task("run-dmz")
    on_run(function ()
        ensure_lunet_runtime()
        os.execv("bash", {"scripts/start-dmz.sh"})
    end)
    set_menu {
        usage = "xmake run-dmz",
        description = "Start the DMZ backproxy"
    }
task_end()

task("run-internal")
    on_run(function ()
        ensure_lunet_runtime()
        os.execv("bash", {"scripts/start-internal.sh"})
    end)
    set_menu {
        usage = "xmake run-internal",
        description = "Start the Conduit workers (connects out to DMZ)"
    }
task_end()

task("test")
    on_run(function ()
        ensure_lunet_runtime()
        os.execv("bash", {"scripts/run-tests.sh"})
    end)
    set_menu {
        usage = "xmake test",
        description = "Run all tests (unit + integration)"
    }
task_end()

task("run-echo")
    on_run(function ()
        ensure_lunet_runtime()
        os.execv("bash", {"scripts/start-echo.sh"})
    end)
    set_menu {
        usage = "xmake run-echo",
        description = "Start the echo workers (connects out to DMZ)"
    }
task_end()
