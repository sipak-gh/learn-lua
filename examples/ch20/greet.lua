-- A tiny module used by the bytecode and preload demos.
local M = {}

function M.hello(name)
  return "hello, " .. name
end

function M.fail()
  error("greet failed", 2)    -- level 2: blame the caller
end

function M.crash()
  local t = nil
  return t.x                  -- line 14: a runtime error
end

return M
