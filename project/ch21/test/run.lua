-- A tiny test runner. Run it from the project root:
--
--   luajit test/run.lua          run every test file
--   luajit test/run.lua cli      run only files whose name contains "cli"
--
-- Each test file calls test(name, fn) and the assertions below; they are
-- handed to the file through its environment, so they need no require.
-- Tests that need files get a scratch directory from tmpdir(name).

package.path = "src/?.lua;" .. package.path
require("stash.strict")

-- Test files, in the order they run.
local FILES = {
  "util_test", "cli_test", "entry_test", "iter_test", "config_test",
  "commands_test", "json_test", "html_test", "fs_test", "term_test",
  "buffer_test", "db_test", "store_test", "fetch_test", "compress_test",
  "plugins_test", "e2e_test",
}

-- Scratch space. os.tmpname() would give us a file, not a directory, so
-- the runner keeps its own directory and deletes it at the end.
local TMP = ".test-tmp"
os.execute("rm -rf " .. TMP .. " && mkdir " .. TMP)


-- Formats a value for failure messages: strings are quoted.
local function show(v)
  if type(v) == "string" then
    return ("%q"):format(v)
  end
  return tostring(v)
end

-- Deep equality: tables are equal when they have equal keys and values.
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not same(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

-- A failed assertion raises a table, so the runner can tell it apart
-- from an unexpected error. debug.getinfo(3) describes the caller of the
-- assertion: the line in the test file.
local Failure = {}

local function fail(message)
  local info = debug.getinfo(3, "Sl")
  error(setmetatable({ text = ("%s:%d: %s"):format(info.short_src, info.currentline, message) },
                     Failure))
end

local assertions = {}

function assertions.eq(actual, expected)
  if actual ~= expected then
    fail(("expected %s, got %s"):format(show(expected), show(actual)))
  end
end

function assertions.same(actual, expected)
  if not same(actual, expected) then
    fail("tables differ")
  end
end

function assertions.ok(value, message)
  if not value then
    fail(message or "expected a true value")
  end
end

-- Calls fn and checks that it raises an error whose text contains `text`.
-- Returns the error value so the test can look at it further.
function assertions.raises(fn, text)
  local ok, err = pcall(fn)
  if ok then
    fail("expected an error")
  end
  if text and not tostring(err):find(text, 1, true) then
    fail(("error %s does not contain %s"):format(show(tostring(err)), show(text)))
  end
  return err
end

-- Returns a fresh, empty directory for one test.
function assertions.tmpdir(name)
  local path = TMP .. "/" .. name
  assert(os.execute("rm -rf " .. path .. " && mkdir " .. path) == 0)
  return path
end

local passed, failed = 0, 0

local function run_file(name)
  local tests = {}
  local env = setmetatable({
    test = function(title, fn)
      tests[#tests + 1] = { title = title, fn = fn }
    end,
  }, { __index = function(_, key) return assertions[key] or _G[key] end })

  local chunk = assert(loadfile("test/" .. name .. ".lua"))
  setfenv(chunk, env)
  chunk()                                    -- registers the tests

  local file_failed = 0
  for _, t in ipairs(tests) do
    -- Failed assertions report their line; anything else gets a traceback.
    local ok, err = xpcall(t.fn, function(e)
      if getmetatable(e) == Failure then
        return e.text
      end
      -- Not `return debug.traceback(...)`: that tail call would replace
      -- this handler's frame, and level 2 would skip the failing test.
      local trace = debug.traceback(tostring(e), 2)
      return trace
    end)
    if ok then
      passed = passed + 1
    else
      failed, file_failed = failed + 1, file_failed + 1
      print(("FAIL %s: %s\n  %s"):format(name, t.title, tostring(err)))
    end
  end
  print(("%-16s %d tests, %d failed"):format(name, #tests, file_failed))
end

local filter = arg[1]
for _, name in ipairs(FILES) do
  if filter == nil or name:find(filter, 1, true) then
    run_file(name)
  end
end
os.execute("rm -rf " .. TMP)
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
