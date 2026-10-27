-- Save a Lua table as Lua source, then load it back.

local function serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "string" then
    return ("%q"):format(v)               -- quoted and escaped so Lua can read it back
  elseif t == "number" then
    return ("%.17g"):format(v)            -- 17 digits: the exact same double comes back
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    local inner = indent .. "  "
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = { "{\n" }
    for _, k in ipairs(keys) do
      local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k
                  or "[" .. serialize(k) .. "]"
      out[#out + 1] = inner .. key .. " = " .. serialize(v[k], inner) .. ",\n"
    end
    out[#out + 1] = indent .. "}"
    return table.concat(out)
  end
  error("cannot serialize a " .. t)
end

local data = {
  name = "stash",
  version = 0.1,
  tags = { "lua", "jit" },
  ["odd key"] = 'say "hi"\n',
}

local f = assert(io.open("data.lua", "w"))
f:write("return ", serialize(data), "\n")
f:close()

for line in io.lines("data.lua") do print(line) end

-- loadfile compiles the file into a function without running it.
local chunk = assert(loadfile("data.lua"))
setfenv(chunk, {})                         -- an empty environment: no os, no io, no print
local copy = chunk()
print(copy.name, copy.version, copy.tags[2], copy["odd key"])

-- The empty environment stops a malicious data file from doing harm.
f = assert(io.open("data.lua", "w"))
f:write('return os.execute("echo pwned")\n')
f:close()
chunk = assert(loadfile("data.lua"))
setfenv(chunk, {})
print(pcall(chunk))

os.remove("data.lua")
