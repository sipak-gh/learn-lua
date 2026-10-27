-- Expected failures: return nil plus a message, and let the caller decide.
local function parse_port(s)
  local n = tonumber(s)
  if n == nil or n % 1 ~= 0 then
    return nil, "not a whole number: " .. tostring(s)
  end
  if n < 1 or n > 65535 then
    return nil, "port out of range: " .. n
  end
  return n
end

for _, s in ipairs({ "8080", "http", "70000" }) do
  local port, err = parse_port(s)
  if port then
    print("port", port)
  else
    print("error", err)
  end
end

-- Converting between the two styles:
print(pcall(function() return assert(parse_port("x")) end))  -- nil, err -> error
local ok, err = pcall(error, "boom", 0)                       -- error -> false, err
print(ok, err)
