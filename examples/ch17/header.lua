-- Reading a binary header through a C struct, and why byte order bites.
package.path = "project/ch17/src/?.lua;" .. package.path
local ffi = require("ffi")
local bit = require("bit")
local compress = require("stash.compress")

ffi.cdef [[
struct blob_header { uint32_t size; uint32_t crc; };
]]

local blob = compress.pack("hello")
print(#blob, ffi.sizeof("struct blob_header"))

-- Point a struct at the string's bytes: no copy. Valid while `blob` lives.
local h = ffi.cast("const struct blob_header *", blob)
print(h.size, bit.tohex(h.crc))                -- read in the CPU's byte order

-- The header is big-endian; on a little-endian CPU, swap.
local function be32(n)
  return ffi.abi("le") and bit.bswap(n) or n
end
print(be32(h.size), bit.tohex(be32(h.crc)))
