-- A stateful iterator keeps its state in upvalues. The for loop only
-- needs the function; s and ctl are unused.

local function words(s)
  local pos = 1
  return function()
    local first, last = s:find("%a+", pos)
    if first == nil then
      return nil
    end
    pos = last + 1
    return s:sub(first, last)
  end
end

for w in words("one, two;  three") do
  print(w)
end

-- The iterator is an ordinary function: you can call it by hand, too.
local it = words("call me")
print(it(), it(), it())
