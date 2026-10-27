-- The generic for calls an iterator function until it returns nil.
--   for k, v in explist do body end
-- evaluates explist once to get three values: f, s (state), ctl (control),
-- then loops:  k, v = f(s, ctl); if k == nil then break end; ctl = k; body

local t = { "a", "b", "c" }

print(ipairs(t))                             -- the triplet: function, table, 0

-- The same loop, written by hand.
local f, s, ctl = ipairs(t)
while true do
  local i, v = f(s, ctl)
  if i == nil then
    break
  end
  ctl = i
  print(i, v)
end
