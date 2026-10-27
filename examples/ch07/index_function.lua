-- __index can be a function: it runs for every missing key.
local squares = setmetatable({}, {
  __index = function(t, n)
    print("  computing " .. n)
    local value = n * n
    rawset(t, n, value)          -- cache it: next time the key exists
    return value
  end,
})

print(squares[12])
print(squares[12])               -- cached: __index is not called again

-- A default value for every missing key.
local counts = setmetatable({}, { __index = function() return 0 end })
for _, word in ipairs({ "a", "b", "a" }) do
  counts[word] = counts[word] + 1
end
print(counts.a, counts.b, counts.zzz)
