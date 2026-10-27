-- Two ways to hold bytes: Lua strings (immutable) and uint8_t arrays (mutable).
local ffi = require("ffi")

local s = "A\0B\255"                       -- a string may hold any byte, even zero
print(#s, s:byte(1, -1))                   -- # counts bytes; byte() gives their values
print(string.char(72, 105))                -- and back

local buf = ffi.new("uint8_t[?]", 8)       -- 8 zero bytes, mutable
ffi.copy(buf, s, #s)                       -- copy the string's 4 bytes in
buf[4] = 0x43                              -- 'C'
ffi.fill(buf + 5, 3, 0x2e)                 -- three '.' after it
print(buf[1], buf[3], buf[4])

print(#ffi.string(buf))                    -- without a length: stops at the first zero
print(#ffi.string(buf, 8))                 -- with a length: all 8 bytes
-- Show unprintable bytes as \ddd escapes.
print((ffi.string(buf, 8):gsub("[^%g ]", function(c) return "\\" .. c:byte() end)))
