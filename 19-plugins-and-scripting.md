# Chapter 19 — Plugins and Scripting

This is the payoff of the course. Lua was built to be embedded in programs and scripted by their
users. You'll turn `stash` into a platform: users drop Lua files into `plugins/` to add commands
and change bookmarks as they are saved. You'll learn to run untrusted code in its own environment,
build a plugin API from closures, use hooks, and see where a Lua sandbox stops protecting you. One
plugin uses the FFI: power and danger in one file. [Chapter 18](18-performance-and-the-jit.md) made
`stash` fast; [Chapter 20](20-embedding-luajit.md) packs it into one binary.

## The app as a platform

Plugins let users add features you never planned, without touching your code. Lua fits the job:

- **It was built for it.** Lua started in 1993 as a configuration and scripting language for C
  programs. Embedding is its main job.
- **Code is data.** A plugin is a chunk you load and run, like `config.lua` in
  [Chapter 8](08-modules.md). No parser, no file format.
- **Environments.** You choose which globals a chunk sees: your API and a few safe functions.

A plugin system has three parts:

| Part | Lua mechanism |
|------|---------------|
| What a plugin can see | an environment table set with `setfenv` |
| What a plugin can do | an API table of closures |
| What happens when a plugin fails | `pcall` around every call into plugin code |

## Environments: where globals live

In Lua 5.1 and LuaJIT, every function has an **environment**: the table holding its globals.
Reading global `x` means `env.x`; `x = 1` means `env.x = 1`. Normally the environment is `_G`.
`setfenv(f, t)` swaps it for `t`; `getfenv(f)` returns it. [Chapter 8](08-modules.md) used this to
run `config.lua` against an empty table.

`examples/ch19/env.lua`

```lua
-- Every function has an environment: the table its globals live in.
-- setfenv swaps it, so the same code can run against a different world.

local code = [[
greeting = "hello from the plugin"      -- a global assignment...
function shout(s) return s:upper() end  -- ...and a global function
print(greeting)                          -- which print? the env's
]]

local chunk = assert(loadstring(code, "=plugin"))

local env = { print = function(...) print("[plugin]", ...) end }
setfenv(chunk, env)
chunk()

print(greeting)                         -- nil: our globals are untouched
print(env.greeting)                     -- the chunk's globals live in env
print(env.shout("quiet"))               -- functions it defines keep env
print(getfenv(env.shout) == env)

-- Without print in its environment, the chunk can't print at all.
local bare = setfenv(assert(loadstring("print('hi')", "=bare")), {})
print(pcall(bare))
```

```console
$ luajit examples/ch19/env.lua
[plugin]	hello from the plugin
nil
hello from the plugin
QUIET
true
false	bare:1: attempt to call global 'print' (a nil value)
```

What to notice:

- Functions defined in the chunk (`shout`) get the chunk's environment, so the whole plugin lives
  in its table.
- `setfenv` returns the function, so `setfenv(loadstring(...), {})` fits on one line.
- A chunk name starting with `=` is used as is in errors: `bare:1:`, not
  `[string "print('hi')"]:1:`.
- Locals are not globals. `local x` in the chunk never touches the environment.

> LuaJIT's `load` and `loadfile` also take the environment as their last argument, as in Lua 5.2:
> `load(code, "=plugin", "t", env)` equals `setfenv` on the result. Lua 5.2+ dropped `setfenv`, so
> the `load` form is portable. `stash` keeps `setfenv`, as in Chapter 8. See
> [Appendix C](appendix-c-lua-versions.md).

## Building a sandbox

A **sandbox** is an environment holding only what you choose to share. Build it from an
**allowlist** (name what is allowed), never a denylist (copy `_G`, delete the dangerous parts).
Forget an allowlist item and a plugin misses a feature. Forget a denylist item and you have a hole.

`examples/ch19/sandbox.lua`

```lua
-- A sandbox: an environment holding only what we choose to share.

local SAFE = { "assert", "error", "ipairs", "next", "pairs", "pcall",
               "select", "tonumber", "tostring", "type", "unpack" }

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function sandbox()
  local env = {}
  for _, name in ipairs(SAFE) do
    env[name] = _G[name]
  end
  -- Copies: a plugin that changes string.rep changes only its own copy.
  env.string, env.table, env.math = copy(string), copy(table), copy(math)
  env.os = { time = os.time, date = os.date, clock = os.clock }
  env.print = print
  return env
end

-- Loads source code as text only ("t") and runs it in a fresh sandbox,
-- plus the `extra` globals, if any.
local function run(name, code, extra)
  local chunk, err = load(code, "=" .. name, "t")
  if chunk == nil then
    return print(name, "refused:", err)
  end
  local env = sandbox()
  for k, v in pairs(extra or {}) do env[k] = v end
  setfenv(chunk, env)
  local ok, perr = pcall(chunk)
  print(name, ok and "ok" or perr)
end

run("peek", [[ print(type(io), type(require), type(os.execute), type(os.time)) ]])
run("io", [[ io.open("/etc/passwd") ]])
run("vandal", [[ string.rep = nil; print(type(string.rep)) ]])
print("host still has string.rep:", type(string.rep))
-- Method calls on strings use the real string library, not the copy:
run("method", [[ string.upper = nil; print(("abc"):upper()) ]])
-- Bytecode is refused: it is never verified, and bad bytecode can crash.
run("bytecode", string.dump(function() print("hi") end))

-- Two "harmless" functions that open the sandbox wide:
run("getfenv", [[ print(type(getfenv(0).io)) ]], { getfenv = getfenv })
run("getmetatable", [[ getmetatable("").__index.upper = function() return "pwned" end ]],
    { getmetatable = getmetatable })
print(("host"):upper())
```

```console
$ luajit examples/ch19/sandbox.lua
nil	nil	nil	function
peek	ok
io	io:1: attempt to index global 'io' (a nil value)
nil
vandal	ok
host still has string.rep:	function
ABC
method	ok
bytecode	refused:	attempt to load chunk with wrong mode
table
getfenv	ok
getmetatable	ok
pwned
```

Line by line:

- **Copies of libraries.** Tables are shared by reference ([Chapter 5](05-tables.md)). With the
  real `string` table, a plugin's `string.rep = nil` breaks the whole program. A shallow copy keeps
  the damage inside the plugin.
- **Method calls ignore the copy.** `("abc"):upper()` finds `upper` through the string metatable,
  whose `__index` is the real `string` table. Fine: the plugin can call those functions, not
  replace them.
- **`load(code, name, "t")`.** The mode: `"t"` text only, `"b"` bytecode only, `"bt"` both (the
  default). `loadfile(path, "t")` works the same; LuaJIT has both from Lua 5.2. Lua bytecode is not
  checked on load, and broken or hostile bytecode can crash the VM or worse. Never load it from
  anyone you don't trust.
