local commands = require("stash.commands")
local Entry = require("stash.entry")
local Plugins = require("stash.plugins")
local Store = require("stash.store")

local DIR = tmpdir("plugins")

local function write(name, code)
  local file = assert(io.open(DIR .. "/" .. name .. ".lua", "w"))
  file:write(code)
  file:close()
end

-- A registry with the given plugins loaded, ready to run commands; the
-- sample plugins live in plugins/, test ones in DIR. Output collects in
-- `lines`.
local function setup(names, trusted)
  local store = assert(Store.open(":memory:"))
  local plugins = Plugins.new(commands)
  for _, name in ipairs(names) do
    local path = ("plugins/%s.lua"):format(name)
    local sample = io.open(path)
    if sample then
      sample:close()
    else
      path = ("%s/%s.lua"):format(DIR, name)
    end
    plugins:load(name, path, trusted or false)
  end
  local lines = {}
  plugins.ctx = { store = store, out = function(line) lines[#lines + 1] = line end,
                  paint = function(text) return text end, plugins = plugins }
  return plugins, store, lines
end

test("autotag adds tags from the URL, title and text", function()
  local plugins = setup({ "autotag" })
  local fields = { url = "https://github.com/LuaJIT/LuaJIT", title = "LuaJIT",
                   text = "a compiler for Lua", tags = { "jit" } }
  plugins:emit("add", fields)
  same(fields.tags, { "jit", "jit", "lua", "code" })        -- add cleans up duplicates
end)

test("wordcount adds a command that reads saved pages", function()
  local plugins, store, lines = setup({ "wordcount" })
  store:add(Entry.new({ url = "https://a.org/", title = "A" }), nil,
            "<title>A</title><p>the cat and the dog and the bird</p>")
  local words = plugins.commands.words
  eq(words.plugin, "wordcount")
  words.run(nil, { "1", top = 2 })
  same(lines, { "9 words in #1 A", "    3  the", "    2  and" })
end)

test("plugins see only safe globals, and copies of the libraries", function()
  write("peek", [[
    string.format = nil                      -- only the plugin's copy
    stash.command("peek", { run = function()
      stash.print(type(io), type(require), type(os.execute), type(os.time), type(stash.fail))
    end })
  ]])
  local plugins, _, lines = setup({ "peek" })
  plugins.commands.peek.run(nil, {})
  same(lines, { "nil\tnil\tnil\tfunction\tfunction" })
  eq(type(string.format), "function")
end)

test("trusted plugins may use require, and the FFI", function()
  raises(function() setup({ "checksum" }) end, "plugin checksum:")
  local plugins, store, lines = setup({ "checksum" }, true)
  store:add(Entry.new({ url = "https://a.org/" }), nil, "hello")
  plugins.commands.crc.run(nil, { "1" })
  same(lines, { "3610a686  #1" })
end)

test("errors in plugins name the plugin", function()
  write("broken", "stash.on('add', function(e) e.tags = e.tags + 1 end)")
  local plugins = setup({ "broken" })
  local err = raises(function() plugins:emit("add", { tags = {} }) end, "plugin broken:")
  eq(err.kind, "failed")
  raises(function() setup({ "missing" }) end, "plugin missing: cannot open")
  write("clash", "stash.command('list', { run = print })")
  raises(function() setup({ "clash" }) end, "command 'list' already exists")
  write("early", "stash.get(1)")
  raises(function() setup({ "early" }) end, "stash API used while loading")
end)

test("bytecode plugins are refused", function()
  local file = assert(io.open(DIR .. "/bytecode.lua", "wb"))
  file:write(string.dump(function() end))
  file:close()
  raises(function() setup({ "bytecode" }) end, "attempt to load chunk with wrong mode")
end)
