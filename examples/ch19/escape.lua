-- Why a plugin with the FFI is not sandboxed at all.

local PASSWORD = "secret"                -- the host's own constant

local plugin = [[
local ffi = require("ffi")
ffi.cdef [=[ int getpid(void); ]=]
print("plugin sees pid", ffi.C.getpid() > 0)   -- any C function

-- Lua strings are immutable... unless you write to their memory.
local p = ffi.cast("uint8_t *", "secret")       -- same interned string
p[0] = string.byte("X")
]]

local env = { require = require, print = print, string = string }
local chunk = assert(load(plugin, "=evil", "t"))
setfenv(chunk, env)
chunk()

print(PASSWORD)                         -- the host's string changed
print(PASSWORD == "secret")
