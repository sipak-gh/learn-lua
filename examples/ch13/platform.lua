-- Where am I running? The FFI knows.

local ffi = require("ffi")

print("os:  ", ffi.os)                -- "Linux", "OSX", "Windows", "BSD", ...
print("arch:", ffi.arch)              -- "x64", "arm64", "x86", ...
for _, flag in ipairs({ "32bit", "64bit", "le", "be", "fpu", "hardfp", "win" }) do
  print(("abi(%q) = %s"):format(flag, tostring(ffi.abi(flag))))
end

-- Types whose size depends on the platform:
print("long:", ffi.sizeof("long"), "size_t:", ffi.sizeof("size_t"))

-- Choose declarations by platform when they differ.
if ffi.os == "Windows" then
  ffi.cdef("int _getpid(void);")
  print("pid via _getpid", ffi.C._getpid() > 0)
else
  ffi.cdef("int getpid(void);")
  print("pid via getpid", ffi.C.getpid() > 0)
end
