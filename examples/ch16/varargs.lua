-- Variadic C functions (...) get no type information for the extra
-- arguments, so the FFI picks one from the Lua value.
local ffi = require("ffi")

ffi.cdef [[
int printf(const char *format, ...);
]]

ffi.C.printf("%.1f\n", 42)                       -- a Lua number goes as a double
ffi.C.printf("%d\n", ffi.cast("int", 42))        -- cast when C wants an int
ffi.C.printf("%ld\n", ffi.cast("long", 2^40))    -- ...or a long
ffi.C.printf("%s has %d bytes\n", "hello", ffi.new("int", #"hello"))
ffi.C.printf("%lld\n", 123LL)                    -- int64 cdata stays int64
-- ffi.C.printf("%d\n", 42) prints garbage: printf reads an int from a
-- register where the double was never put.
