-- A test runner in 30 lines: register tests, run each one protected,
-- count, report, and set the exit code.
local tests = {}

local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function eq(actual, expected)
  if actual ~= expected then
    -- level 2: blame the line in the test that called eq
    error(("expected %q, got %q"):format(tostring(expected), tostring(actual)), 2)
  end
end

local function slug(s)
  return (s:lower():gsub("%W+", "-"))
end

test("lowercases", function() eq(slug("Hello"), "hello") end)
test("joins words", function() eq(slug("Hello, World"), "hello-world") end)
test("trims", function() eq(slug("  trim me  "), "trim-me") end)
test("empty string", function() eq(slug(""), "") end)

local failed = 0
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if not ok then
    failed = failed + 1
    print("FAIL " .. t.name .. ": " .. err)
  end
end
print(("%d passed, %d failed"):format(#tests - failed, failed))
os.exit(failed == 0)                 -- true -> 0, false -> 1
