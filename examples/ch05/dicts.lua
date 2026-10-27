-- A dictionary maps keys to values. Any value except nil (and NaN) can be a key.
local ages = { ada = 36, ["alan turing"] = 41 }
ages.grace = 85                      -- t.name is sugar for t["name"]
ages["linus"] = 28
print(ages.ada, ages["alan turing"], ages.grace)

-- t.x uses the literal NAME x. t[x] uses the VALUE of the variable x.
local key = "ada"
print(ages.key, ages[key])

-- Assigning nil removes a key. Reading a missing key gives nil.
ages.linus = nil
print(ages.linus)

-- Keys can be numbers, booleans, tables, functions...
local t = { [10] = "ten", [true] = "yes" }
t[print] = "the print function"
print(t[10], t[true], t[print])

-- Numbers are compared by value: 1 and 1.0 are the same key.
-- A string "1" is a different key from the number 1.
t[1] = "number one"
print(t[1.0], t["1"])

-- Test for emptiness with next(): it returns nil for an empty table.
print(next({}) == nil, next(t) ~= nil)