- **`getfenv` is a hole.** `getfenv(0)` returns the running thread's globals: the real `_G`, with
  `io`, `os.execute` and the rest.
- **`getmetatable` is a hole.** `getmetatable("")` is the string metatable, shared by every string.
  Its `__index` is the real `string` table, so the plugin replaced `string.upper` for the host too.

What to leave out of a sandbox:

| Leave out | Because |
|-----------|---------|
| `io`, `os.execute`, `os.remove`, `os.exit`, … | files, programs, the process |
| `require`, `package` | loads any module, including `ffi` |
| `load`, `loadstring`, `loadfile`, `dofile` | load bytecode, or run code outside the sandbox |
| `getfenv`, `setfenv` | reach or change other functions' environments |
| `getmetatable` | the string metatable (shown above) |
| `rawget`, `rawset`, `rawequal` | bypass metatables the host relies on |
| `debug` | reads and writes locals, upvalues and metatables anywhere |
| `collectgarbage` | can stop the garbage collector |
| `string.dump` | turns functions into bytecode |
| `jit`, `ffi` | see below |

`stash` copies `string`, so plugins do get `string.dump`. Harmless: nothing in the sandbox can load
bytecode.

## A plugin API made of closures

The API is a table of functions, built **new for each plugin**. Its functions are closures
([Chapter 4](04-functions.md)) over the plugin's name and record, so the host knows who registered
a command without being told.

`examples/ch19/registry.lua`

```lua
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
```

```console
$ luajit examples/ch19/registry.lua
hello, Lua
doc.saved =	2
false	plugin dup: dup:1: command 'hello' already exists
false	plugin typo: typo:1: unknown event sav
false	plugin buggy: buggy:1: attempt to index field 'x' (a nil value)
```

The design ideas:

- **Hooks (events).** The host names moments ("save", "add") and calls every registered handler
  in load order. Handlers may change the table they get, so a plugin changes behavior without the
  host knowing what it does.
- **Error level 2.** `error(msg, 2)` blames the plugin line that called `app.command`, not the API
  ([Chapter 9](09-errors.md)).
- **A `pcall` boundary.** Every call into plugin code goes through `guard`. A plugin bug becomes an
  error naming the plugin, not a mystery crash.
- **Private state.** `count` is a local of the plugin chunk; the host never sees it.
- **Validate input** at once, while the plugin author can still see the wrong line.

## Declarative config and DSLs

Lua began as a language for describing data ([Chapter 5](05-tables.md)). Add a few functions to the
environment and a config file becomes a small domain-specific language (DSL). Two rules make it
read well: a call with one string or table argument needs no parentheses, and a function can
return a function.

`examples/ch19/dsl.lua`

```lua
-- A small DSL: rules for tagging bookmarks, written as Lua.
-- `tag "lua" { ... }` is two calls without parentheses:
-- tag("lua") returns a function, which gets the table.

local rules_text = [[
tag "lua" {
  words = { "lua", "luajit" },
  hosts = { "www.lua.org" },
}
tag "db" { words = { "sqlite", "sql" } }

-- Rules are code, so they can loop, call functions, and so on.
for _, host in ipairs({ "go.dev", "pkg.go.dev" }) do
  tag "code" { hosts = { host } }
end
]]

-- The DSL's vocabulary: the only globals the rules file sees.
local function load_rules(text)
  local rules = {}
  local env = { ipairs = ipairs }
  function env.tag(name)
    return function(spec)
      rules[#rules + 1] = { tag = name, words = spec.words or {}, hosts = spec.hosts or {} }
    end
  end
  local chunk = assert(load(text, "=rules", "t"))
  setfenv(chunk, env)
  chunk()
  return rules
end

local function tags_for(rules, url, title)
  local host = url:match("^%a+://([^/]+)")
  local text = title:lower()
  local tags = {}
  for _, rule in ipairs(rules) do
    for _, word in ipairs(rule.words) do
      if text:find("%f[%w]" .. word .. "%f[%W]") then tags[rule.tag] = true end
    end
    for _, h in ipairs(rule.hosts) do
      if h == host then tags[rule.tag] = true end
    end
  end
  local list = {}
  for tag in pairs(tags) do list[#list + 1] = tag end
  table.sort(list)
  return table.concat(list, ",")
end

local rules = load_rules(rules_text)
print(#rules .. " rules")
print(tags_for(rules, "https://www.lua.org/manual/", "Lua 5.1 Reference Manual"))
print(tags_for(rules, "https://sqlite.org/fts5.html", "SQLite FTS5 Extension"))
print(tags_for(rules, "https://go.dev/doc/", "Documentation"))
print(tags_for(rules, "https://example.com/", "Nothing here"))
```

```console
$ luajit examples/ch19/dsl.lua
4 rules
lua
db
code

```

The last line is empty: no rule matched. The rules file looks like data, but it is code:

- **Power:** loops, helper functions, computed values, comments. No config format offers that.
- **Risk:** it can loop forever or build a huge table. Load it in a sandbox, check its result
  ([Chapter 8](08-modules.md) checks every setting against a default), and treat it like any
  program.

`stash` uses the same trick: `command "add" { ... }` in `commands.lua` is a DSL.

## Hot reload

A plugin is just a chunk, so you can run a new version while the program runs. That's **hot
reload**, popular in games and editors: change a script, see the result without a restart.

`examples/ch19/reload.lua`

```lua
-- Hot reload: run a plugin file again to pick up its new code.
-- The new code replaces the old; state kept in the host survives.

local PATH = "reload_demo.lua"           -- written in the current directory

local function write(code)
  local file = assert(io.open(PATH, "w"))
  file:write(code)
  file:close()
end

local state = { greeted = 0 }            -- owned by the host, not the plugin
local plugin                             -- the plugin's exports

local function reload()
  local chunk, err = loadfile(PATH, "t")
  if chunk == nil then
    return print("reload failed, keeping the old code: " .. err)
  end
  setfenv(chunk, { state = state, tostring = tostring })
  plugin = chunk()
end

write([[ return { greet = function(name)
  state.greeted = state.greeted + 1
  return "hello, " .. name
end } ]])
reload()
print(plugin.greet("Ada"))

write([[ return { greet = function(name)
  state.greeted = state.greeted + 1
  return "HELLO, " .. name .. " (greeting #" .. tostring(state.greeted) .. ")"
end } ]])
reload()
print(plugin.greet("Ada"))

write([[ return { greet = function(name) oops ]])  -- a syntax error
reload()
print(plugin.greet("Grace"))

-- require caches modules in package.loaded. To reload a module,
-- forget the cached copy first.
write([[ return { version = 1 } ]])
print(require("reload_demo").version)
write([[ return { version = 2 } ]])
print(require("reload_demo").version)    -- the cached table
package.loaded["reload_demo"] = nil
print(require("reload_demo").version)    -- loaded again
os.remove(PATH)
```

