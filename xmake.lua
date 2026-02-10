set_project("lunet-backproxy")
set_version("0.1.0")

local lunet_dir = "../lunet"

task("build-lunet")
    on_run(function ()
        os.cd(lunet_dir)
        os.exec("xmake f -m release -y")
        os.exec("xmake build")
        os.exec("xmake build lunet-sqlite3")
    end)
    set_menu {
        usage = "xmake build-lunet",
        description = "Build the lunet runtime and sqlite3 driver"
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
        local lunet_bin = path.join(lunet_dir, "build/lunet")
        os.execv(lunet_bin, {"app/dmz/main.lua"})
    end)
    set_menu {
        usage = "xmake run-dmz",
        description = "Start the DMZ backproxy"
    }
task_end()

task("run-internal")
    on_run(function ()
        local lunet_bin = path.join(lunet_dir, "build/lunet")

        local sqlite_so = nil
        local build_dir = path.join(lunet_dir, "build")
        for _, f in ipairs(os.files(path.join(build_dir, "**", "sqlite3.so"))) do
            sqlite_so = f
            break
        end

        if sqlite_so then
            local sqlite_dir = path.directory(sqlite_so)
            local existing = os.getenv("LUA_CPATH") or ""
            os.setenv("LUA_CPATH", sqlite_dir .. "/?.so;" .. existing .. ";;")
        end

        os.execv(lunet_bin, {"app/internal/main.lua"})
    end)
    set_menu {
        usage = "xmake run-internal",
        description = "Start the Conduit workers (connects out to DMZ)"
    }
task_end()

task("test")
    on_run(function ()
        local lunet_bin = path.join(lunet_dir, "build/lunet")
        local tests = {
            "test/test_unix_loop.lua",
            "test/test_tcp_loop.lua",
            "test/test_combined_loops.lua",
        }
        for _, t in ipairs(tests) do
            print("Running " .. t .. "...")
            os.execv(lunet_bin, {t})
        end

        print("Running integration test...")
        local sqlite_so = nil
        for _, f in ipairs(os.files(path.join(lunet_dir, "build", "**", "sqlite3.so"))) do
            sqlite_so = f
            break
        end
        if sqlite_so then
            local sqlite_dir = path.directory(sqlite_so)
            local existing = os.getenv("LUA_CPATH") or ""
            os.setenv("LUA_CPATH", sqlite_dir .. "/?.so;" .. existing .. ";;")
        end
        os.setenv("DB_PATH", ".tmp/test_integration.sqlite3")
        os.rm(".tmp/test_integration.sqlite3")
        os.execv(lunet_bin, {"test/test_integration.lua"})

        print("All tests passed.")
    end)
    set_menu {
        usage = "xmake test",
        description = "Run all tests (unit + integration)"
    }
task_end()
