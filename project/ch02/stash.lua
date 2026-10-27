#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 2: a version constant and a first look at the arguments.

-- `local` keeps names private to this file. Upper case marks constants
-- (a convention only: Lua has no real constants).
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
  "  version       print the version"

-- arg[1] is nil when no argument was given; `or` supplies a default.
local command = arg[1] or "help"

-- No `if` yet (that is Chapter 3): `and`/`or` pick one of three messages.
-- Each `x and y` yields y only when x is true, so the first true test wins.
local message = (command == "help" and USAGE)
  or (command == "version" and "stash " .. VERSION)
  or "stash: unknown command '" .. command .. "' (try 'stash help')"

print(message)
