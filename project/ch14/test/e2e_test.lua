-- End-to-end tests: run the real program in a shell and check its output
-- and exit code.

local HOME = tmpdir("e2e")
local PAGES = "file://" .. os.getenv("PWD") .. "/test/fixtures"

-- Runs `stash ARGS` (with extra environment variables `env`, like
-- "COLUMNS=100") and returns its output (stdout and stderr) and exit code.
-- io.popen's close() does not report the exit code in LuaJIT, so the
-- shell prints it after the output.
local function stash(args, env)
  local command = ("%s STASH_HOME=%s STASH_NOW=1767225600 ./stash %s 2>&1; echo \"[exit $?]\"")
                  :format(env or "", HOME, args)
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

test("color = \"always\" in the config paints the list", function()
  assert(require("stash.fs").write_atomic(HOME .. "/config.lua", 'color = "always"\n'))
  eq(stash("list"),
     "\27[33m  2\27[0m  example.com                           \27[36mweb             \27[0m  "
     .. "\27[2m2026-01-01\27[0m\n")
  os.remove(HOME .. "/config.lua")
end)

test("the title column follows COLUMNS", function()
  stash("add " .. PAGES .. "/luajit.html -t jit")
  eq(stash("list -t jit", "COLUMNS=60"),
     "  3  LuaJIT: a Just-In...  jit               2026-01-01\n")
  eq(stash("list -t jit", "COLUMNS=100"),
     "  3  LuaJIT: a Just-In-Time Compiler & FFI                     jit               2026-01-01\n")
end)
