-- One number type: a 64-bit floating-point value (a C double).
print(7 + 2, 7 - 2, 7 * 2)    -- whole results print without ".0"
print(7 / 2)                  -- / always divides exactly
print(math.floor(7 / 2))      -- integer division: floor of the quotient
print(7 % 3, -7 % 3)          -- % takes the sign of the divisor
print(2 ^ 10, 2 ^ 0.5)        -- ^ is exponentiation (always a float)
print(0xff, 1e3, 2.5e-3)      -- hex and scientific notation

-- Every integer up to 2^53 is exact. Beyond that, gaps appear.
print(2 ^ 53, 2 ^ 53 + 1 == 2 ^ 53)

-- Floats are binary fractions, so decimal fractions are approximations.
print(0.1 + 0.2 == 0.3, string.format("%.17g", 0.1 + 0.2))

-- Division by zero is not an error.
print(1 / 0, -1 / 0, 0 / 0)
print(math.huge, math.pi, math.max(3, 9, 4), math.abs(-2))
