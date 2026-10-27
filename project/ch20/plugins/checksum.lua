-- checksum: CRC-32 of saved pages, computed by zlib through the FFI.
--
-- This plugin needs `require`, so it only works when trusted:
--
--   trusted_plugins = { "checksum" }
--
-- (stash itself already binds zlib; a plugin makes its own bindings.)

local ffi = require("ffi")

-- C declarations are global to the process. Declaring a function twice
-- is allowed (the first declaration wins); declaring a struct twice is
-- an error.
ffi.cdef [[
unsigned long crc32(unsigned long crc, const unsigned char *buf, unsigned int len);
]]
-- "z" means libz.so, which only the zlib development package installs;
-- libz.so.1 is the library itself.
local ok, zlib = pcall(ffi.load, "z")
if not ok then
  zlib = ffi.load("libz.so.1")
end

stash.command("crc", {
  usage = "crc ID",
  help = "CRC-32 of a saved page",
  run = function(opts)
    local id = tonumber(opts[1]) or stash.fail("missing or bad ID")
    local page = stash.page(id) or stash.not_found("no saved page for #%d", id)
    local crc = tonumber(zlib.crc32(0, page, #page))  -- unsigned long: cdata
    stash.print(("%08x  #%d"):format(crc, id))
  end,
})
