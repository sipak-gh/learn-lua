local nums = { 5, 2, 8, 1 }
table.sort(nums)                       -- ascending, with <
print(table.concat(nums, " "))

table.sort(nums, function(a, b) return a > b end)
print(table.concat(nums, " "))         -- descending

-- Sort records by one field, then by another.
local people = {
  { name = "carol", age = 30 },
  { name = "alice", age = 30 },
  { name = "bob", age = 25 },
}
table.sort(people, function(a, b)
  if a.age ~= b.age then
    return a.age < b.age
  end
  return a.name < b.name
end)
for _, p in ipairs(people) do print(p.age, p.name) end

-- Strings sort byte by byte: upper case before lower case.
local words = { "banana", "apple", "Cherry" }
table.sort(words)
print(table.concat(words, " "))
table.sort(words, function(a, b) return a:lower() < b:lower() end)
print(table.concat(words, " "))
