-- assert(v, message) raises message if v is false or nil.
-- Otherwise it returns ALL its arguments.
print(assert(42, "unused"))
print(pcall(function() assert(1 > 2) end))
print(pcall(function() assert(nil, "port is required") end))

-- The idiom: wrap a function that returns nil plus a message.
local n = assert(tonumber("17"))
print(n)
print(pcall(function()
  local chunk = assert(loadstring("return 1 +"))
end))
