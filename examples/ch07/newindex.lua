-- __newindex runs when you assign to a key the table does NOT have.
local log = {}
local t = setmetatable({}, {
  __newindex = function(tbl, key, value)
    log[#log + 1] = ("set %s = %s"):format(tostring(key), tostring(value))
    rawset(tbl, key, value)      -- store it for real (t[key] = value would recurse)
  end,
})

t.x = 1        -- new key: logged
t.x = 2        -- key exists now: plain assignment, not logged
t.y = 3        -- new key: logged
print(t.x, t.y)
print(table.concat(log, "; "))

-- __newindex can also be a table: new keys go THERE instead.
local store = {}
local front = setmetatable({}, { __newindex = store })
front.a = 10
print(rawget(front, "a"), store.a)
