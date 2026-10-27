-- The string library, called as functions and as methods.
local s = "Hello, Lua"

print(#s, string.len(s))          -- length in bytes
print(string.upper(s), s:lower()) -- s:lower() is string.lower(s)
print(s:sub(1, 5))                -- characters 1 to 5 (inclusive)
print(s:sub(-3))                  -- negative = count from the end
print(s:sub(8, 100), s:sub(5, 2) == "") -- out of range is clamped
print(("ab"):rep(3), ("ab"):rep(3, "-"))
print(s:reverse())
print(s:byte(1), s:byte(-1), s:byte(1, 3)) -- byte codes
print(string.char(76, 117, 97))           -- and back
print(("%d items"):format(3))             -- literal: needs parentheses
print(s, "unchanged")                     -- strings never change in place
