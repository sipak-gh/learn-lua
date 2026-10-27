-- Lua strings are bytes. UTF-8 text works, but # and sub count bytes.
local s = "naïve café"
print(#s)                          -- 12 bytes, 10 characters
print(s:upper())                   -- only ASCII letters change
print(s:sub(1, 3))                 -- cuts the ï in half

-- One UTF-8 character: a lead byte, then 0 or more continuation bytes.
local CHAR = "[%z\1-\127\194-\244][\128-\191]*"
local count = 0
for ch in s:gmatch(CHAR) do
  count = count + 1
end
print(count)                       -- 10

-- A UTF-8 aware length, from the same pattern.
local function ulen(str)
  return select(2, str:gsub(CHAR, ""))
end
print(ulen("€uro"), #"€uro")
