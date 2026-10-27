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
