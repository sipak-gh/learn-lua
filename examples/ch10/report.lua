-- The code under test: formats a small table report.
return function(rows)
  local lines = { ("%-10s %5s"):format("name", "count") }
  for _, row in ipairs(rows) do
    lines[#lines + 1] = ("%-10s %5d"):format(row.name, row.count)
  end
  return table.concat(lines, "\n") .. "\n"
end
