-- == compares tables by identity. Tests usually want "same contents".
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not same(v, b[k]) then        -- recursion handles nested tables
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then              -- a key that only b has
      return false
    end
  end
  return true
end

print({ 1, 2 } == { 1, 2 })
print(same({ 1, 2 }, { 1, 2 }))
print(same({ tags = { "a" }, n = 1 }, { n = 1, tags = { "a" } }))
print(same({ 1, 2 }, { 1, 2, 3 }), same({ 1, 2, 3 }, { 1, 2 }))
print(same({ x = { 1 } }, { x = { 2 } }))
