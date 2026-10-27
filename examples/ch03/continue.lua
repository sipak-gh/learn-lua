-- Lua has no `continue`. A goto to a label at the end of the body does the job.
for i = 1, 6 do
  if i % 3 == 0 then
    goto continue              -- skip multiples of 3
  end
  io.write(i, " ")
  ::continue::
end
print()

-- goto also leaves nested loops in one step.
for row = 1, 3 do
  for col = 1, 3 do
    if row * col == 4 then
      print("found 4 at", row, col)
      goto done
    end
  end
end
::done::
print("after the loops")
