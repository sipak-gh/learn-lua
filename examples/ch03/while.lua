-- while checks the condition BEFORE each pass.
-- The Collatz sequence: halve even numbers, map odd n to 3n + 1.
local n = tonumber(arg[1]) or 6
local steps = 0
while n ~= 1 do
  if n % 2 == 0 then
    n = n / 2
  else
    n = 3 * n + 1
  end
  steps = steps + 1
end
print("reached 1 after " .. steps .. " steps")
