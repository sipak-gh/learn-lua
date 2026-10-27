-- Compressed blobs for page bodies.
--
-- A blob is an 8-byte header followed by zlib data:
--
--   bytes 0-3   length of the original data   (unsigned, big-endian)
--   bytes 4-7   CRC-32 of the original data   (unsigned, big-endian)
--   bytes 8-    the zlib stream
--
-- zlib's uncompress needs to know how much room to make, so we store the
-- length; the checksum catches data that was damaged on the way.

local ffi = require("ffi")
local bit = require("bit")
local Z = require("stash.ffi.zlib")

local band, bor, lshift, rshift, tobit = bit.band, bit.bor, bit.lshift, bit.rshift, bit.tobit

local M = {}

local HEADER = 8

-- CRC-32 as a signed 32-bit number, the form the bit library works with.
-- crc32 returns an unsigned long, which arrives as a 64-bit cdata number.
function M.crc32(data)
  return tobit(tonumber(Z.crc32(0, data, #data)))
end

-- A 32-bit number as 4 bytes, most significant first (big-endian), so
-- the blob reads the same on every machine.
local function u32_bytes(n)
  return string.char(band(rshift(n, 24), 0xff), band(rshift(n, 16), 0xff),
                     band(rshift(n, 8), 0xff), band(n, 0xff))
end

local function u32_at(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d)   -- signed, like tobit
end

function M.pack(data)
  local bound = Z.compressBound(#data)
  local out = ffi.new("Bytef[?]", bound)                     -- a variable-length array
  local out_len = ffi.new("uLong[1]", bound)                 -- in: room, out: bytes used
  local rc = Z.compress2(out, out_len, data, #data, Z.Z_BEST_COMPRESSION)
  if rc ~= Z.Z_OK then
    error("compress2 failed with code " .. rc)
  end
  return u32_bytes(#data) .. u32_bytes(M.crc32(data)) .. ffi.string(out, out_len[0])
end

-- Returns the original data, or nil and a message for a damaged blob.
function M.unpack(blob)
  if #blob < HEADER then
    return nil, "blob too short"
  end
  local size = u32_at(blob, 1)
  local out = ffi.new("Bytef[?]", size)
  local out_len = ffi.new("uLong[1]", size)
  -- A Lua string converts to `const Bytef *` for the call; blob + 8 would
  -- not work on a string, so we pass the zlib part as its own string.
  local stream = blob:sub(HEADER + 1)
  local rc = Z.uncompress(out, out_len, stream, #stream)
  if rc ~= Z.Z_OK or out_len[0] ~= size then
    return nil, "corrupt data (zlib error " .. rc .. ")"
  end
  local data = ffi.string(out, size)
  if M.crc32(data) ~= u32_at(blob, 5) then
    return nil, ("checksum mismatch: %s, expected %s"):format(bit.tohex(M.crc32(data)),
                                                             bit.tohex(u32_at(blob, 5)))
  end
  return data
end

function M.version()
  return ffi.string(Z.zlibVersion())
end

return M
