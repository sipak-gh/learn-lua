-- break leaves the innermost loop at once.
local words = { "alpha", "beta", "", "delta" }
local first_empty
for i, w in ipairs(words) do
  if w == "" then
    first_empty = i
    break
  end
end
print("first empty word at", first_empty)

-- `return` also ends a function or a whole chunk early.
-- Like break, it must be the last statement in its block,
-- so to stop in the middle of a block, wrap it: do return end
print("before")
do return end
print("after")                 -- never runs
