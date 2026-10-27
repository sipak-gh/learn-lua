-- Testing with plain assert: it works, but it stops at the first failure
-- and says nothing about the values.
local function slug(s)
  return (s:lower():gsub("%W+", "-"))
end

assert(slug("Hello") == "hello")
assert(slug("Hello, World") == "hello-world")
assert(slug("  trim me  ") == "trim-me")
print("all passed")              -- never reached
