-- ffi.copy and ffi.fill: memcpy and memset for Lua.

local ffi = require("ffi")

local buf = ffi.new("char[16]")

-- ffi.copy(dst, str) copies a Lua string plus its terminating zero.
ffi.copy(buf, "hello")
print(ffi.string(buf))

-- ffi.copy(dst, src, len) copies exactly len bytes, from a string or a pointer.
ffi.copy(buf + 5, ", world", 7)
print(ffi.string(buf))          -- up to the first zero (ffi.new zero-filled buf)
print(ffi.string(buf, 12))      -- with a length: exactly 12 bytes

-- ffi.fill(dst, len, byte) sets len bytes; the byte defaults to 0.
ffi.fill(buf, 5, string.byte("*"))
print(ffi.string(buf, 12))
ffi.fill(buf, 16)
print(#ffi.string(buf), #ffi.string(buf, 16))

-- Copy between two C arrays:
local a = ffi.new("int[3]", { 1, 2, 3 })
local b = ffi.new("int[3]")
ffi.copy(b, a, ffi.sizeof(a))   -- the length is in bytes!
print(b[0], b[1], b[2])
