-- The four quantifiers. They apply to ONE character class only.
local s = "<b>bold</b> and <b>more</b>"

print(s:match("<b>.*</b>"))   -- *  longest:  0 or more
print(s:match("<b>.-</b>"))   -- -  shortest: 0 or more
print(("aaa"):match("a+"))    -- +  1 or more, longest
print(("ab"):match("a?b"), ("b"):match("a?b")) -- ?  0 or 1
print(("key=   value"):match("=%s*(.*)"))
