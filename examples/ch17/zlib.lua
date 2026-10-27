-- Compress and uncompress a string with zlib's one-call functions.
local ffi = require("ffi")

ffi.cdef [[
typedef unsigned long uLong;
const char *zlibVersion(void);
uLong compressBound(uLong sourceLen);
int compress2(uint8_t *dest, uLong *destLen, const uint8_t *source, uLong sourceLen, int level);
int uncompress(uint8_t *dest, uLong *destLen, const uint8_t *source, uLong sourceLen);
]]
local z = ffi.load("z")

local function compress(data, level)
  local bound = z.compressBound(#data)        -- the worst case for this length
  local out = ffi.new("uint8_t[?]", bound)
  local out_len = ffi.new("uLong[1]", bound)  -- in: room in out; out: bytes written
  assert(z.compress2(out, out_len, data, #data, level) == 0)
  return ffi.string(out, out_len[0])
end

-- zlib doesn't record the original size; the caller must know it.
local function uncompress(blob, size)
  local out = ffi.new("uint8_t[?]", size)
  local out_len = ffi.new("uLong[1]", size)
  local rc = z.uncompress(out, out_len, blob, #blob)
  if rc ~= 0 then
    return nil, rc
  end
  return ffi.string(out, out_len[0])
end

print("zlib " .. ffi.string(z.zlibVersion()))
local text = assert(io.open(arg[0])):read("*a")  -- this file's own source
for _, level in ipairs({ 0, 1, 6, 9 }) do
  print(("level %d: %d -> %d bytes"):format(level, #text, #compress(text, level)))
end
local same = ("na"):rep(1000)
print(("repeats: %d -> %d bytes"):format(#same, #compress(same, 9)))
print(z.compressBound(#text))

local blob = compress(text, 9)
print(uncompress(blob, #text) == text)
print(uncompress(blob, 100))                 -- too little room
print(uncompress(blob:sub(1, 20), #text))    -- cut short
print(uncompress("not zlib data", #text))    -- not zlib at all
