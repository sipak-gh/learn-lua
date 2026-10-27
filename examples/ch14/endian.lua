-- Endianness: the order of bytes inside a number.

local ffi = require("ffi")
local bit = require("bit")

print("little-endian:", ffi.abi("le"))

-- Look at the bytes of a uint32 through a union.
ffi.cdef [[ typedef union { uint32_t n; uint8_t b[4]; } u32bytes; ]]
local u = ffi.new("u32bytes")
u.n = 0x11223344
print(("%02x %02x %02x %02x"):format(u.b[0], u.b[1], u.b[2], u.b[3]))

-- Network protocols and many file formats are big-endian.
-- On a little-endian machine, bit.bswap reverses the bytes.
local function to_be32(n)
  if ffi.abi("le") then return bit.bswap(n) end
  return n
end
u.n = to_be32(0x11223344)
print(("%02x %02x %02x %02x"):format(u.b[0], u.b[1], u.b[2], u.b[3]))
print(bit.tohex(bit.bswap(0x11223344)))

-- Or build the number from bytes yourself; this works on any machine.
local b = ffi.new("uint8_t[4]", { 0x11, 0x22, 0x33, 0x44 })
local be = bit.bor(bit.lshift(b[0], 24), bit.lshift(b[1], 16), bit.lshift(b[2], 8), b[3])
print(bit.tohex(be))
