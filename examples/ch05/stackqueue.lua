-- A stack: push and pop at the end. Both are O(1).
local stack = {}
table.insert(stack, "a")
table.insert(stack, "b")
stack[#stack + 1] = "c"
print(table.remove(stack), table.remove(stack), #stack)

-- A queue: table.remove(q, 1) shifts every item (O(n)).
-- Two indexes make both ends O(1).
local queue = { first = 1, last = 0 }

local function push(q, v)
  q.last = q.last + 1
  q[q.last] = v
end

local function pop(q)
  if q.first > q.last then
    return nil                   -- empty
  end
  local v = q[q.first]
  q[q.first] = nil               -- let the item be garbage collected
  q.first = q.first + 1
  return v
end

push(queue, "job1"); push(queue, "job2"); push(queue, "job3")
print(pop(queue), pop(queue))
push(queue, "job4")
print(pop(queue), pop(queue), pop(queue))