```console
$ luajit examples/ch19/reload.lua
hello, Ada
HELLO, Ada (greeting #2)
reload failed, keeping the old code: reload_demo.lua:1: '=' expected near '<eof>'
HELLO, Grace (greeting #3)
1
1
2
```

Rules for safe reloading:

- **Keep state in the host.** The old chunk's locals die with it; `state.greeted` survived
  because the host owns it.
- **Load first, swap second.** If the new file has a syntax error, keep the old code.
- **Old closures stay old.** Anything holding a function from the old version (a hook list, a
  callback) keeps calling old code. Clear registrations before reloading.
- **When to reload** is up to you: a `reload` command, or a check of the file's change time
  (`stat` through the FFI, or Linux `inotify`).

`stash` runs once per command, so it reloads for free: every run loads the plugins again.

## Where a Lua sandbox stops

A sandbox stops accidents: a plugin can't delete your files by mistake or break the string library
for everyone. It doesn't stop a determined attacker. Two limits matter.

### Plugins can run forever

An environment can't stop `while true do end`, or a plugin that fills memory. The usual tool is a
**count hook**: `debug.sethook(fn, "", n)` calls `fn` every `n` VM instructions, and `fn` can raise
an error.

`examples/ch19/limits.lua`

```lua
-- A sandbox does not stop a plugin from running forever. A count hook
-- can interrupt it -- but only in the interpreter: LuaJIT's compiled
-- code does not check hooks.

local function run_limited(code, max)
  local chunk = assert(load(code, "=plugin", "t"))
  setfenv(chunk, {})
  jit.off(chunk, true)                   -- interpret it, and what it defines
  debug.sethook(function() error("instruction limit reached", 2) end, "", max)
  local ok, err = pcall(chunk)
  debug.sethook()                        -- remove the hook
  return ok, err
end

print(run_limited("local n = 0 for i = 1, 1000 do n = n + i end", 1e6))
print(run_limited("while true do end", 1e6))
```

```console
$ luajit examples/ch19/limits.lua
true	nil
false	plugin:1: instruction limit reached
```

Delete the `jit.off` line and the second call never returns (press Ctrl-C). The loop gets hot, the
JIT compiles it ([Chapter 18](18-performance-and-the-jit.md)), and compiled code doesn't check
hooks. A LuaJIT build option adds those checks, but it's off by default because it slows tight
loops. `jit.off(f, true)` stops compilation of `f` and every function defined inside it, so the
plugin runs in the interpreter: slower, but interruptible.

Memory has no such knob in LuaJIT's Lua API. Run hostile code in a separate process with OS limits.

### The FFI breaks every sandbox

The FFI gives Lua code the power of C: any function, any address. A plugin with `require` can load
`ffi`, and the sandbox is gone.

`examples/ch19/escape.lua`

```lua
-- Why a plugin with the FFI is not sandboxed at all.

local PASSWORD = "secret"                -- the host's own constant

local plugin = [[
local ffi = require("ffi")
ffi.cdef [=[ int getpid(void); ]=]
print("plugin sees pid", ffi.C.getpid() > 0)   -- any C function

-- Lua strings are immutable... unless you write to their memory.
local p = ffi.cast("uint8_t *", "secret")       -- same interned string
p[0] = string.byte("X")
]]

local env = { require = require, print = print, string = string }
local chunk = assert(load(plugin, "=evil", "t"))
setfenv(chunk, env)
chunk()

print(PASSWORD)                         -- the host's string changed
print(PASSWORD == "secret")
```

```console
$ luajit examples/ch19/escape.lua
plugin sees pid	true
Xecret
true
```

Strings are interned ([Chapter 2](02-values-and-types.md)): every `"secret"` in the program is one
object, and the plugin wrote into its memory. The host's constant now prints `Xecret` but still
equals `"secret"`, because equality compares objects, not bytes. The VM's own rules no longer hold.
The plugin could also call `system()`, read other memory, or crash the process.

The rule: **never give `require`, `ffi`, `jit`, `debug` or `package` to code you don't trust.**
Code that needs them is a program, not a plugin; install it only if you'd run it as a program.

## Building stash: plugins

`stash` gets a plugin system:

- `$STASH_HOME/plugins/NAME.lua` files, listed in `config.lua`:
  `plugins = { "autotag", "wordcount" }`.
- Each plugin runs in its own sandbox with a `stash` table: the plugin API.
- Plugins add commands (`stash.command`) and react to the `add` event (`stash.on`).
- Plugins named in `trusted_plugins` also get `require`, `io` and the full `os`. That's how a
  plugin gets the FFI, and why "trusted" means "runs like a program".
- A new `plugins` command lists what is loaded; `help` lists plugin commands.
- Three sample plugins in `plugins/`: `autotag`, `wordcount` and `checksum` (trusted; uses zlib
  through the FFI).

Start from your `project/ch18` code. Six files change and five are new.

### `src/stash/config.lua`: two new settings

Add both settings to the example in the header comment:

```lua
--   timeout = 30
--   plugins = { "autotag", "wordcount" }    -- from $STASH_HOME/plugins
--   trusted_plugins = { "checksum" }        -- loaded with full access
```

and to the defaults. A default's type is the type the setting must have, so both are tables:

```lua
M.defaults = {
  list_limit = 20,
  aliases = {},
  color = "auto",
  user_agent = "stash",                      -- sent with every download
  timeout = 10,                              -- seconds, per download
  plugins = {},                              -- names of the plugins to load
  trusted_plugins = {},                      -- plugins that may use require (and ffi)
}
```

### `src/stash/plugins.lua`: the registry (new)

The `registry.lua` example, grown up. It holds the loaded plugins, their commands and hooks:

- `Plugins.new(builtin)` makes a registry. `builtin` is the command table, so plugins can't
  replace `list` or `add`.
- `Plugins:api(plugin)` builds one plugin's `stash` table from closures.
- `environment(api, trusted)` builds the sandbox.
- `Plugins:load(name, path, trusted)` loads one file, text only, and runs it.
- `Plugins:emit(event, ...)` runs an event's hooks.

Two decisions:

- The data functions (`stash.get`, `stash.entries`, …) need the open store, which exists only
  after `main` parses the command. Until then `self.ctx` is `nil`; calling them while the plugin
  loads raises `stash API used while loading`.
- Entries reach plugins as plain records (`entry:record()`, [Chapter 12](12-io-and-os.md)), a fresh
  copy per call. A plugin can scribble on its copy but can't break `stash`'s `Entry` objects.

