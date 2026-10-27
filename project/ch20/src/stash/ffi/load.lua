-- Loads a shared C library, trying several names in turn.
--
-- ffi.load("sqlite3") looks for libsqlite3.so (Linux) or libsqlite3.dylib
-- (macOS). On Linux that unversioned name often comes only with the
-- development package, so we also try the versioned name ("soname")
-- that every installed copy has: libsqlite3.so.0.
--
-- First, though, we look in ffi.C: the single-file stash program
-- (Chapter 20) has SQLite and zlib linked in, and exports their
-- functions, so there is nothing to load. `symbol` is any function the
-- library has; finding it in ffi.C means the library is there.

local ffi = require("ffi")

return function(names, symbol)
  if pcall(function() return ffi.C[symbol] end) then
    return ffi.C
  end
  local problems = {}
  for _, name in ipairs(names) do
    local ok, lib = pcall(ffi.load, name)
    if ok then
      return lib
    end
    problems[#problems + 1] = lib
  end
  error("cannot load C library: " .. table.concat(problems, "; "), 2)
end
