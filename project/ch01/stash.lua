#!/usr/bin/env luajit
-- stash: a scriptable bookmark and snippet keeper.
--
-- Chapter 1: the program only prints how to use it.
-- Run it with:  luajit stash.lua   (or ./stash.lua after chmod +x)

print("stash - a scriptable bookmark keeper")
print()
print("usage: stash <command> [arguments]")
print()
print("commands:")
print("  add URL       save a bookmark")
print("  list          list bookmarks")
print("  search TERM   search bookmarks")
print("  show ID       show one bookmark")
print("  rm ID         delete a bookmark")
print("  help          show this help")