`src/stash/plugins.lua`

```lua
-- Plugins: Lua files in $STASH_HOME/plugins that add commands and react
-- to events. config.lua says which ones to load:
--
--   plugins = { "autotag", "wordcount", "checksum" }
--   trusted_plugins = { "checksum" }
--
-- A plugin is a chunk run in its own environment. All it can see is a
-- few safe globals and the `stash` table: the plugin API.
--
--   stash.command(name, { usage =, help =, options =, run = function(opts) })
--   stash.on("add", function(fields) ... end)   -- before an entry is saved
--   stash.entries()   stash.get(id)   stash.page(id)   stash.text(html)
--   stash.print(...)  stash.paint(text, style)
--   stash.fail(fmt, ...)   stash.not_found(fmt, ...)
--
-- Entries reach plugins as plain records (copies), never as our own
-- objects: whatever a plugin can reach, it can change.
--
-- The sandbox keeps honest plugins from breaking stash by accident; it
-- is not a security boundary. A plugin can still loop forever or eat all
-- memory. And a *trusted* plugin gets `require`, and with it the FFI:
-- with the FFI, Lua code can read and write any memory. No sandbox
-- survives that, so only trust plugins you would run as a program.

local errors = require("stash.errors")
local html = require("stash.html")

local Plugins = {}
Plugins.__index = Plugins

local EVENTS = { add = true }

-- Globals every plugin gets. string, table and math are copied, so a
-- plugin that replaces string.format replaces it only for itself.
local SAFE = { "assert", "error", "ipairs", "next", "pairs", "pcall", "select",
               "tonumber", "tostring", "type", "unpack", "xpcall" }
local LIBRARIES = { "string", "table", "math" }

local function copy(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = v
  end
  return c
end

-- builtin: the built-in commands, which plugins may not replace.
function Plugins.new(builtin)
  return setmetatable({
    builtin = builtin or {},
    loaded = {},                             -- { name =, trusted =, commands =, events = }
    commands = {},                           -- name -> command record, like stash.commands
    order = {},                              -- command names, in the order registered
    hooks = { add = {} },                    -- event -> list of functions
    ctx = nil,                               -- set by main once the store is open
  }, Plugins)
end

-- Calls fn(...) on behalf of a plugin. A stash error (stash.fail and
-- friends) passes through; any other error becomes a failure that names
-- the plugin, instead of an "internal error" of stash.
local function call(plugin, fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then
    return
  end
  if errors.is_error(err) then
    error(err, 0)
  end
  errors.fail("plugin %s: %s", plugin.name, tostring(err))
end

-- The `stash` table for one plugin. Its functions close over `self`
-- (the registry) and `plugin` (the record of the plugin being loaded).
function Plugins:api(plugin)
  local function ctx()
    return self.ctx or error("stash API used while loading", 3)
  end
  local api = { name = plugin.name }

  function api.command(name, def)
    if type(name) ~= "string" or type(def) ~= "table" or type(def.run) ~= "function" then
      error("usage: stash.command(name, { usage =, help =, run = function })", 2)
    end
    if self.builtin[name] or self.commands[name] then
      error(("command '%s' already exists"):format(name), 2)
    end
    self.commands[name] = {
      name = name,
      usage = def.usage or name,
      help = def.help or "",
      options = def.options or {},
      plugin = plugin.name,
      run = function(_, opts) call(plugin, def.run, opts) end,
    }
    self.order[#self.order + 1] = name
    plugin.commands[#plugin.commands + 1] = name
  end

  function api.on(event, fn)
    if not EVENTS[event] then
      error(("unknown event '%s'"):format(tostring(event)), 2)
    end
    table.insert(self.hooks[event], function(...) return call(plugin, fn, ...) end)
    plugin.events[#plugin.events + 1] = event
  end

  function api.get(id)
    local entry = ctx().store:get(id)
    return entry and entry:record()
  end

  function api.entries()
    local entries = ctx().store:entries()
    return function()
      local entry = entries()
      return entry and entry:record()
    end
  end

  function api.page(id)
    return ctx().store:page(id)
  end

  api.text = html.text

  function api.print(...)
    local parts = { ... }
    for i = 1, select("#", ...) do
      parts[i] = tostring(parts[i])
    end
    ctx().out(table.concat(parts, "\t"))
  end

  function api.paint(text, style)
    return ctx().paint(text, style)
  end

  api.fail = errors.fail
  api.not_found = errors.not_found
  return api
end

-- The global environment of one plugin.
local function environment(api, trusted)
  local env = {}
  for _, name in ipairs(SAFE) do
    env[name] = _G[name]
  end
  for _, name in ipairs(LIBRARIES) do
    env[name] = copy(_G[name])
  end
  env.os = { time = os.time, date = os.date, clock = os.clock }
  env.print = api.print
  env.stash = api
  if trusted then
    env.require, env.io, env.os = require, io, os
  end
  return env
end

-- Loads the plugin `name` from the file `path`.
function Plugins:load(name, path, trusted)
  -- Mode "t": text only. Lua bytecode is never verified, and broken
  -- bytecode can crash the VM -- or worse.
  local chunk, err = loadfile(path, "t")
  if chunk == nil then
    errors.fail("plugin %s: %s", name, err)
  end
  local plugin = { name = name, trusted = trusted, commands = {}, events = {} }
  setfenv(chunk, environment(self:api(plugin), trusted))
  call(plugin, chunk)
  self.loaded[#self.loaded + 1] = plugin
end

-- Runs the hooks for an event, in the order the plugins were loaded.
function Plugins:emit(event, ...)
  for _, hook in ipairs(self.hooks[event]) do
    hook(...)
  end
end

return Plugins
```

Notes on the code:

- **`call` keeps stash errors intact.** `stash.fail("missing ID")` raises a stash `Error` table
  ([Chapter 9](09-errors.md)); `call` re-raises it with `error(err, 0)`, so the user sees
  `stash: missing ID` and the right exit code. Any other error is a plugin bug: it becomes
  `stash: plugin NAME: ...`, exit 2, never an "internal error" of `stash`.
- **`ctx()` uses level 3.** Level 1 is `ctx`, level 2 the API function, level 3 the plugin line
  that called it.
- **The `run` wrapper** has a built-in command's shape, `run(ctx, opts)`, so `main` runs plugin
  commands like its own. The plugin's function gets only `opts`; it uses `stash`, not `ctx`.
- **`print` is `stash.print`**, so plugin output goes through `ctx.out` and tests can capture it.
- **Trusted plugins** get `require`, `io` and `os` too. Holding anything else back is pointless:
  with `require("ffi")` they can do anything.

### `src/stash/main.lua`: load plugins, find their commands

Require the module with the others:

