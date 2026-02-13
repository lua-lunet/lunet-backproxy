io.stdout:setvbuf("no")
local socket = require("lunet.socket")

print("=== Socket module API ===")
for k, v in pairs(socket) do
    print(string.format("%s: %s", k, type(v)))
end
