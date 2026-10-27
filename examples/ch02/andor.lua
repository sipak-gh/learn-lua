-- and/or return one of their operands, not just true/false.
print(nil or "default")       -- or: the first operand if it is true, else the second
print("value" or "default")
print(nil and "x")            -- and: the first operand if it is false, else the second
print(1 and "x")

-- Idiom 1: a default value.
local name = arg[1] or "world"
print("hello " .. name)

-- Idiom 2: a choice, like C's  c ? x : y
local n = 7
print(n % 2 == 0 and "even" or "odd")

-- The gotcha: if x is false or nil, `c and x or y` gives y.
local flag = true
print(flag and false or "oops")   -- prints oops, not false

-- Short-circuit: the right side runs only when needed.
local t = nil
print(t and t.field)          -- no error: t.field is never evaluated