```lua
local Plugins = require("stash.plugins")
local Store = require("stash.store")
```

Add `load_plugins` after `expand_alias`. It turns `trusted_plugins` into a set
([Chapter 5](05-tables.md)), then loads each plugin from `$STASH_HOME/plugins`:

```lua
-- Loads the plugins the settings ask for, from $STASH_HOME/plugins.
local function load_plugins(settings)
  local trusted = {}
  for _, name in ipairs(settings.trusted_plugins) do
    trusted[name] = true
  end
  local plugins = Plugins.new(commands)
  for _, name in ipairs(settings.plugins) do
    plugins:load(name, ("%s/plugins/%s.lua"):format(M.home(), name), trusted[name] or false)
  end
  return plugins
end
```

In `execute`, load the plugins right after the settings and before alias expansion (so an alias
can name a plugin command), look up plugin commands after built-in ones, and pass the registry in
`ctx`. The complete function:

```lua
local function execute(args, state)
  local settings, err = config.load(M.home() .. "/config.lua")
  if settings == nil then
    errors.fail("%s", err)
  end

  local plugins = load_plugins(settings)
  args = expand_alias(args, settings.aliases)
  local name = args[1]
  if name == nil or name == "-h" or name == "--help" then
    name = "help"
  elseif name == "--version" then
    name = "version"
  end

  local command = commands[name] or plugins.commands[name]
                  or errors.usage("unknown command '%s'", name)
  state.command = command
  local opts, perr = cli.parse(args, 2, command.options)
  if opts == nil then
    errors.usage("%s", perr)
  end

  local ok, merr = fs.mkdir_p(M.home())
  if not ok then
    errors.fail("cannot create %s", merr)
  end
  local store, serr = Store.open(M.home() .. "/stash.db")
  if store == nil then
    errors.fail("%s", serr)
  end
  local ctx = {
    store = store,
    config = settings,
    out = print,
    paint = term.painter(term.use_color(settings.color)),
    width = term.width(),
    plugins = plugins,
  }
  plugins.ctx = ctx                          -- the plugin API works from now on
  command.run(ctx, opts)
  store:close()
end
```

Plugin commands have `name`, `usage` and `options` like built-in ones, so `cli.parse` and its usage
errors work for them unchanged.

### `src/stash/commands.lua`: the `add` event, `plugins`, `help`

`ctx` has a new field; update the header comment:

```lua
-- The commands. Each one gets a context table `ctx` (the store, the
-- settings, an `out` function for output, a `paint` function for color,
-- the terminal `width` and the loaded `plugins`) plus the parsed options.
```

Tags now come from the user and from plugins, and need the same checks. Move the tag loop from
`add` into a function after `need_id`. It also drops duplicates, so a plugin can add a tag without
checking for it first. `tostring` guards against a plugin that adds a number:

```lua
-- Tags are lowercase words; duplicates are dropped.
local function clean_tags(list)
  local tags, seen = {}, {}
  for _, tag in ipairs(list) do
    tag = tostring(tag):lower()
    if not tag:find("^[%w_-]+$") then
      errors.usage("bad tag '%s' (use letters, digits, - and _)", tag)
    end
    if not seen[tag] then
      seen[tag] = true
      tags[#tags + 1] = tag
    end
  end
  return tags
end
```

`add` emits the `add` event after the download, before saving. Plugins get a plain `fields` table
they may change; `add` builds the `Entry` from it. The whole command:

```lua
command "add" {
  usage = "add URL [-t TAGS] [-n NOTE] [--no-fetch]",
  help = "save a bookmark",
  options = { ["-t"] = { "tags", "list" }, ["-n"] = { "note", "value" },
              ["--no-fetch"] = { "no_fetch", "flag" } },
  run = function(ctx, opts)
    local url = opts[1]
    if url == nil then
      errors.usage("missing URL")
    end
    if not url:find("^%a[%w+.-]*://") then
      errors.usage("'%s' does not look like a URL", url)
    end
    local tags = clean_tags(opts.tags or {})
    -- Download the page for its title and the search index.
    local title, text, page
    if not opts.no_fetch then
      local body, info = fetch.get(url, { user_agent = ctx.config.user_agent,
                                          timeout = ctx.config.timeout })
      if body == nil then
        errors.fail("cannot fetch %s: %s", url, info)
      end
      -- file:// URLs have no content type; trust them to be HTML.
      if info.content_type == nil or info.content_type:find("html") then
        title, text, page = html.title(body), html.text(body), body
      end
    end
    -- Plugins may change the title, note and tags before we save. They
    -- get a plain table: our Entry objects stay out of their reach.
    local fields = { url = url, title = title, note = opts.note or "", tags = tags, text = text }
    ctx.plugins:emit("add", fields)
    local entry = ctx.store:add(Entry.new({ url = url, title = fields.title, note = fields.note,
                                            tags = clean_tags(fields.tags), created = util.now() }),
                                text, page)
    ctx.out("added " .. tostring(entry))
  end,
}
```

`url` comes from the local, not `fields`: plugins can read the URL but not change it. The text and
page also stay as downloaded.

Add the `plugins` command before `help`, so `help` lists them in that order:

```lua
command "plugins" {
  usage = "plugins",
  help = "list the loaded plugins",
  run = function(ctx)
    local loaded = ctx.plugins.loaded
    for _, p in ipairs(loaded) do
      local provides = {}
      if #p.commands > 0 then
        provides[#provides + 1] = "commands: " .. table.concat(p.commands, ", ")
      end
      if #p.events > 0 then
        provides[#provides + 1] = "events: " .. table.concat(p.events, ", ")
      end
      ctx.out(("%-12s %s%s"):format(p.name, table.concat(provides, "; "),
                                    p.trusted and "  (trusted)" or ""))
    end
    if #loaded == 0 then
      ctx.out("no plugins loaded (see 'plugins' in config.lua)")
    end
  end,
}
```

Replace `help`. It measures plugin usage lines too, so both sections line up, and lists plugin
commands in their own section:

```lua
command "help" {
  usage = "help",
  help = "show this help",
  run = function(ctx)
    ctx.out("usage: stash <command> [arguments]")
    ctx.out("")
    ctx.out("commands:")
    local width = 0                          -- of the longest usage line
    for _, name in ipairs(order) do
      width = math.max(width, #commands[name].usage)
    end
    local plugins = ctx.plugins
    for _, name in ipairs(plugins.order) do
      width = math.max(width, #plugins.commands[name].usage)
    end
    local function show(c)
      ctx.out(("  %-" .. width .. "s  %s"):format(c.usage, c.help))
    end
    for _, name in ipairs(order) do
      show(commands[name])
    end
    if #plugins.order > 0 then
      ctx.out("")
      ctx.out("plugin commands:")
      for _, name in ipairs(plugins.order) do
        show(plugins.commands[name])
      end
    end
  end,
}
```

