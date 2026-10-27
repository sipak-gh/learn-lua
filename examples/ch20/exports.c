/* A C function in the host program, called from Lua through ffi.C.
   ffi.C can only see it if the program exports its symbols (-Wl,-E). */
#include <stdio.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

int host_answer(int x) { return x * 2; }

int main(void)
{
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  if (luaL_dostring(L, "local ffi = require('ffi')  "
                       "ffi.cdef('int host_answer(int x);')  "
                       "print('host_answer(21) =', ffi.C.host_answer(21))") != 0)
    printf("error: %s\n", lua_tostring(L, -1));
  lua_close(L);
  return 0;
}
