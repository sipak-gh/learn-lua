-- A function can return several values.
local function divmod(a, b)
  return math.floor(a / b), a % b
end

local q, r = divmod(17, 5)
print(q, r)

-- A call at the END of a list keeps all its values...
print(divmod(17, 5))
print("x", divmod(17, 5))
local t = { divmod(17, 5) }
print(#t)

-- ...anywhere else it is cut to its first value.
print(divmod(17, 5), "x")
local u = { divmod(17, 5), "x" }
print(#u)

-- Parentheses cut a call to exactly one value.
print((divmod(17, 5)))

-- Ignore values you don't need with _ (just a normal name, by convention).
local _, rest = divmod(17, 5)
print(rest)

-- Many library functions return several values.
print(string.find("hello world", "wor"))
