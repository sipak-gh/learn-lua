#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 4: every command is a function.

local VERSION = "0.1.0"

local USAGE = "usage: stash <command> [arguments]\n" ..
  "\n" ..
  "commands:\n" ..
  "  add URL       save a bookmark\n" ..
  "  list          list bookmarks\n" ..
  "  search TERM   search bookmarks\n" ..
  "  show ID       show one bookmark\n" ..
  "  rm ID         delete a bookmark\n" ..
  "  help          show this help\n" ..
  "  version       print the version\n" ..
  "\n" ..
  "options:\n" ..
  "  -h, --help    show this help\n" ..
  "  --version     print the version"

-- Print an error message built from any number of parts.
local function fail(...)
  local message = "stash:"
  for i = 1, select("#", ...) do
    -- select(i, ...) returns ALL values from i on; the parentheses keep one.
    message = message .. " " .. tostring((select(i, ...)))
  end
  print(message)
end

-- A closure: each call of the returned function bumps the captured `n`.
local function counter(start)
  local n = start - 1
  return function()
    n = n + 1
    return n
  end
end

local next_id = counter(1)

-- A higher-order helper: builds a handler for a command we have not written yet.
local function not_yet(name)
  return function()
    fail("'" .. name .. "' is not implemented yet")
  end
end

local function cmd_help()
  print(USAGE)
end

local function cmd_version()
  print("stash " .. VERSION)
end

local function cmd_add(url, ...)
  if url == nil then
    return fail("add: missing URL")
  end
  -- Nothing is stored yet (tables arrive in Chapter 5).
  print("added " .. next_id() .. ": " .. url .. " (" .. select("#", ...) .. " extra arguments)")
end

local function cmd_show(id)
  if tonumber(id) == nil then
    return fail("show: ID must be a number, got", id)
  end
  fail("'show' is not implemented yet")
end

local cmd_list = not_yet("list")
local cmd_search = not_yet("search")
local cmd_rm = not_yet("rm")

-- Scan the arguments. Returns four values: the command, its position,
-- and whether -h/--help or --version appeared anywhere.
local function scan(...)
  local command, position
  local want_help, want_version = false, false
  for i = 1, select("#", ...) do
    local a = select(i, ...)
    if a == "-h" or a == "--help" then
      want_help = true
    elseif a == "--version" then
      want_version = true
    elseif command == nil then
      command, position = a, i
    end
  end
  return command, position, want_help, want_version
end

local function run(...)
  local command, position, want_help, want_version = scan(...)
  if want_help or command == "help" then
    return cmd_help()
  elseif want_version or command == "version" then
    return cmd_version()
  elseif command == nil then
    return cmd_help()
  end

  -- The arguments after the command go to its handler. `return f(...)`
  -- is a proper tail call: run's stack frame is reused.
  if command == "add" then
    return cmd_add(select(position + 1, ...))
  elseif command == "list" then
    return cmd_list(select(position + 1, ...))
  elseif command == "search" then
    return cmd_search(select(position + 1, ...))
  elseif command == "show" then
    return cmd_show(select(position + 1, ...))
  elseif command == "rm" then
    return cmd_rm(select(position + 1, ...))
  end
  return fail("unknown command '" .. command .. "' (try 'stash help')")
end

-- The main chunk receives the command-line arguments as `...` too.
run(...)
