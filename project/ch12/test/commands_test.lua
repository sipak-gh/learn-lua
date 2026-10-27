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

local NOW = 1767225600                       -- 2026-01-01 00:00 UTC

local function sample_store()
  return MemoryStore.new({
    { url = "https://www.lua.org/", title = "Lua", tags = { "lua" }, created = NOW },
    { url = "https://luajit.org/", title = "LuaJIT", tags = { "lua", "jit" }, note = "fast",
      created = NOW },
  })
end

test("list prints one aligned row per entry", function()
  eq(run(sample_store(), { "list" }), table.concat({
    "  1  Lua                                   lua               2026-01-01",
    "  2  LuaJIT                                jit,lua           2026-01-01",
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
added: 2026-01-01 00:00 UTC
note:  fast]])
end)

test("errors carry a kind", function()
  local err = raises(function() run(sample_store(), { "show", "7" }) end, "no entry with id 7")
  eq(err.kind, "not_found")
  err = raises(function() run(sample_store(), { "add", "lua.org" }) end, "does not look like a URL")
  eq(err.kind, "usage")
end)

test("export writes a JSON array", function()
  eq(run(sample_store(), { "export" }), table.concat({
    "[",
    [[  {"created":1767225600,"id":1,"note":"","tags":["lua"],"title":"Lua","url":"https://www.lua.org/"},]],
    [[  {"created":1767225600,"id":2,"note":"fast","tags":["jit","lua"],"title":"LuaJIT","url":"https://luajit.org/"}]],
    "]",
  }, "\n"))
end)
