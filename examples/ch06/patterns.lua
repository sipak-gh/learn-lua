-- Lua patterns: a table of examples. Each row: pattern, subject, match.
local examples = {
  { "%d+",           "order 66 shipped" },  -- one or more digits
  { "%a+",           "123abc456" },         -- letters
  { "%s",            "no-space here" },     -- whitespace
  { "%u%l+",         "hello World" },       -- upper then lowers
  { "%x+",           "color #ff8800" },     -- the FIRST match wins: c!
  { "%p",            "end." },              -- punctuation
  { "%W+",           "a, b" },              -- uppercase class = complement
  { "[aeiou]+",      "queueing" },          -- a set
  { "[^%s,]+",       "  alpha, beta" },     -- a negated set
  { "[0-9a-f]+",     "ID: 3fa9" },          -- ranges in a set
  { "colou?r",       "my colour" },         -- ? = optional
  { "a.c",           "abc" },               -- . = any character
  { "%.",            "x.y" },               -- %. = a literal dot
  { "^%d+",          "42 is 6*7" },         -- ^ anchors at the start
  { "%d+$",          "6*7 is 42" },         -- $ anchors at the end
  { "^%d+$",         "42x" },               -- whole string must match
}

for _, ex in ipairs(examples) do
  local pattern, subject = ex[1], ex[2]
  print(("%-10s %-20s -> [%s]"):format(pattern, '"' .. subject .. '"', tostring(subject:match(pattern))))
end
