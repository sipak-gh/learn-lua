-- No `finally` in Lua: catch the error, clean up, then raise it again.
local function open(name)
  print("open " .. name)
  return { name = name, close = function(self) print("close " .. self.name) end }
end

local function with(resource, fn)
  local ok, err = pcall(fn, resource)
  resource:close()                -- runs whether fn failed or not
  if not ok then
    error(err, 0)                 -- level 0: keep the original position
  end
  return err                      -- on success, err holds fn's first result
end

print(with(open("a"), function(r) return "used " .. r.name end))
print(pcall(with, open("b"), function(r) error("disk full") end))
