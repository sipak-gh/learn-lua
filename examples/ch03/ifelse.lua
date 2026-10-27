-- Usage: luajit ifelse.lua NUMBER
local n = tonumber(arg[1])

if n == nil then
  print("not a number: " .. tostring(arg[1]))
elseif n < 0 then
  print(n .. " is negative")
elseif n == 0 then
  print("zero")
else
  if n % 2 == 0 then
    print(n .. " is positive and even")
  else
    print(n .. " is positive and odd")
  end
end
