local a = "double quotes"
local b = 'single quotes'
local c = [[a long string:
it can span lines and has no escapes: \n stays \n]]
print(a, b)
print(c)

-- Escapes in quoted strings.
print("tab:\t|  newline:\n|  quote:\"  backslash:\\")
print("\65\066\x43")          -- decimal \ddd and hex \xXX byte escapes

-- # gives the length in bytes. Strings may contain any byte, even zero.
print(#"hello", #"", #"a\0b")
print(#"héllo")               -- é is two bytes in UTF-8

-- .. joins strings. Numbers are converted to text automatically.
local name = "Lua"
print("Hello, " .. name .. " " .. 5.1)

-- Strings are immutable: "changing" one makes a new string.
local s = "hello"
local t = s:upper()           -- method call syntax (Chapter 6)
print(s, t)
