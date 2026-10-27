-- for var = start, stop [, step] do ... end   (stop is inclusive)
-- io.write prints its arguments with no tabs and no newline (Chapter 12).
for i = 1, 3 do io.write(i, " ") end print()
for i = 10, 1, -3 do io.write(i, " ") end print()
for i = 1, 0 do print("never runs") end

-- start, stop and step are evaluated once, before the loop starts.
local n = 3
for i = 1, n do n = 10; io.write(i, " ") end print()

-- The loop variable is a new local, gone after the loop.
for i = 1, 2 do end
print(i)                       -- nil: this is the global `i`

-- Float steps accumulate rounding errors. 0.3 is never reached:
for x = 0, 0.3, 0.1 do io.write(x, " ") end print()

-- Loop over integers and compute the float instead.
for k = 0, 3 do io.write(k / 10, " ") end print()
