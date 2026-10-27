-- Raw bindings to zlib (from zlib.h and zconf.h).

local ffi = require("ffi")
local load = require("stash.ffi.load")

ffi.cdef [[
typedef unsigned char Bytef;
typedef unsigned long uLong;                  /* 64 bits on Linux and macOS, 32 on Windows */
typedef unsigned int uInt;

enum {
  Z_OK = 0,
  Z_DATA_ERROR = -3,
  Z_MEM_ERROR = -4,
  Z_BUF_ERROR = -5,
  Z_BEST_COMPRESSION = 9,
};

const char *zlibVersion(void);
uLong compressBound(uLong sourceLen);
int compress2(Bytef *dest, uLong *destLen, const Bytef *source, uLong sourceLen, int level);
int uncompress(Bytef *dest, uLong *destLen, const Bytef *source, uLong sourceLen);
uLong crc32(uLong crc, const Bytef *buf, uInt len);
]]

return load({ "z", "libz.so.1" })
