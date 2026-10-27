-- A small JSON encoder.
--
-- Lua has one structure, JSON has two: a table becomes a JSON array when
-- its keys are exactly 1..n, otherwise an object. An empty table is
-- written as [] (we cannot tell which one was meant).

local buffer = require("string.buffer")    -- LuaJIT's string builder

local M = {}

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

-- The other control characters (what %c matches: bytes 0-31 and 127)
-- become \u00XX. Filling the table once, up front, lets gsub look each
-- match up in it instead of calling a Lua function per match.
for byte = 0, 127 do
  local c = string.char(byte)
  if (byte < 32 or byte == 127) and not ESCAPES[c] then
    ESCAPES[c] = ("\\u%04x"):format(byte)
  end
end

local function encode_string(s, out)
  -- %c matches control characters. Bytes >= 128 (UTF-8) pass unchanged.
  -- Most strings need no escaping at all: then skip gsub and its copy.
  if s:find('[%c"\\]') then
    s = s:gsub('[%c"\\]', ESCAPES)
  end
  out:put('"', s, '"')
end

local function is_array(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then
      return false
    end
  end
  return true
end

local encode

local function encode_table(t, out)
  if is_array(t) then
    out:put("[")
    for i, v in ipairs(t) do
      if i > 1 then out:put(",") end
      encode(v, out)
    end
    out:put("]")
    return
  end
  -- Objects: keys sorted, so equal data always gives equal text.
  local keys = {}
  for k in pairs(t) do
    if type(k) ~= "string" then
      error("JSON object keys must be strings, got " .. type(k))
    end
    keys[#keys + 1] = k
  end
  table.sort(keys)
  out:put("{")
  for i, k in ipairs(keys) do
    if i > 1 then out:put(",") end
    encode_string(k, out)
    out:put(":")
    encode(t[k], out)
  end
  out:put("}")
end

function encode(value, out)
  local kind = type(value)
  if kind == "string" then
    encode_string(value, out)
  elseif kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("JSON cannot represent " .. tostring(value))
    end
    if value % 1 == 0 and math.abs(value) < 2^53 then
      out:put(("%d"):format(value))
    else
      out:put(("%.17g"):format(value))
    end
  elseif kind == "boolean" then
    out:put(tostring(value))
  elseif kind == "nil" then
    out:put("null")
  elseif kind == "table" then
    encode_table(value, out)
  else
    error("JSON cannot represent a " .. kind)
  end
end

-- One buffer, reused by every call: its memory is allocated once
-- instead of once per call.
local out = buffer.new()

function M.encode(value)
  out:reset()
  encode(value, out)
  return out:tostring()
end

-- Streams a JSON array, one element per line, pulling the elements from
-- an iterator and handing each finished line to emit(line). Nothing but
-- the current element is kept in memory. Returns the number of elements.
function M.write_array(it, emit)
  emit("[")
  local count = 0
  local pending                              -- held back: is it the last one?
  for value in it do
    if pending then
      emit("  " .. pending .. ",")
    end
    pending = M.encode(value)
    count = count + 1
  end
  if pending then
    emit("  " .. pending)
  end
  emit("]")
  return count
end

return M
