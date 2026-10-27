-- LuaJIT's bit library: 32-bit integer operations on Lua numbers.
local bit = require("bit")
local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

print(band(0xF0, 0x3C), bor(0xF0, 0x0F), bxor(0xFF, 0x0F))
print(lshift(1, 4), rshift(256, 4))

-- Results are signed 32-bit numbers:
print(lshift(1, 31), bit.tobit(0xFFFFFFFF), rshift(-1, 28), bit.arshift(-256, 4))

-- tohex shows the 32 bits; tobit wraps any number into that range.
print(bit.tohex(-1), bit.tohex(255), bit.tohex(255, 2), bit.tohex(255, -4))
print(bit.tobit(2^32 + 5))

-- Flags: one bit each.
local READ, WRITE, EXEC = 1, 2, 4
local mode = bor(READ, EXEC)
print(band(mode, WRITE) ~= 0, band(mode, EXEC) ~= 0)

-- On 64-bit cdata, the same functions work on all 64 bits.
print(bit.tohex(bit.band(0xFFFF00000000LL, 0xF0F000000000LL)), bit.lshift(1LL, 40))
