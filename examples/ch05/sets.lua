-- A set: the elements are keys, the values are just `true`.
local function Set(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

local keywords = Set{ "and", "break", "do", "else", "end" }
print(keywords["do"], keywords["while"])   -- membership is one lookup

local function union(a, b)
  local out = {}
  for k in pairs(a) do out[k] = true end
  for k in pairs(b) do out[k] = true end
  return out
end

local function to_sorted_list(s)
  local list = {}
  for k in pairs(s) do list[#list + 1] = k end
  table.sort(list)
  return list
end

local u = union(Set{ "x", "y" }, Set{ "y", "z" })
print(table.concat(to_sorted_list(u), " "))

-- Remove duplicates while keeping the first-seen order.
local seen, unique = {}, {}
for _, w in ipairs({ "b", "a", "b", "c", "a" }) do
  if not seen[w] then
    seen[w] = true
    unique[#unique + 1] = w
  end
end
print(table.concat(unique, " "))
