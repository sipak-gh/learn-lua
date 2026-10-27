-- An array is a table with keys 1, 2, 3, ... Indexes start at 1.
local colors = { "red", "green", "blue" }
print(colors[1], colors[3], colors[4])   -- a missing index is nil
print(#colors)                           -- the length

-- Append: the two common ways.
colors[#colors + 1] = "cyan"
table.insert(colors, "magenta")
print(table.concat(colors, ", "))

-- Insert and remove at a position: later items shift.
table.insert(colors, 1, "black")         -- at the front
local removed = table.remove(colors, 2)  -- returns the removed item
print(removed, table.concat(colors, ", "))
print(table.remove(colors))              -- no position: removes the last
print(#colors)

-- table.concat(t, sep, i, j) joins strings and numbers.
print(table.concat({ 1, 2, 3 }, "+", 2, 3))

-- unpack turns items into separate values.
print(unpack(colors))

-- Loop with a numeric for or with ipairs.
for i = 1, #colors do io.write(i, "=", colors[i], " ") end print()
for i, c in ipairs(colors) do io.write(i, "=", c, " ") end print()
