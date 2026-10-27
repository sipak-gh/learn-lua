-- A branch the trace didn't expect: `luajit -jv sideexit.lua`

local function count(n)
  local small, big = 0, 0
  for i = 1, n do
    if i <= 500 then
      small = small + 1
    else
      big = big + 1               -- first taken at i = 501
    end
  end
  return small, big
end

print(count(1000))
