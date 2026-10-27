-- Any value can be an error. A table can carry fields for the handler.
local AppError = {}
AppError.__index = AppError
AppError.__tostring = function(e) return e.kind .. ": " .. e.message end

local function fail(kind, message)
  error(setmetatable({ kind = kind, message = message }, AppError))
end

local ok, err = pcall(fail, "not_found", "no such entry")
print(ok, type(err), err.kind, err.message)
print(tostring(err))
print(getmetatable(err) == AppError)

-- A string error from Lua itself is not an AppError: that's a bug.
local _, bug = pcall(function() return nil .. "x" end)
print(type(bug), getmetatable(bug) == AppError)
