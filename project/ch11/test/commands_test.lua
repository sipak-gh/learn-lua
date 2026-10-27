local cli = require("stash.cli")
local commands = require("stash.commands")
local config = require("stash.config")
local MemoryStore = require("stash.memstore")

-- Runs a command against a store and returns its output as one string.
-- ctx.out collects lines in a table instead of printing them.
local function run(store, args)
  local lines = {}
  local ctx = {
    store = store,
    config = config.defaults,
    out = function(line) lines[#lines + 1] = line end,
  }
  local command = commands[args[1]]
  command.run(ctx, assert(cli.parse(args, 2, command.options)))
  return table.concat(lines, "\n")
end

local function sample_store()
  return MemoryStore.new({
    { url = "https://www.lua.org/", title = "Lua", tags = { "lua" } },
    { url = "https://luajit.org/", title = "LuaJIT", tags = { "lua", "jit" }, note = "fast" },
  })
end

test("list prints one aligned row per entry", function()
  eq(run(sample_store(), { "list" }), table.concat({
    "  1  Lua                                   lua",
    "  2  LuaJIT                                jit,lua",
  }, "\n"))
end)

test("add stores the entry", function()
  local store = sample_store()
  eq(run(store, { "add", "https://sqlite.org/", "-t", "DB" }), "added #3 sqlite.org")
  eq(store:get(3).tags[1], "db")
end)

test("show prints the fields", function()
  eq(run(sample_store(), { "show", "2" }), [[
id:    2
title: LuaJIT
url:   https://luajit.org/
tags:  jit, lua
note:  fast]])
end)

test("errors carry a kind", function()
  local err = raises(function() run(sample_store(), { "show", "7" }) end, "no entry with id 7")
  eq(err.kind, "not_found")
  err = raises(function() run(sample_store(), { "add", "lua.org" }) end, "does not look like a URL")
  eq(err.kind, "usage")
end)
