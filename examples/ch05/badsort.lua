-- A comparator must be a strict "less than": false for equal items.
-- Using <= breaks that rule. With repeated values, sort can fail.
local t = {}
for i = 1, 20 do t[i] = 5 end
table.sort(t, function(a, b) return a <= b end)
