-- gsub = global substitution. It returns the new string AND the count.
print(("hello world"):gsub("o", "0"))
print(("hello world"):gsub("o", "0", 1))            -- at most 1 replacement

-- In a replacement string, %0 is the whole match, %1.. the captures.
print(("John Smith"):gsub("(%w+) (%w+)", "%2, %1"))
print(("a b c"):gsub("%w", "<%0>"))

-- A table replacement looks the match (or first capture) up.
local vars = { name = "Ada", lang = "Lua" }
print(("$name writes $lang, not $cobol"):gsub("%$(%w+)", vars)) -- missing: kept

-- A function replacement is called for each match.
print(("3 apples and 12 pears"):gsub("%d+", function(n)
  return tostring(tonumber(n) * 2)
end))

-- Keep only the string: wrap the call in parentheses.
local clean = (("  lots   of   space  "):gsub("%s+", " "))
print("[" .. clean .. "]")

-- To use user text as a pattern, escape the magic characters first.
local function escape(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end
print(escape("1+1=2?"), ("is 1+1=2?"):find(escape("1+1=2?")))
