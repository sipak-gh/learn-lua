-- A stateless iterator keeps no state of its own: everything it needs
-- comes in as (s, ctl). ipairs and pairs work this way.

-- Counts from ctl+1 up to s, stepping by 1.
local function upto_step(limit, i)
  i = i + 1
  if i <= limit then
    return i
  end
end

local function upto(limit)
  return upto_step, limit, 0
end

for i in upto(3) do
  io.write(i, " ")
end
print()

-- Every second element of an array: the control variable is the index.
local function every_other_step(t, i)
  i = i + 2
  if t[i] ~= nil then
    return i, t[i]
  end
end

local function every_other(t)
  return every_other_step, t, -1             -- the first index is -1 + 2 = 1
end

for i, v in every_other({ "a", "b", "c", "d", "e" }) do
  io.write(i, "=", v, " ")
end
print()
