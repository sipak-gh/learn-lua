-- Code that prints is hard to test. Code that calls an `out` function
-- it was given is easy: the test passes one that collects the lines.
local function greet_all(names, out)
  for i, name in ipairs(names) do
    out(("%d. hello, %s"):format(i, name))
  end
end

greet_all({ "Ada", "Bob" }, print)            -- the program passes print

local lines = {}
greet_all({ "Ada", "Bob" }, function(line) lines[#lines + 1] = line end)
print(#lines, lines[2])                       -- the test inspects the output
print(table.concat(lines, "\n") == "1. hello, Ada\n2. hello, Bob")
