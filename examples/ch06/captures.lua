-- Captures pull pieces out of a match.
local date = "2026-01-31"
local y, m, d = date:match("(%d+)-(%d+)-(%d+)")
print(y, m, d, type(y))                      -- captures are strings

print(("name = Ada"):match("^(%w+)%s*=%s*(%w+)$"))
print(("hello"):match("()ll()"))             -- () captures a position
print(("say 'hi' or \"bye\""):match("([\"'])(.-)%1")) -- %1 = same quote again

-- %b() matches balanced pairs: here, a parenthesized group with nesting.
print(("f(a, g(b, c)) + 1"):match("%b()"))

-- %f[set] is a frontier: the spot where the previous char is NOT in set
-- and the next char IS. %f[%w] is "start of a word".
print(("cat concat cat"):gsub("%f[%w]cat%f[%W]", "dog"))
