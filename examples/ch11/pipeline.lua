-- Producer -> filters -> consumer. Each stage is a coroutine that pulls
-- values from the stage before it. Nothing runs until the consumer asks.

local function producer(lines)
  return coroutine.wrap(function()
    for _, line in ipairs(lines) do
      print("  (produce " .. line .. ")")
      coroutine.yield(line)
    end
  end)
end

local function grep(pattern, source)
  return coroutine.wrap(function()
    for line in source do
      if line:find(pattern) then
        coroutine.yield(line)
      end
    end
  end)
end

local function number(source)
  return coroutine.wrap(function()
    local n = 0
    for line in source do
      n = n + 1
      coroutine.yield(("%d: %s"):format(n, line))
    end
  end)
end

local input = { "apple pie", "banana", "apple tart", "cherry" }
for line in number(grep("^apple", producer(input))) do
  print(line)                                -- the consumer
end
