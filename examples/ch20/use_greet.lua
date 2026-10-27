-- Loads greet from whatever the path finds first (greet.lua or a .luac
-- placed via package.path) and shows how errors are reported.
local greet = require("greet")
print(greet.hello("bytecode"))
print(pcall(greet.crash))
