-- Variadic C functions (the "..." in printf) get no type information,
-- so the FFI uses default rules: a Lua number is passed as a double.

local ffi = require("ffi")
ffi.cdef [[
int printf(const char *format, ...);
]]

ffi.C.printf("%%g  with a Lua number: %g\n", 42)                -- fine: %g expects a double
ffi.C.printf("%%d  with a Lua number: %d\n", 42)                -- wrong: %d expects an int
ffi.C.printf("%%d  with an int:       %d\n", ffi.new("int", 42))
ffi.C.printf("%%d  with a cast:       %d\n", ffi.cast("int", 42))
ffi.C.printf("%%s  with a Lua string: %s\n", "strings are fine")
ffi.C.printf("%%lld with 1LL:         %lld\n", 1LL)              -- int64_t literal
