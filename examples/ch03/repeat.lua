-- repeat ... until checks the condition AFTER each pass,
-- so the body always runs at least once.
local n = 0
repeat
  n = n + 1
  local square = n * n
until square > 50              -- the body's locals are visible here
print(n, "is the first number whose square is over 50")

-- The body runs once even when the condition is already true.
repeat
  print("ran once")
until true
