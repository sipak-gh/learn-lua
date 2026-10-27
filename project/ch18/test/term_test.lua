local term = require("stash.term")

test("always and never ignore the terminal", function()
  eq(term.use_color("always"), true)
  eq(term.use_color("never"), false)
end)

test("the painter wraps text in escape codes only when enabled", function()
  eq(term.painter(true)("7", "id"), "\27[33m7\27[0m")
  eq(term.painter(false)("7", "id"), "7")
end)

test("without a terminal the width comes from COLUMNS or defaults to 80", function()
  if term.is_tty(1) then
    return                                   -- run with output to a terminal: skip
  end
  eq(term.width(), tonumber(os.getenv("COLUMNS")) or 80)
end)
