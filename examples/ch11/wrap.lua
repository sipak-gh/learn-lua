-- coroutine.wrap returns a plain function. Each call resumes the
-- coroutine; it returns what yield passed, without the true/false flag.

local next_square = coroutine.wrap(function()
  for i = 1, 3 do
    coroutine.yield(i * i)
  end
end)

print(next_square())
print(next_square())
print(next_square())
print(next_square())                         -- the function returns: no values
print(pcall(next_square))                    -- dead now: calling it raises an error
