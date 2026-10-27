-- Escape sequences and long strings.
print("tab:\t|  quote:\"  backslash:\\  newline:\nnext line")
print("decimal \65\066\067 and hex \x41\x42\x43")  -- \ddd is DECIMAL
print("unicode \u{20AC} is " .. #"\u{20AC}" .. " bytes")
print("one \z
       line")                     -- \z skips the line break and spaces
print([[
Long string: the first newline is dropped.
No escapes here: \n stays as typed.]])
print([==[It may contain ]] safely.]==])
local embedded = "a\0b"
print(#embedded)                  -- strings may hold any byte, even zero
