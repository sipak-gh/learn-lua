-- A module is a file that returns a table.
print("loading greet, module name: " .. ...)   -- require passes the name as `...`

local M = {}

local count = 0                    -- private: a local, not exported

function M.hello(name)
  count = count + 1
  return "hello, " .. name
end

function M.count()
  return count
end

return M