### `plugins/autotag.lua`: an event handler (new)

The sample plugins live in `plugins/` at the project root. To use them, copy them to
`$STASH_HOME/plugins/`.

`autotag` tags new bookmarks by content. Its rules are data: Lua patterns with frontiers
(`%f[%w]` = start of a word, [Chapter 6](06-strings.md)) and a table of hosts. It appends tags
freely; `add` lowercases, checks and dedupes them.

`plugins/autotag.lua`

```lua
-- autotag: tags new bookmarks by what they are about.
--
-- The rules are data. WORDS: a Lua pattern, matched against the
-- lowercased title and page text, and the tag it earns (%f[%w] and
-- %f[%W] are frontiers: the start and end of a word). HOSTS: tags for
-- the sites the URLs point to.

local WORDS = {
  { "%f[%w]luajit%f[%W]", "jit" },
  { "%f[%w]lua%f[%W]", "lua" },
  { "%f[%w]sqlite%f[%W]", "db" },
  { "%f[%w]sql%f[%W]", "db" },
}

local HOSTS = {
  ["github.com"] = "code",
  ["gitlab.com"] = "code",
  ["www.lua.org"] = "lua",
}

stash.on("add", function(entry)
  local text = ((entry.title or "") .. " " .. (entry.text or "")):lower()
  for _, rule in ipairs(WORDS) do
    local pattern, tag = rule[1], rule[2]
    if text:find(pattern) then
      entry.tags[#entry.tags + 1] = tag      -- stash drops duplicates
    end
  end
  local host = entry.url:match("^%a[%w+.-]*://([^/:]+)")
  if host and HOSTS[host:lower()] then
    entry.tags[#entry.tags + 1] = HOSTS[host:lower()]
  end
end)
```

It matches only the URL's host, not its path: `github.com/LuaJIT/LuaJIT` gets `code` but not
`jit`. With `--no-fetch` there is no title or text, hence the `or ""`.

### `plugins/wordcount.lua`: a new command (new)

`wordcount` adds `stash words`: words per bookmark, or the top words of one page. It uses only the
API and sandbox globals (`pairs`, `table.sort`, `math.min`, …). Its option spec has the same form
as a built-in command's ([Chapter 5](05-tables.md)).

`plugins/wordcount.lua`

```lua
-- wordcount: counts the words of saved pages.
--
--   stash words          words per bookmark
--   stash words ID       the most common words of one page

local function count_words(text)
  local counts, total = {}, 0
  for word in text:lower():gmatch("%a+") do
    counts[word] = (counts[word] or 0) + 1
    total = total + 1
  end
  return counts, total
end

-- The `top` most frequent words of at least 3 letters, ties in a-z order.
local function most_common(counts, top)
  local words = {}
  for word in pairs(counts) do
    if #word >= 3 then
      words[#words + 1] = word
    end
  end
  table.sort(words, function(a, b)
    if counts[a] ~= counts[b] then
      return counts[a] > counts[b]
    end
    return a < b
  end)
  local result = {}
  for i = 1, math.min(top, #words) do
    result[i] = words[i]
  end
  return result
end

stash.command("words", {
  usage = "words [ID] [--top N]",
  help = "count the words of saved pages",
  options = { ["--top"] = { "top", "number" } },
  run = function(opts)
    if opts[1] == nil then
      for entry in stash.entries() do
        local page = stash.page(entry.id)
        local _, total = count_words(page and stash.text(page) or "")
        stash.print(("%3d  %5d  %s"):format(entry.id, total, entry.title))
      end
      return
    end
    local id = tonumber(opts[1])
    local entry = id and stash.get(id) or stash.not_found("no entry with id %s", opts[1])
    local page = stash.page(id) or stash.not_found("no saved page for #%d", id)
    local counts, total = count_words(stash.text(page))
    stash.print(("%d words in #%d %s"):format(total, id, entry.title))
    for _, word in ipairs(most_common(counts, opts.top or 5)) do
      stash.print(("%5d  %s"):format(counts[word], stash.paint(word, "tag")))
    end
  end,
})
```

### `plugins/checksum.lua`: a trusted plugin with the FFI (new)

`checksum` adds `stash crc ID`, the CRC-32 of a saved page. It makes its own zlib binding, as in
[Chapter 17](17-binary-data-and-zlib.md). It needs `require`, so it loads only when trusted.

`plugins/checksum.lua`

```lua
-- checksum: CRC-32 of saved pages, computed by zlib through the FFI.
--
-- This plugin needs `require`, so it only works when trusted:
--
--   trusted_plugins = { "checksum" }
--
-- (stash itself already binds zlib; a plugin makes its own bindings.)

local ffi = require("ffi")

-- C declarations are global to the process. Declaring a function twice
-- is allowed (the first declaration wins); declaring a struct twice is
-- an error.
ffi.cdef [[
unsigned long crc32(unsigned long crc, const unsigned char *buf, unsigned int len);
]]
-- "z" means libz.so, which only the zlib development package installs;
-- libz.so.1 is the library itself.
local ok, zlib = pcall(ffi.load, "z")
if not ok then
  zlib = ffi.load("libz.so.1")
end

stash.command("crc", {
  usage = "crc ID",
  help = "CRC-32 of a saved page",
  run = function(opts)
    local id = tonumber(opts[1]) or stash.fail("missing or bad ID")
    local page = stash.page(id) or stash.not_found("no saved page for #%d", id)
    local crc = tonumber(zlib.crc32(0, page, #page))  -- unsigned long: cdata
    stash.print(("%08x  #%d"):format(crc, id))
  end,
})
```

This `ffi.cdef` and the one in `stash/ffi/zlib.lua` both declare `crc32`. C declarations are global
to the process, not to a module or sandbox. Declaring a function again is silently ignored;
declaring a struct again is an error. Plugins that declare structs must pick names that won't
clash.

### Tests

Add `plugins_test` to the list in `test/run.lua`, before `e2e_test`:

```lua
local FILES = {
  "util_test", "cli_test", "entry_test", "iter_test", "config_test",
  "commands_test", "json_test", "html_test", "fs_test", "term_test",
  "buffer_test", "db_test", "store_test", "fetch_test", "compress_test",
  "plugins_test", "e2e_test",
}
```

In `test/commands_test.lua`, `add` and `help` now use `ctx.plugins`, so the `run` helper needs a
registry. Require it at the top (`local Plugins = require("stash.plugins")`), then:

