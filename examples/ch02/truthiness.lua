-- Only nil and false are false. Everything else is true,
-- including 0, the empty string and the empty table.
print(not nil, not false, not 0, not "", not "false", not {})

if 0 then print("0 is true") end
if "" then print("the empty string is true") end
if nil then print("never printed") end

-- Use == and ~= to test for a specific value.
local n = 0
print(n == 0, n ~= 0)
