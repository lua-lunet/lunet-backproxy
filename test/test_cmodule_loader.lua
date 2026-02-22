io.stdout:setvbuf("no")

local test_count = 0
local pass_count = 0

local function check(name, condition, detail)
    test_count = test_count + 1
    if condition then
        pass_count = pass_count + 1
        print("PASS: " .. name)
    else
        print("FAIL: " .. name .. " -- " .. tostring(detail or ""))
    end
end

local function try_require(modname)
    local ok, mod_or_err = pcall(require, modname)
    return ok, mod_or_err
end

local function cpath_entries()
    local entries = {}
    for entry in (package.cpath or ""):gmatch("[^;]+") do
        entries[#entries + 1] = entry
    end
    return entries
end

print("== C module loader validation ==")
print("package.cpath = " .. tostring(package.cpath))

local entries = cpath_entries()
check("package.cpath is non-empty", #entries > 0,
    "no cpath entries; C modules will never resolve")

local cpath_has_so = false
for _, e in ipairs(entries) do
    if e:match("%.so") or e:match("%.dylib") or e:match("%.dll") then
        cpath_has_so = true
        break
    end
end
check("cpath contains shared-object patterns", cpath_has_so,
    "cpath entries lack .so/.dylib/.dll; native modules unreachable")

print("")
print("== Core runtime modules ==")

do
    local ok, mod = try_require("lunet")
    check("require('lunet') loads", ok, mod)
    if ok then
        check("lunet module is a table", type(mod) == "table",
            "type=" .. type(mod))
        check("lunet.spawn exists", type(mod.spawn) == "function",
            "spawn missing or wrong type")
    end
end

do
    local ok, mod = try_require("lunet.socket")
    check("require('lunet.socket') loads", ok, mod)
    if ok then
        check("lunet.socket is a table", type(mod) == "table",
            "type=" .. type(mod))
        check("lunet.socket.listen exists", type(mod.listen) == "function",
            "listen missing or wrong type")
        check("lunet.socket.connect exists", type(mod.connect) == "function",
            "connect missing or wrong type")
    end
end

print("")
print("== Optional C extension modules ==")

do
    local ok, mod = try_require("lunet.sqlite3")
    if ok then
        check("require('lunet.sqlite3') loads", true)
        check("lunet.sqlite3 is a table", type(mod) == "table",
            "type=" .. type(mod))
    else
        print("SKIP: lunet.sqlite3 not available (" .. tostring(mod) .. ")")
    end
end

do
    local has_ffi, ffi = pcall(require, "ffi")
    if has_ffi then
        check("require('ffi') loads (LuaJIT FFI)", true)

        local has_sodium = pcall(function() return ffi.load("sodium") end)
        if has_sodium then
            check("ffi.load('sodium') succeeds", true)
        else
            print("SKIP: libsodium not loadable via FFI (optional)")
        end
    else
        print("SKIP: ffi module not available (non-LuaJIT runtime)")
    end
end

print("")
print("== Loader-path sanity ==")

do
    local ok, err = try_require("nonexistent_module_that_should_never_exist_xyz")
    check("bogus module correctly fails to load", not ok, err)
    if not ok then
        local mentions_cpath = tostring(err):match("cpath") or tostring(err):match("no field")
        local mentions_path  = tostring(err):match("path")
        check("error message references search paths", mentions_cpath or mentions_path,
            "error lacks path info: " .. tostring(err):sub(1, 120))
    end
end

print("")
print(string.format("========== %d/%d tests passed ==========", pass_count, test_count))
if pass_count == test_count then
    os.exit(0)
else
    os.exit(1)
end