```lua
local function run(store, args)
  local lines = {}
  local plugins = Plugins.new(commands)      -- none loaded
  local ctx = {
    store = store,
    config = config.defaults,
    out = function(line) lines[#lines + 1] = line end,
    paint = function(text) return text end,
    width = 80,
    plugins = plugins,
  }
  plugins.ctx = ctx
  local command = commands[args[1]]
  command.run(ctx, assert(cli.parse(args, 2, command.options)))
  return table.concat(lines, "\n")
end
```

The `add` test now checks that duplicate tags are dropped:

```lua
test("add stores the entry", function()
  local store = sample_store()
  eq(run(store, { "add", "https://sqlite.org/", "-t", "DB,db", "--no-fetch" }), "added #3 sqlite.org")
  same(store:get(3).tags, { "db" })
end)
```

At the end of `test/e2e_test.lua`, add a test that installs the sample plugins into the test's
`STASH_HOME` and runs them through the real program:

```lua
test("plugins from $STASH_HOME/plugins add tags and commands", function()
  assert(os.execute("mkdir -p " .. HOME .. "/plugins && cp plugins/*.lua " .. HOME .. "/plugins/") == 0)
  assert(require("stash.fs").write_atomic(HOME .. "/config.lua",
                                          'plugins = { "autotag", "wordcount" }\n'))
  eq(stash("add " .. PAGES .. "/sqlite.html"), "added #4 SQLite FTS5 Extension\n")
  eq(stash("list -t db"),
     "  4  SQLite FTS5 Extension                 db                2026-01-01\n")
  eq(stash("words 4 --top 1"), "15 words in #4 SQLite FTS5 Extension\n    2  fts\n")
  ok(stash("help"):find("plugin commands:\n  words [ID] [--top N]", 1, true))
  os.remove(HOME .. "/config.lua")
end)
```

`test/plugins_test.lua` is new: copy it from `project/ch19/test/`. Its six tests load plugins
straight into a registry with an in-memory store, and cover:

- `autotag` adding tags from the URL, title and text;
- `wordcount`'s command reading a saved page;
- the sandbox: `io`, `require` and `os.execute` are `nil`, and changing `string.format` in a
  plugin leaves the real one alone;
- trusted plugins: `checksum` fails without trust, and with it computes `3610a686` for `"hello"`;
- errors: a broken hook, a missing file, a command that clashes with `list`, and an API call
  during loading all raise errors that name the plugin;
- a bytecode file is refused with `attempt to load chunk with wrong mode`.

### Checkpoint

Run the tests, then try the plugins in a scratch `STASH_HOME`. Set `PAGES` as in earlier
chapters:

```console
$ luajit test/run.lua
util_test        3 tests, 0 failed
cli_test         5 tests, 0 failed
entry_test       4 tests, 0 failed
iter_test        4 tests, 0 failed
config_test      4 tests, 0 failed
commands_test    6 tests, 0 failed
json_test        6 tests, 0 failed
html_test        5 tests, 0 failed
fs_test          3 tests, 0 failed
term_test        3 tests, 0 failed
buffer_test      3 tests, 0 failed
db_test          10 tests, 0 failed
store_test       11 tests, 0 failed
fetch_test       3 tests, 0 failed
compress_test    4 tests, 0 failed
plugins_test     6 tests, 0 failed
e2e_test         6 tests, 0 failed

86 passed, 0 failed
$ export STASH_HOME=demo STASH_NOW=1767225600
$ PAGES=file://$PWD/test/fixtures
$ mkdir -p demo/plugins && cp plugins/*.lua demo/plugins/
$ ./stash plugins
no plugins loaded (see 'plugins' in config.lua)
$ echo 'plugins = { "autotag", "wordcount", "checksum" }' > demo/config.lua
$ ./stash plugins
stash: plugin checksum: demo/plugins/checksum.lua:9: attempt to call global 'require' (a nil value)
$ echo $?
2
```

`checksum` isn't trusted yet, so `require` is `nil` in its sandbox. A plugin that fails to load
stops the whole run, even `plugins`: a clear error beats a half-working program. Trust it:

```console
$ echo 'trusted_plugins = { "checksum" }' >> demo/config.lua
$ cat demo/config.lua
plugins = { "autotag", "wordcount", "checksum" }
trusted_plugins = { "checksum" }
$ ./stash plugins
autotag      events: add
wordcount    commands: words
checksum     commands: crc  (trusted)
$ ./stash add $PAGES/lua.html
added #1 The Programming Language Lua
$ ./stash add $PAGES/luajit.html -t fast
added #2 LuaJIT: a Just-In-Time Compiler & FFI
$ ./stash add $PAGES/sqlite.html
added #3 SQLite FTS5 Extension
$ ./stash add https://github.com/LuaJIT/LuaJIT --no-fetch
added #4 github.com/LuaJIT/LuaJIT
$ ./stash list
  1  The Programming Language Lua          lua               2026-01-01
  2  LuaJIT: a Just-In-Time Compiler &...  fast,jit,lua      2026-01-01
  3  SQLite FTS5 Extension                 db                2026-01-01
  4  github.com/LuaJIT/LuaJIT              code              2026-01-01
```

Every tag except `fast` came from `autotag`. Now the plugin commands:

```console
$ ./stash words
  1     23  The Programming Language Lua
  2     33  LuaJIT: a Just-In-Time Compiler & FFI
  3     15  SQLite FTS5 Extension
  4      0  github.com/LuaJIT/LuaJIT
$ ./stash words 2 --top 3
33 words in #2 LuaJIT: a Just-In-Time Compiler & FFI
    2  code
    2  compiler
    2  ffi
$ ./stash words 4
stash: no saved page for #4
$ echo $?
1
$ ./stash crc 1
8d2a2f62  #1
$ ./stash help
usage: stash <command> [arguments]

commands:
  add URL [-t TAGS] [-n NOTE] [--no-fetch]  save a bookmark
  list [-t TAG] [-m PATTERN] [--limit N]    list bookmarks
  search WORDS...                           full-text search, best matches first
  show ID [--body]                          show one bookmark, or its saved page
  rm ID                                     delete a bookmark
  tags                                      count bookmarks per tag
  export [FILE]                             write all bookmarks as JSON
  stats                                     count entries and the space pages take
  plugins                                   list the loaded plugins
  help                                      show this help
  version                                   print the version

plugin commands:
  words [ID] [--top N]                      count the words of saved pages
  crc ID                                    CRC-32 of a saved page
```

`stash.not_found` in a plugin gives exit code 1, like built-in commands. Finally, a plugin that
tries to read a file:

```console
$ echo 'local f = io.open("/etc/passwd")' > demo/plugins/snoop.lua
$ echo 'plugins = { "snoop" }' > demo/config.lua
$ ./stash list
stash: plugin snoop: demo/plugins/snoop.lua:1: attempt to index global 'io' (a nil value)
$ echo $?
2
$ rm -r demo
```

