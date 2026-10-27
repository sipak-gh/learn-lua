-- Buffer: a growable array of bytes in C memory, for data that arrives
-- from C in pieces (Chapter 16 collects downloads in one).
--
-- The buffer is a C struct with Lua methods attached by ffi.metatype. Its
-- bytes live in memory from malloc, which the garbage collector knows
-- nothing about, so the __gc metamethod hands them back with free().

local ffi = require("ffi")
require("stash.ffi.libc")                    -- declares malloc, realloc, free

ffi.cdef [[
typedef struct {
  uint8_t *data;                             /* NULL until the first append */
  size_t len;                                /* bytes in use */
  size_t cap;                                /* bytes allocated */
} stash_buffer;
]]

local C = ffi.C

local Buffer = {}
Buffer.__index = Buffer

-- Makes room for n more bytes, doubling the allocation as needed.
-- size_t fields read as 64-bit cdata; tonumber turns them into Lua numbers.
function Buffer:reserve(n)
  local need = tonumber(self.len) + n
  local cap = tonumber(self.cap)
  if need <= cap then
    return
  end
  cap = math.max(cap, 64)
  while cap < need do
    cap = cap * 2
  end
  local data = C.realloc(self.data, cap)     -- realloc(NULL, n) works like malloc(n)
  if data == nil then                        -- a NULL pointer compares equal to nil
    error("out of memory", 2)
  end
  self.data = ffi.cast("uint8_t *", data)
  self.cap = cap
end

-- Appends a Lua string, or len bytes starting at a C pointer.
function Buffer:append(data, len)
  len = len or #data
  self:reserve(len)
  ffi.copy(self.data + self.len, data, len)  -- pointer arithmetic: data + offset
  self.len = self.len + len
  return self
end

-- The byte at position i (0-based, like C).
function Buffer:byte(i)
  assert(i >= 0 and i < self.len, "index out of range")
  return self.data[i]
end

function Buffer:tostring()
  return ffi.string(self.data, self.len)     -- copies the bytes into a Lua string
end

function Buffer:reset()
  self.len = 0
end

Buffer.__tostring = Buffer.tostring

function Buffer.__len(self)
  return tonumber(self.len)
end

function Buffer.__gc(self)
  C.free(self.data)                          -- free(NULL) is allowed
end

-- ffi.metatype returns a constructor for the C type; every object it
-- makes shares the metatable. ffi.new zero-fills the struct.
local new = ffi.metatype("stash_buffer", Buffer)

return {
  new = function()
    return new()
  end,
}
