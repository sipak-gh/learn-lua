-- `local function` makes the name visible inside the body, so it can recurse.
local function factorial(n)
  if n <= 1 then
    return 1
  end
  return n * factorial(n - 1)
end
print(factorial(5), factorial(20))

-- Mutual recursion: declare the second name first.
local is_odd
local function is_even(n)
  if n == 0 then return true end
  return is_odd(n - 1)
end
function is_odd(n)             -- assigns the local declared above
  if n == 0 then return false end
  return is_even(n - 1)
end
print(is_even(10), is_odd(7))

-- The trap: with `local f = function`, f is not in scope inside its own body.
local fib = function(n)
  if n < 2 then return n end
  return fib(n - 1) + fib(n - 2) -- this `fib` is the GLOBAL fib: nil
end
print(fib(5))
