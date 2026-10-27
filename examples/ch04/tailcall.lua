-- `return f(x)` is a proper tail call: it reuses the caller's stack frame.
local function count_down(n)
  if n == 0 then
    return "done"
  end
  return count_down(n - 1)     -- tail call: no stack growth
end
print(count_down(10000000))

-- Not a tail call: the `1 +` must run after f returns, so frames pile up.
local function depth(n)
  if n == 0 then
    return 0
  end
  return 1 + depth(n - 1)
end
print(depth(10000))
print(pcall(depth, 10000000))
