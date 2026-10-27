-- Alignment and packing: where the fields really are.

local ffi = require("ffi")
ffi.cdef [[
typedef struct { uint8_t tag; uint32_t value; uint8_t flag; } loose;
typedef struct { uint32_t value; uint8_t tag; uint8_t flag; } ordered;
typedef struct __attribute__((packed)) { uint8_t tag; uint32_t value; uint8_t flag; } packed;
]]

-- Each field starts at a multiple of its alignment, and the whole struct
-- is padded to a multiple of its largest alignment.
for _, name in ipairs({ "loose", "ordered", "packed" }) do
  print(("%-8s size %2d  align %d  offsets tag=%d value=%d flag=%d"):format(
    name, ffi.sizeof(name), ffi.alignof(name),
    ffi.offsetof(name, "tag"), ffi.offsetof(name, "value"), ffi.offsetof(name, "flag")))
end

-- Some C types have different sizes on different systems.
print(ffi.sizeof("long"), ffi.sizeof("void *"), ffi.sizeof("size_t"))
