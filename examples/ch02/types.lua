-- type() returns the name of a value's type, as a string.
print(type(nil))              --> nil
print(type(true))             --> boolean
print(type(42))               --> number
print(type("hi"))             --> string
print(type({}))               --> table
print(type(print))            --> function
print(type(io.stdout))        --> userdata  (a C object: an open file)
print(type(coroutine.create(print)))  --> thread (Chapter 11)
print(type(1LL))              --> cdata     (LuaJIT only: C data, Chapter 13)
print(type(type(42)))         --> string: type() itself returns a string
