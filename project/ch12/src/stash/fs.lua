-- File system helpers.

local M = {}

-- Quotes a string for the shell: 'it'\''s' is how sh spells "it's".
local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Creates a directory and its parents, like `mkdir -p`.
-- Note: in LuaJIT os.execute returns the raw wait status (0 = success).
function M.mkdir_p(path)
  if os.execute("mkdir -p " .. shell_quote(path)) ~= 0 then
    return nil, "cannot create directory " .. path
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
