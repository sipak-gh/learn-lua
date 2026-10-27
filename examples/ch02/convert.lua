-- tostring turns any value into a string.
print(tostring(42), tostring(1.5), tostring(nil), tostring(true))

-- tonumber turns a string into a number, or returns nil.
print(tonumber("42"), tonumber("  3.5  "), tonumber("0x10"), tonumber("1e2"))
print(tonumber("12abc"), tonumber(""), tonumber("abc"))
print(tonumber("ff", 16), tonumber("777", 8), tonumber("101", 2))

-- Arithmetic converts strings to numbers; .. converts numbers to strings.
print("10" + 1, "3" * "4", 10 .. 20)

-- But == never converts: a string is not equal to a number.
print("10" == 10, tonumber("10") == 10)
