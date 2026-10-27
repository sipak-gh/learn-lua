-- Lua has no keyword arguments. Pass one table instead.
local function box(opts)
  local width = opts.width or 10
  local char = opts.char or "*"
  local title = opts.title or ""
  return title .. string.rep(char, width)
end

-- f{...} is short for f({...}), and f"..." for f("...").
print(box{ width = 5 })
print(box{ char = "=", title = "> ", width = 3 })
print(box{})

local function shout(s) return s:upper() .. "!" end
print(shout"hey")