The complete project at this point is in `project/ch19/`.

## Summary

- A plugin is a chunk run in its own **environment**. `setfenv(chunk, env)` decides every global
  it sees; functions it defines share that environment.
- Build sandboxes from an **allowlist**. Copy shared library tables. Leave out `io`, `require`,
  `load*`, `getfenv`/`setfenv`, `getmetatable`, `debug`, `collectgarbage`.
- Load untrusted code with mode `"t"`: Lua bytecode is not verified.
- Build the API as a **table of closures**, one per plugin, so the host knows which plugin calls.
- Wrap every call into plugin code in `pcall`. Name the plugin in errors; let your own error
  objects pass through.
- **Hooks** let plugins change data at named moments. Hand them plain copies; validate what comes
  back.
- Config files and DSLs are Lua code: powerful, and to be loaded as carefully as plugins.
- Hot reload is "load the file again". Keep state in the host; swap only after a good load.
- A sandbox stops accidents, not attacks. Plugins can loop forever (count hooks don't fire in
  JIT-compiled code). With `require`, a plugin has the FFI and can read or write any memory.
  Trusted plugins are programs.

## Exercises

1. Write a plugin `recent.lua` that adds `stash recent [N]`: the `N` (default 3) newest bookmarks,
   newest first, one per line as `#ID TITLE`. Use only the `stash` API and sandbox globals.

   <details><summary>Solution</summary>

   `stash.entries()` returns entries in id order, so collect them and walk the list backwards:

   ```lua
   -- recent: the newest bookmarks first.
   stash.command("recent", {
     usage = "recent [N]",
     help = "show the newest bookmarks",
     run = function(opts)
       local n = tonumber(opts[1] or 3) or stash.fail("bad count '%s'", opts[1])
       local all = {}
       for entry in stash.entries() do
         all[#all + 1] = entry
       end
       for i = #all, math.max(1, #all - n + 1), -1 do
         stash.print(("#%d %s"):format(all[i].id, all[i].title))
       end
     end,
   })
   ```

   With the four bookmarks of the checkpoint and `plugins = { "recent" }`:

   ```console
   $ ./stash recent 2
   #4 github.com/LuaJIT/LuaJIT
   #3 SQLite FTS5 Extension
   ```

   </details>

2. Add a second event, `rm`, that runs before a bookmark is deleted and gets its record. A handler
   may call `stash.fail(...)` to stop the deletion. Write a plugin `keep.lua` that refuses to
   delete bookmarks tagged `keep`.

   <details><summary>Solution</summary>

   In `plugins.lua`, allow the event and give it a hook list:

   ```lua
   local EVENTS = { add = true, rm = true }
   ```

   ```lua
       hooks = { add = {}, rm = {} },           -- event -> list of functions
   ```

   In `commands.lua`, emit it from `rm` before removing. The entry must exist first:

   ```lua
   command "rm" {
     usage = "rm ID",
     help = "delete a bookmark",
     run = function(ctx, opts)
       local id = need_id(opts)
       local found = ctx.store:get(id) or errors.not_found("no entry with id %d", id)
       ctx.plugins:emit("rm", found:record())
       local entry = ctx.store:remove(id) or errors.not_found("no entry with id %d", id)
       ctx.out("removed " .. tostring(entry))
     end,
   }
   ```

   `plugins/keep.lua`:

   ```lua
   stash.on("rm", function(entry)
     for _, tag in ipairs(entry.tags) do
       if tag == "keep" then
         stash.fail("#%d is tagged 'keep'", entry.id)
       end
     end
   end)
   ```

   ```console
   $ ./stash add https://example.com/ -t keep --no-fetch
   added #1 example.com
   $ ./stash rm 1
   stash: #1 is tagged 'keep'
   $ echo $?
   2
   ```

   `stash.fail` raises a stash error, which `call` passes through unchanged.

   </details>

3. A user asks: "Instead of `trusted_plugins`, can't you give every plugin a `require` that
   refuses `ffi` and only loads `stash.*` modules?" Explain why that is still not safe.

   <details><summary>Solution</summary>

   - Modules are shared tables, cached in `package.loaded`. `require("stash.json")` hands over the
     table `stash` uses, and `json.encode = evil` changes `export` for everyone.
   - Worse, `stash.ffi.sqlite`, `stash.ffi.zlib` and `stash.ffi.curl` **return FFI library
     namespaces** (what `ffi.load` returned): `require("stash.ffi.sqlite")` hands over every SQLite
     C function, `sqlite3_free` included. `stash.db` hands out raw cdata handles. Any module that
     requires `ffi` can leak it.
   - A safe allowlist would hold only modules you have checked, with copies for each plugin. That
     is just extending the `stash` API, which is the right design anyway.

   </details>

4. Untrusted plugins can still run forever. Change `call` in `plugins.lua` so that plugin code is
   stopped after 10 million VM instructions with the error `plugin NAME: too slow`. Test it with a
   plugin whose `add` hook is `while true do end`.

   <details><summary>Solution</summary>

   Two steps: interpret plugin code (hooks don't fire in compiled code), and put a count hook
   around each call. In `Plugins:load`, turn off the JIT for the plugin chunk and everything it
   defines:

   ```lua
     setfenv(chunk, environment(self:api(plugin), trusted))
     jit.off(chunk, true)                     -- count hooks only fire when interpreted
     call(plugin, chunk)
   ```

   and set the hook in `call`:

   ```lua
   local LIMIT = 1e7                          -- VM instructions per call

   local function call(plugin, fn, ...)
     debug.sethook(function() error("too slow", 0) end, "", LIMIT)
     local ok, err = pcall(fn, ...)
     debug.sethook()
     if ok then
       return
     end
     if errors.is_error(err) then
       error(err, 0)
     end
     errors.fail("plugin %s: %s", plugin.name, tostring(err))
   end
   ```

   ```console
   $ echo 'stash.on("add", function() while true do end end)' > demo/plugins/spin.lua
   $ echo 'plugins = { "spin" }' > demo/config.lua
   $ ./stash add https://example.com/ --no-fetch
   stash: plugin spin: too slow
   ```

   The limit is a rough budget: the hook also counts the `stash` code a plugin calls, except the
   parts the JIT has compiled. It's also easy to dodge. A plugin that catches the error and loops
   again never stops:

   ```lua
   stash.on("add", function() while true do pcall(function() while true do end end) end end)
   ```

   Closing that gap takes more machinery (for example, a hook that keeps failing until the
   plugin's coroutine is dead): one more reason the sandbox is not a security boundary. A trusted
   plugin can also just remove the hook: `require("debug").sethook()`.

   </details>

Sources for this chapter: [REFERENCES.md](REFERENCES.md#chapter-19--plugins-and-scripting)
