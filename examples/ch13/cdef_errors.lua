-- What happens when declarations are wrong or missing.

local ffi = require("ffi")

-- Calling something you never declared:
print(pcall(function() return ffi.C.strlen("x") end))

-- Declaring a function that does not exist in the library:
ffi.cdef("int no_such_function(int);")
print(pcall(function() return ffi.C.no_such_function(1) end))

-- A C syntax error:
print(pcall(ffi.cdef, "int broken(int x"))

-- An unknown type:
print(pcall(ffi.cdef, "my_type f(void);"))

-- Struct definitions can only be given once per process:
ffi.cdef("struct pair { int a, b; };")
print(pcall(ffi.cdef, "struct pair { int a, b; };"))

-- But a function declared twice keeps the first declaration, silently:
ffi.cdef("int abs(int);")
ffi.cdef("double abs(double);")
print(ffi.C.abs(-2.5))
