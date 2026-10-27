-- ffi.new creates C values owned by Lua's garbage collector.

local ffi = require("ffi")

-- A scalar: a "boxed" C int. You can read it, but not change it.
local n = ffi.new("int", 42)
print(type(n), tonumber(n), n + 1)

-- To hold one C value you can change, use an array of one.
local d = ffi.new("double[1]", 2.5)
d[0] = d[0] * 2
print(d[0])

-- Arrays: fixed size, zero-filled, indexed from 0.
local a = ffi.new("int[5]")
print(a[0], a[4], ffi.sizeof(a))
for i = 0, 4 do a[i] = i * i end
print(a[0], a[1], a[2], a[3], a[4])

-- Initializers: a list of values or a Lua table.
local b = ffi.new("int[5]", 1, 2)          -- the rest stay 0
local c = ffi.new("int[5]", { 7, 8, 9 })
local e = ffi.new("int[5]", 3)             -- ONE initializer fills every element
print(b[0], b[1], b[2], "|", c[0], c[2], c[4], "|", e[0], e[4])

-- VLA: "[?]" leaves the size open; pass it as the first argument.
local size = 3 + 2
local bytes = ffi.new("uint8_t[?]", size)
print(ffi.sizeof(bytes), ffi.typeof(bytes))
local bytes2 = ffi.new("uint8_t[?]", 4, { 1, 2, 3, 4 })
print(bytes2[3])

-- Out of range writes are NOT checked. bytes[100] = 1 would corrupt memory.

-- Character arrays and strings:
local name = ffi.new("char[16]", "stash")  -- copies the bytes and a terminating 0
print(ffi.string(name), ffi.sizeof(name))

-- Creating the same type again and again? Parse it once with ffi.typeof:
local int_array = ffi.typeof("int[?]")
local x = int_array(1000)
print(ffi.sizeof(x))
