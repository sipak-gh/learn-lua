-- The generic for walks over whatever an iterator function gives it.
-- ipairs: the items of an array, in order, with their index.
local fruits = { "apple", "banana", "cherry" }
for i, fruit in ipairs(fruits) do
  print(i, fruit)
end

-- pairs: every key and value of a table, in no particular order.
local ages = { ada = 36, alan = 41 }
for name, age in pairs(ages) do
  print(name, age)
end
