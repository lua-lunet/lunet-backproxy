set_project("lunet-backproxy")
set_version("0.1.0")
set_policy("compatibility.version", "3.0")

local function run_cmd(cmd, argv, xos)
    local runtime_os = xos or os
    return runtime_os.execv(cmd, argv or {})
end

local function find_lunet_bin(xos)
    local runtime_os = xos or os
    local env_bin = runtime_os.getenv("LUNET_BIN")
    if env_bin and runtime_os.isfile(env_bin) then
        return env_bin
    end

    for _, f in ipairs(runtime_os.files(path.join(".tmp", "runtime", "lunet-*", "bin", "lunet"))) do
        return f
    end
    for _, f in ipairs(runtime_os.files(path.join(".tmp", "runtime", "lunet-*", "bin", "lunet-run"))) do
        return f
    end
    return nil
end

local function ensure_lunet_runtime(xos)
    local runtime_os = xos or os
    local lunet_bin = find_lunet_bin(runtime_os)
    if lunet_bin then
        return lunet_bin
    end

    run_cmd("bash", {"scripts/setup-lunet.sh"}, runtime_os)
    lunet_bin = find_lunet_bin(runtime_os)
    if not lunet_bin then
        runtime_os.raise("Lunet runtime not found after setup-lunet. Expected .tmp/runtime/lunet-*/bin/lunet")
    end
    return lunet_bin
end

target("setup-lunet")
    set_kind("phony")
    on_run(function ()
        run_cmd("bash", {"scripts/setup-lunet.sh"}, os)
    end)
target_end()

target("build-lunet")
    set_kind("phony")
    on_run(function ()
        run_cmd("bash", {"scripts/setup-lunet.sh"}, os)
    end)
target_end()

target("init-db")
    set_kind("phony")
    on_run(function ()
        os.mkdir(".tmp")
        local db_path = os.getenv("DB_PATH") or ".tmp/conduit.sqlite3"
        if os.isfile(db_path) then
            print("Database already exists: " .. db_path)
        else
            print("Creating database: " .. db_path)
            run_cmd("sqlite3", {db_path, ".read app/conduit/schema_sqlite.sql"}, os)
            print("Database initialised.")
        end
    end)
target_end()

target("run-dmz")
    set_kind("phony")
    on_run(function ()
        ensure_lunet_runtime(os)
        run_cmd("bash", {"scripts/start-dmz.sh"}, os)
    end)
target_end()

target("run-internal")
    set_kind("phony")
    on_run(function ()
        ensure_lunet_runtime(os)
        run_cmd("bash", {"scripts/start-internal.sh"}, os)
    end)
target_end()

target("run-echo")
    set_kind("phony")
    on_run(function ()
        ensure_lunet_runtime(os)
        run_cmd("bash", {"scripts/start-echo.sh"}, os)
    end)
target_end()

target("stress-e2e")
    set_kind("phony")
    on_run(function ()
        run_cmd("bash", {"scripts/stress-real-e2e.sh"}, os)
    end)
target_end()

target("stress-compare")
    set_kind("phony")
    on_run(function ()
        run_cmd("bash", {"scripts/stress-compare.sh"}, os)
    end)
target_end()

target("backproxy-tests")
    set_kind("phony")
    add_tests("default")
    on_test(function ()
        ensure_lunet_runtime(os)
        run_cmd("bash", {"scripts/run-tests.sh"}, os)
        return true
    end)
target_end()
