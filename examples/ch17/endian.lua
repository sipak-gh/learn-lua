-- The same 4 bytes read as one 32-bit number: byte order matters.
local ffi = require("ffi")
local bit = require("bit")

print("little-endian CPU:", ffi.abi("le"))

local n = ffi.new("uint32_t[1]", 0x01020304)
local bytes = ffi.cast("uint8_t *", n)       -- look at the same memory byte by byte
print(bytes[0], bytes[1], bytes[2], bytes[3])

-- A file format must pick one order. Big-endian ("network order") puts
-- the most significant byte first. Building the bytes by hand gives the
-- same result on every CPU:
local function u32_be(x)
  return string.char(bit.band(bit.rshift(x, 24), 0xff), bit.band(bit.rshift(x, 16), 0xff),
                     bit.band(bit.rshift(x, 8), 0xff), bit.band(x, 0xff))
end
print(u32_be(0x01020304):byte(1, -1))

-- Copying memory gives the CPU's order, which is why it's not portable:
print(ffi.string(n, 4):byte(1, -1))

-- bit.bswap reverses the bytes of a 32-bit number.
print(bit.tohex(bit.bswap(0x01020304)))

-- Reading back: shift each byte into place.
local function read_u32_be(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return bit.bor(bit.lshift(a, 24), bit.lshift(b, 16), bit.lshift(c, 8), d)
end
print(bit.tohex(read_u32_be("\1\2\3\4", 1)), read_u32_be("\255\255\255\254", 1))
