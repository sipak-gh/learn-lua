-- string.find returns where a match starts and ends, or nil.
local s = "one.two.three"

print(s:find("two"))         -- 5  7
print(s:find("four"))        -- nil
print(s:find("t", 6))        -- start looking at position 6
print(s:find(".", 1, true))  -- plain: "." is just a dot
print(s:find("."))           -- pattern: "." means any character
print(s:find("(%a+)%.(%a+)")) -- captures come after the positions
if s:find("three", 1, true) then
  print("contains three")
end
