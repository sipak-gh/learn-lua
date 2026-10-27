-- The command-line arguments live in the global table `arg`.
print("interpreter:", arg[-1])
print("script:     ", arg[0])
print("first:      ", arg[1])
print("second:     ", arg[2])
print("count:      ", #arg)   -- # is the length operator (Chapter 2)
