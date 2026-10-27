-- End-to-end tests: run the real program in a shell and check its output
-- and exit code.

local HOME = tmpdir("e2e")
local PAGES = "file://" .. os.getenv("PWD") .. "/test/fixtures"

-- Runs `stash ARGS` and returns its output (stdout and stderr) and exit code.
-- io.popen's close() does not report the exit code in LuaJIT, so the
-- shell prints it after the output.
local function stash(args)
  local command = ("STASH_HOME=%s STASH_NOW=1767225600 ./stash %s 2>&1; echo \"[exit $?]\"")
                  :format(HOME, args)
  local pipe = assert(io.popen(command))
  local output = pipe:read("*a")
  pipe:close()
  local text, code = output:match("^(.-)%[exit (%d+)%]\n$")
  return text, tonumber(code)
end

test("add, list, rm round trip", function()
  eq(stash("add " .. PAGES .. "/lua.html -t lua"), "added #1 The Programming Language Lua\n")
  eq(stash("add https://example.com/ -t web"), "added #2 example.com\n")
  eq(stash("list -t lua"),
     "  1  The Programming Language Lua          lua               2026-01-01\n")
  eq(stash("rm 1"), "removed #1 The Programming Language Lua\n")
  local text, code = stash("show 1")
  eq(text, "stash: no entry with id 1\n")
  eq(code, 1)
end)

test("usage errors exit with 2", function()
  local text, code = stash("list --limit")
  eq(code, 2)
  ok(text:find("usage: stash list", 1, true), text)
end)

test("a missing page is an error and nothing is saved", function()
  local _, code = stash("add file:///no/such/page.html")
  eq(code, 2)
  eq(select(2, stash("show 3")), 1)
end)
