-- A hot loop: run it with `luajit -jv hot.lua` to watch the JIT.

local function sum_squares(n)
  local sum = 0
  for i = 1, n do
    sum = sum + i * i
  end
  return sum
end

print(sum_squares(10))        -- 10 iterations: too few to get hot
print(sum_squares(1000))      -- hot: the loop is traced and compiled
