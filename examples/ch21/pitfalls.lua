-- The mistakes Lua programmers make most, each in a few lines.

-- 1. Only nil and false are false. 0 and "" are true.
local count = 0
if count then print("1. 0 is true") end

-- 2. # on a table with holes: any border is a valid answer.
local t = { 1, 2, nil, 4 }
print("2. #t =", #t, "(could be 2 or 4)")

-- 3. a and b or c is not a ternary when b can be false or nil.
local enabled = false
local setting = true and enabled or "default"
print("3. setting =", setting)

-- 4. Forgetting local makes a global.
local function count_words(s)
  n = 0                           -- oops: global n
  for _ in s:gmatch("%S+") do n = n + 1 end
  return n
end
count_words("a b c")
print("4. global n =", n)

-- 5. Indexes start at 1; t[0] is just another key.
local list = { "a", "b" }
list[0] = "zero"
print("5. #list =", #list, "unpack sees:", select("#", unpack(list)))

-- 6. String functions count bytes, not characters.
local word = "naïve"
print("6. #word =", #word, ("%-7s|"):format(word))

-- 7. . vs : calls.
local obj = { name = "obj" }
function obj:hello() return "hello from " .. tostring(self and self.name) end
print("7.", obj:hello(), pcall(obj.hello))

-- 8. A NULL pointer is cdata, not nil, and it is truthy.
local ffi = require("ffi")
local p = ffi.cast("void *", 0)
print("8. p == nil:", p == nil, "type:", type(p), "truthy:", not not p)

-- 9. 64-bit integers from C are cdata: 1LL ~= 1 as a table key.
local big = ffi.new("int64_t", 1)
local keys = { [1] = "number key" }
print("9.", big == 1, keys[big], tonumber(big) == 1, keys[tonumber(big)])

-- 10. Strings are immutable: gsub and friends return a new string.
local s = "hello"
s:upper()
print("10.", s, s:upper())
