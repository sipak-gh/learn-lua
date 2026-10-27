-- Lifetimes: keep memory alive while C (or a pointer) still uses it.

local ffi = require("ffi")
ffi.cdef [[
typedef struct item { const char *name; int *values; int count; } item;
]]

-- WRONG (don't do this): the arrays below are only referenced by the struct's
-- pointer fields. The GC does not follow C pointers, so it may free them
-- while `bad` still points at them.
--
--   local bad = ffi.new("item")
--   bad.values = ffi.new("int[3]", { 1, 2, 3 })   -- garbage right away!
--   bad.name = "temp" .. 1                        -- same for this string

-- RIGHT: keep a Lua reference ("anchor") for as long as the pointer is used.
local function new_item(name, values)
  local arr = ffi.new("int[?]", #values, values)
  local it = ffi.new("item", { name = name, values = arr, count = #values })
  return { c = it, anchors = { name, arr } }   -- the table keeps both alive
end

local x = new_item("scores", { 7, 8, 9 })
collectgarbage(); collectgarbage()           -- safe: the anchors hold on
local it = x.c
print(ffi.string(it.name), it.count, it.values[0] + it.values[1] + it.values[2])

-- A Lua string passed straight to a C function is only valid during that
-- call. Fine for strlen or setenv (which copies it); not fine if C keeps the
-- pointer for later, like putenv does. Then copy it into memory you own.
ffi.cdef [[ size_t strlen(const char *s); ]]
print(tonumber(ffi.C.strlen("only needed during the call")))
