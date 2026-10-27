#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 3: walk over the arguments and decide what to do.

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

local command                 -- the first argument that is not a flag
local want_help = false
local want_version = false

-- Flags may appear anywhere, so look at every argument.
for i = 1, #arg do
  local a = arg[i]
  if a == "-h" or a == "--help" then
    want_help = true
    goto continue             -- Lua has no `continue`; a goto does the job
  end
  if a == "--version" then
    want_version = true
    goto continue
  end
  if command == nil then
    command = a
  end
  ::continue::
end

if want_help or command == "help" then
  print(USAGE)
elseif want_version or command == "version" then
  print("stash " .. VERSION)
elseif command == nil then
  print(USAGE)
elseif command == "add" or command == "list" or command == "search"
    or command == "show" or command == "rm" then
  print("stash: '" .. command .. "' is not implemented yet")
else
  print("stash: unknown command '" .. command .. "' (try 'stash help')")
end
