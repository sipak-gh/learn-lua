-- Turns plain data (tables, strings, numbers, booleans) into Lua source
-- code that rebuilds it. Reading the data back is just loading that code.

local M = {}

local function is_identifier(key)
  return type(key) == "string" and key:find("^[%a_][%w_]*$") ~= nil
end

local function write(value, indent, out)
  local kind = type(value)
  if kind == "string" then
    out[#out + 1] = ("%q"):format(value)
  elseif kind == "number" then
    out[#out + 1] = ("%.17g"):format(value)  -- 17 digits: reads back exactly
  elseif kind == "boolean" then
    out[#out + 1] = tostring(value)
  elseif kind == "table" then
    -- Array part first, then the other keys in sorted order, so the same
    -- data always gives the same text.
    local inner = indent .. "  "
    out[#out + 1] = "{\n"
    for _, v in ipairs(value) do
      out[#out + 1] = inner
      write(v, inner, out)
      out[#out + 1] = ",\n"
    end
    local keys = {}
    for k in pairs(value) do
      if not (type(k) == "number" and k >= 1 and k <= #value and k % 1 == 0) then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      out[#out + 1] = inner
      if is_identifier(k) then
        out[#out + 1] = k
      else
        out[#out + 1] = "["
        write(k, inner, out)
        out[#out + 1] = "]"
      end
      out[#out + 1] = " = "
      write(value[k], inner, out)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = indent .. "}"
  else
    error("cannot serialize a " .. kind)
  end
end

function M.serialize(value)
  local out = {}
  write(value, "", out)
  return table.concat(out)
end

-- Loads data written by serialize. The chunk runs with an empty
-- environment: a data file cannot call any function.
function M.load(path)
  local chunk, err = loadfile(path)
  if chunk == nil then
    return nil, err
  end
  setfenv(chunk, {})
  local ok, value = pcall(chunk)
  if not ok then
    return nil, value
  end
  return value
end

return M
