-- CRC-32 checksums with zlib: a 32-bit fingerprint of some bytes.
local ffi = require("ffi")
local bit = require("bit")

ffi.cdef [[
unsigned long crc32(unsigned long crc, const uint8_t *buf, unsigned int len);
]]
local z = ffi.load("z")

local c = z.crc32(0, "hello", 5)
print(c, type(c))                            -- unsigned long: 64-bit cdata
print(tonumber(c), bit.tohex(tonumber(c)))

-- One changed byte changes the checksum completely.
local d = tonumber(z.crc32(0, "hellp", 5))
print(d, bit.tohex(d))
print(bit.tobit(d))                          -- the same 32 bits, in bit's signed form

-- Feed it in pieces: pass the running value back in.
local running = 0
for _, piece in ipairs({ "he", "ll", "o" }) do
  running = z.crc32(running, piece, #piece)
end
print(running == c)
