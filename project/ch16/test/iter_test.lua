local iter = require("stash.iter")

local function is_even(n) return n % 2 == 0 end

test("values, filter and collect", function()
  same(iter.collect(iter.values({ 1, 2, 3, 4 })), { 1, 2, 3, 4 })
  same(iter.collect(iter.filter(is_even, iter.values({ 1, 2, 3, 4 }))), { 2, 4 })
end)

test("take stops early", function()
  same(iter.collect(iter.take(2, iter.values({ 1, 2, 3 }))), { 1, 2 })
  same(iter.collect(iter.take(0, iter.values({ 1, 2, 3 }))), {})
  same(iter.collect(iter.take(5, iter.values({ 1 }))), { 1 })
end)

test("take does not pull more values than it needs", function()
  local pulled = 0
  local function counting()
    pulled = pulled + 1
    return pulled                            -- an endless iterator: 1, 2, 3, ...
  end
  same(iter.collect(iter.take(3, counting)), { 1, 2, 3 })
  eq(pulled, 3)
end)

test("errors inside a stage reach the consumer", function()
  local it = iter.filter(function(v) error("bad value " .. v) end, iter.values({ 7 }))
  raises(function() iter.collect(it) end, "bad value 7")
end)
