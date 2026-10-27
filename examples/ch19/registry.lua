-- A tiny plugin host. Each plugin gets its own `app` table: closures
-- that know which plugin they belong to. That is the whole API.

local commands = {}                     -- name -> { plugin =, run = }
local hooks = { save = {} }             -- event -> list of handlers

-- Runs plugin code; any error is reported with the plugin's name.
local function guard(plugin, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    error(("plugin %s: %s"):format(plugin, tostring(err)), 0)
  end
end

local function api(plugin)
  local app = {}
  function app.command(name, run)
    if commands[name] then
      error(("command '%s' already exists"):format(name), 2)
    end
    commands[name] = { plugin = plugin, run = run }
  end
  function app.on(event, handler)
    local list = hooks[event] or error("unknown event " .. tostring(event), 2)
    list[#list + 1] = function(...) return guard(plugin, handler, ...) end
  end
  return app
end

local function load_plugin(name, code)
  local chunk = assert(load(code, "=" .. name, "t"))
  setfenv(chunk, { app = api(name), print = print, ipairs = ipairs })
  guard(name, chunk)
end

-- Two plugins, as text (they would normally be files).
load_plugin("hello", [[
  app.command("hello", function(who) print("hello, " .. (who or "world")) end)
]])
load_plugin("stamp", [[
  local count = 0                        -- private state of this plugin
  app.on("save", function(doc)
    count = count + 1
    doc.saved = count
  end)
]])

commands.hello.run("Lua")
local doc = {}
for _, handler in ipairs(hooks.save) do handler(doc) end
for _, handler in ipairs(hooks.save) do handler(doc) end
print("doc.saved =", doc.saved)

print(pcall(load_plugin, "dup", [[ app.command("hello", print) ]]))
print(pcall(load_plugin, "typo", [[ app.on("sav", print) ]]))
load_plugin("buggy", [[ app.on("save", function(doc) return doc.x.y end) ]])
print(pcall(hooks.save[2], doc))
