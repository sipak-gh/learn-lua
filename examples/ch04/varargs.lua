-- `...` stands for all extra arguments.
local function count(...)
  return select("#", ...)      -- the number of arguments, nils included
end
print(count(), count(1, 2), count(nil, nil))

-- select(n, ...) returns the arguments from n on.
print(select(2, "a", "b", "c"))
print(select(-1, "a", "b", "c")) -- negative counts from the end

-- Loop over the arguments.
local function sum(...)
  local total = 0
  for i = 1, select("#", ...) do
    total = total + (select(i, ...))  -- parentheses keep one value
  end
  return total
end
print(sum(1, 2, 3, 4))

-- {...} packs them into a table; # is unreliable if there are nils.
local function pack(...)
  return { n = select("#", ...), ... }
end
local p = pack("a", nil, "c")
print(p.n, p[1], p[2], p[3])

-- unpack(t, i, j) is the opposite: table items -> separate values.
print(unpack({ 1, 2, 3 }))
print(unpack(p, 1, p.n))      -- pass n to keep trailing/middle nils

-- Pass the arguments on to another function unchanged.
-- string.format fills in the %s and %d placeholders (Chapter 6).
local function log(fmt, ...)
  print("[log] " .. string.format(fmt, ...))
end
log("%s has %d items", "cart", 3)
