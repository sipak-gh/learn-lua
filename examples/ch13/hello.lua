-- Calling a C function from Lua: declare it, then call it.

local ffi = require("ffi")

-- 1. Tell the FFI what the function looks like, in plain C.
ffi.cdef [[
int printf(const char *format, ...);
]]

-- 2. Call it through ffi.C, the C library that is already loaded.
local n = ffi.C.printf("Hello from %s, %d + %d = %d\n", "C", ffi.new("int", 2),
                       ffi.new("int", 3), ffi.new("int", 5))
print("printf returned", n, type(n))
