-- A malformed pattern is a runtime error.
print(("price: $5"):find("$5"))     -- fine: $ is only special at the end
print(("100%"):find("100%"))        -- error: % must be followed by something
