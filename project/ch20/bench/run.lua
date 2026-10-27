-- Benchmarks for stash's hot paths. Run from the project directory:
--
--   luajit bench/run.lua            all benchmarks
--   luajit bench/run.lua export     the ones whose name contains "export"
--   luajit bench/run.lua -p export  ditto, and profile them (jit.p)
--
-- Timings depend on the machine; compare runs on the same one.

package.path = "src/?.lua;" .. package.path

local clock = require("stash.clock")
local cli = require("stash.cli")
local commands = require("stash.commands")
local config = require("stash.config")
local Entry = require("stash.entry")
local Store = require("stash.store")

local N = 20000

-- Runs fn `rounds` times and prints the fastest run: the slower ones
-- measure whatever else the machine was doing.
local function measure(name, rounds, fn)
  local best = math.huge
  for _ = 1, rounds do
    collectgarbage()
    local start = clock.now()
    fn()
    best = math.min(best, clock.now() - start)
  end
  print(("%-28s %8.1f ms"):format(name, best * 1000))
end

-- A store with N entries, each with two tags and some text.
local function big_store()
  local store = assert(Store.open(":memory:"))
  store.db:transaction(function()
    for i = 1, N do
      store:add(Entry.new({ url = ("https://example.com/page/%d"):format(i),
                            title = ("Page number %d about \"Lua\""):format(i),
                            tags = { "tag" .. i % 10, "bench" }, note = "note\t" .. i,
                            created = 1767225600 + i }),
                "some words for the search index " .. i)
    end
  end)
  return store
end

-- Runs a command with output going nowhere.
local function run_command(store, args)
  local command = commands[args[1]]
  local ctx = { store = store, config = config.defaults, out = function() end,
                paint = function(s) return s end, width = 80 }
  command.run(ctx, assert(cli.parse(args, 2, command.options)))
end

local BENCHMARKS = {
  { "insert " .. N .. " entries", 1, big_store },
  { "export " .. N .. " entries", 5, function(store) run_command(store, { "export" }) end },
  { "list " .. N .. " entries", 5, function(store) run_command(store, { "list", "--limit", "-1" }) end },
  { "search 'words'", 5, function(store) run_command(store, { "search", "words" }) end },
}

local profile, filter = false, nil
for _, a in ipairs(arg) do
  if a == "-p" then profile = true else filter = a end
end

-- `luajit -jp` would profile the whole run, setup included; jit.p lets
-- us profile just the benchmarks. "F" means: show module:function names.
local store = big_store()
if profile then require("jit.p").start("F") end
for _, b in ipairs(BENCHMARKS) do
  local name, rounds, fn = b[1], b[2], b[3]
  if filter == nil or name:find(filter, 1, true) then
    measure(name, rounds, function() fn(store) end)
  end
end
if profile then require("jit.p").stop() end
