-- A small JSON encoder.
--
-- Lua has one structure, JSON has two: a table becomes a JSON array when
-- its keys are exactly 1..n, otherwise an object. An empty table is
-- written as [] (we cannot tell which one was meant).

local M = {}

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function escape_char(c)
  return ESCAPES[c] or ("\\u%04x"):format(c:byte())
end

local function encode_string(s)
  -- %c matches control characters. Bytes >= 128 (UTF-8) pass unchanged.
  return '"' .. s:gsub('[%c"\\]', escape_char) .. '"'
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
    out[#out + 1] = "["
    for i, v in ipairs(t) do
      if i > 1 then out[#out + 1] = "," end
      encode(v, out)
    end
    out[#out + 1] = "]"
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
  out[#out + 1] = "{"
  for i, k in ipairs(keys) do
    if i > 1 then out[#out + 1] = "," end
    out[#out + 1] = encode_string(k)
    out[#out + 1] = ":"
    encode(t[k], out)
  end
  out[#out + 1] = "}"
end

function encode(value, out)
  local kind = type(value)
  if kind == "string" then
    out[#out + 1] = encode_string(value)
  elseif kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("JSON cannot represent " .. tostring(value))
    end
    if value % 1 == 0 and math.abs(value) < 2^53 then
      out[#out + 1] = ("%d"):format(value)
    else
      out[#out + 1] = ("%.17g"):format(value)
    end
  elseif kind == "boolean" then
    out[#out + 1] = tostring(value)
  elseif kind == "nil" then
    out[#out + 1] = "null"
  elseif kind == "table" then
    encode_table(value, out)
  else
    error("JSON cannot represent a " .. kind)
  end
end

function M.encode(value)
  local out = {}
  encode(value, out)
  return table.concat(out)
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
