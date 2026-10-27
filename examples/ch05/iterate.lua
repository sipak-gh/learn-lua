local t = { "a", "b", nil, "d", x = 1, y = 2 }

-- ipairs: 1, 2, 3, ... in order, stopping at the first nil.
for i, v in ipairs(t) do io.write(i, "=", v, " ") end print()

-- pairs: every key, in an unspecified order.
local keys = {}
for k, v in pairs(t) do keys[#keys + 1] = tostring(k) end
print(#keys .. " keys: " .. table.concat(keys, " "))

-- For a stable order, collect the keys and sort them.
local scores = { carol = 7, alice = 9, bob = 8 }
local names = {}
for name in pairs(scores) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do print(name, scores[name]) end

-- While iterating with pairs you may change or clear (set to nil)
-- existing fields, but never add new ones.
for name in pairs(scores) do
  if scores[name] < 9 then scores[name] = nil end
end
print(next(scores))
