-- Who frees the memory? ffi.new vs. malloc + ffi.gc.

local ffi = require("ffi")
ffi.cdef [[
void *malloc(size_t size);
void free(void *ptr);
]]
local C = ffi.C

-- 1. ffi.new: the garbage collector owns the memory. Nothing to free.
local a = ffi.new("uint8_t[?]", 1024)
a[0] = 1

-- 2. malloc: C owns the memory. You must free it exactly once.
local p = ffi.cast("uint8_t *", C.malloc(1024))
assert(p ~= nil, "out of memory")
p[0] = 1
C.free(p)
p = nil                      -- don't keep a dangling pointer around

-- 3. ffi.gc attaches a finalizer: free is called when the cdata is collected.
local freed = 0
local function my_free(ptr)
  freed = freed + 1
  C.free(ptr)
end
local q = ffi.gc(ffi.cast("uint8_t *", C.malloc(64)), my_free)
q = nil
collectgarbage(); collectgarbage()
print("freed by gc:", freed)

-- 4. ffi.gc(ptr, nil) removes the finalizer: you take ownership back,
--    e.g. before freeing by hand or handing the pointer to C for good.
local r = ffi.gc(ffi.cast("uint8_t *", C.malloc(64)), my_free)
ffi.gc(r, nil)
my_free(r)                   -- freed once, by us
r = nil
collectgarbage(); collectgarbage()
print("total frees:", freed)
