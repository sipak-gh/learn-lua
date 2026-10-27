-- How big is Lua? Count the functions in each standard library table.

local libs = { "_G", "string", "table", "math", "io", "os",
               "coroutine", "debug", "package", "bit", "jit", "ffi" }

local total = 0
for _, name in ipairs(libs) do
  local t = name == "_G" and _G or (_G[name] or require(name))
  local n = 0
  for _, v in pairs(t) do
    if type(v) == "function" then n = n + 1 end
  end
  total = total + n
  print(("%-10s %3d functions"):format(name, n))
end
print(("%-10s %3d"):format("total", total))

local kinds = {}
for _, v in pairs(_G) do
  kinds[type(v)] = (kinds[type(v)] or 0) + 1
end
print("globals by type:", kinds["function"], "functions,", kinds.table, "tables")
