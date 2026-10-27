-- A generator: a coroutine that yields values one by one. Recursive
-- walks are where they shine: the recursion keeps the state for you.

local tree = {
  value = "root",
  { value = "a", { value = "a1" }, { value = "a2" } },
  { value = "b", { value = "b1" } },
}

-- Depth-first walk; yields each node's value and its depth.
local function walk(node, depth)
  coroutine.yield(node.value, depth)
  for _, child in ipairs(node) do
    walk(child, depth + 1)                   -- yields from deep inside work too
  end
end

local function nodes(root)
  return coroutine.wrap(function() walk(root, 0) end)
end

for value, depth in nodes(tree) do
  print(("  "):rep(depth) .. value)
end

-- All permutations of an array, generated in place (no lists of lists).
local function permute(a, n)
  if n <= 1 then
    coroutine.yield(a)
    return
  end
  for i = 1, n do
    a[n], a[i] = a[i], a[n]
    permute(a, n - 1)
    a[n], a[i] = a[i], a[n]
  end
end

for p in coroutine.wrap(function() permute({ "x", "y", "z" }, 3) end) do
  io.write(table.concat(p), " ")
end
print()
