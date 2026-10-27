-- File system helpers.

local ffi = require("ffi")
local libc = require("stash.ffi.libc")

local M = {}

-- Creates a directory and its parents, like `mkdir -p`, by calling
-- mkdir(2) for "a", "a/b", "a/b/c" in turn. "Already exists" is fine.
function M.mkdir_p(path)
  local prefix = path:sub(1, 1) == "/" and "/" or ""
  for part in path:gmatch("[^/]+") do
    prefix = prefix .. part
    if ffi.C.mkdir(prefix, tonumber("755", 8)) ~= 0 then
      local errno = ffi.errno()              -- read it at once: the next C call may change it
      if errno ~= libc.EEXIST then
        return nil, prefix .. ": " .. libc.strerror(errno)
      end
    end
    prefix = prefix .. "/"
  end
  return true
end

-- "a/b/c.lua" -> "a/b"; "c.lua" -> "."
function M.dirname(path)
  return path:match("^(.*)/[^/]*$") or "."
end

function M.exists(path)
  local file = io.open(path)
  if file then
    file:close()
  end
  return file ~= nil
end

function M.read_file(path)
  local file, err = io.open(path, "rb")
  if file == nil then
    return nil, err
  end
  local data = file:read("*a")
  file:close()
  return data
end

-- Opens a file, calls fn(file), and closes the file even when fn raises
-- an error -- Lua has no `finally`, so pcall plays that part.
function M.with_file(path, mode, fn)
  local file, err = io.open(path, mode)
  if file == nil then
    return nil, err
  end
  local ok, result = pcall(fn, file)
  file:close()
  if not ok then
    error(result, 0)                         -- re-raise, unchanged
  end
  return true, result
end

-- Writes data to path via a temporary file and a rename, so a crash
-- never leaves a half-written file behind.
function M.write_atomic(path, data)
  local tmp = path .. ".tmp"
  local ok, err = M.with_file(tmp, "wb", function(file)
    assert(file:write(data))
  end)
  if not ok then
    return nil, err
  end
  return os.rename(tmp, path)
end

return M
