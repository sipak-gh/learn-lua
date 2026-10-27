-- Variables hold REFERENCES to tables. Assignment doesn't copy.
local a = { 1, 2, 3 }
local b = a
b[1] = 100
print(a[1], a == b)

-- Two tables with the same contents are still different tables.
print({ 1 } == { 1 })

-- Functions receive references too, so they can change the caller's table.
local function clear_first(t) t[1] = nil end
clear_first(a)
print(a[1])

-- A shallow copy copies the top level only.
local function shallow_copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- A deep copy copies nested tables too. `seen` handles shared and cyclic tables.
local function deep_copy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local out = {}
  seen[t] = out
  for k, v in pairs(t) do
    out[deep_copy(k, seen)] = deep_copy(v, seen)
  end
  return out
end

local original = { name = "x", tags = { "a", "b" } }
original.self = original         -- a cycle
local s = shallow_copy(original)
local d = deep_copy(original)
original.tags[1] = "CHANGED"
print(s.tags[1], d.tags[1])      -- the shallow copy shares `tags`
print(d.self == d, d.self == original)
