-- Cooperative multitasking: a scheduler runs tasks in turns. A task runs
-- until it yields; nothing interrupts it. The clock here is a counter,
-- so the output is the same on every run.

local tasks = {}                             -- { co = coroutine, wake = tick }
local now = 0

local function spawn(name, fn)
  tasks[#tasks + 1] = { name = name, co = coroutine.create(fn), wake = 0 }
end

-- Called from inside a task: give up control for `ticks` ticks.
local function sleep(ticks)
  coroutine.yield(ticks)
end

local function run()
  while #tasks > 0 do
    local i = 1
    while i <= #tasks do
      local t = tasks[i]
      local finished = false
      if t.wake <= now then
        local ok, result = coroutine.resume(t.co)  -- result: ticks, or an error
        if not ok then
          print(("[%d] %s failed: %s"):format(now, t.name, result))
        end
        finished = coroutine.status(t.co) == "dead"
        if not finished then
          t.wake = now + result
        end
      end
      if finished then
        table.remove(tasks, i)               -- the next task moves into slot i
      else
        i = i + 1
      end
    end
    now = now + 1
  end
end

spawn("ping", function()
  for i = 1, 3 do
    print(("[%d] ping %d"):format(now, i))
    sleep(2)
  end
end)

spawn("pong", function()
  for i = 1, 2 do
    print(("[%d] pong %d"):format(now, i))
    sleep(3)
  end
  error("pong gives up")
end)

run()
print("all tasks finished at tick " .. now)
