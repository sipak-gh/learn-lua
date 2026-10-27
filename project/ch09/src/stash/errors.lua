-- Errors stash expects -- bad usage, a missing entry, a failed operation --
-- are raised as tables with a `kind` and a `message`. Any other error
-- value (usually a string from a runtime error) means a bug.

local M = {}

local Error = {}
Error.__index = Error

function Error.__tostring(e)
  return e.message
end

-- The process exit code for each kind of error.
M.EXIT = { not_found = 1, usage = 2, failed = 2, bug = 2 }

local function raise(kind, fmt, ...)
  -- A table error value carries no "file:line:" prefix, so no level is needed.
  error(setmetatable({ kind = kind, message = fmt:format(...) }, Error))
end

function M.usage(fmt, ...) raise("usage", fmt, ...) end
function M.not_found(fmt, ...) raise("not_found", fmt, ...) end
function M.fail(fmt, ...) raise("failed", fmt, ...) end

function M.is_error(value)
  return getmetatable(value) == Error
end

return M
