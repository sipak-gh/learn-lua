-- Multiple assignment: a list of names = a list of values.
local a, b, c = 1, 2
print(a, b, c)                -- missing values become nil

local x, y = 10, 20, 30       -- extra values are dropped
print(x, y)

-- All values on the right are evaluated BEFORE any assignment,
-- so swapping needs no temporary variable.
x, y = y, x
print(x, y)

local i = 1
i, a = i + 1, i               -- a gets the OLD i
print(i, a)
