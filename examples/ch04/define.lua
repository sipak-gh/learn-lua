-- A function definition is an assignment of a function value.
local function add(a, b)       -- same as: local add; add = function(a, b) ... end
  return a + b
end

local square = function(x)     -- an anonymous function stored in a local
  return x * x
end

print(add(2, 3), square(4))

-- Functions are values: store them, pass them, compare them.
local op = add
print(op(10, 20), op == add, type(op))

-- Extra arguments are dropped; missing ones are nil.
print(add(1, 2, 3))
print(pcall(add, 1))           -- pcall catches the error (Chapter 9)

-- Default values with `or`.
local function greet(name, greeting)
  greeting = greeting or "Hello"
  return greeting .. ", " .. (name or "world") .. "!"
end
print(greet())
print(greet("Ada", "Hi"))

-- A function with no return statement returns nothing (nil when you ask).
local function nothing() end
print(nothing())               -- an empty line: no values at all
print((nothing()))             -- parentheses force exactly one value: nil
