-- C reports errors through a return value plus the global `errno`.

local ffi = require("ffi")
ffi.cdef [[
int mkdir(const char *path, unsigned int mode);
int rmdir(const char *path);
char *strerror(int errnum);
]]

local function try_mkdir(path)
  local rc = ffi.C.mkdir(path, tonumber("755", 8))
  if rc ~= 0 then
    local errno = ffi.errno()        -- read it right away
    return nil, ("%s: %s (errno %d)"):format(path, ffi.string(ffi.C.strerror(errno)), errno)
  end
  return true
end

print(try_mkdir("demo-dir"))
print(try_mkdir("demo-dir"))          -- already exists
print(try_mkdir("no/such/parent"))
print(try_mkdir("/stash-demo"))       -- no permission to write in /
ffi.C.rmdir("demo-dir")

-- ffi.errno(new) sets errno and returns the old value.
ffi.errno(0)
print(ffi.errno())
