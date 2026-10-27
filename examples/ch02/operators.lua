-- Comparison returns a boolean. "Not equal" is ~=, not !=.
print(1 < 2, 1 <= 1, 2 > 3, 1 == 1.0, 1 ~= 2)

-- Values of different types are never equal...
print(1 == "1", nil == false)

-- ...and < between different types is an error (see below).
print("a" < "b", "Z" < "a", "10" < "9")  -- strings compare byte by byte

-- Precedence, highest first:
--   ^   then   not # - (unary)   then   * / %   then   + -
--   then ..   then  < > <= >= ~= ==   then  and   then  or
print(-2 ^ 2)                 -- -(2^2): ^ binds tighter than unary minus
print(2 ^ 3 ^ 2)              -- 2^(3^2): ^ and .. are right-associative
print(1 + 2 .. "")            -- (1+2) .. "": arithmetic before ..
print(not 1 == 2)             -- (not 1) == 2, so false == 2: false
