/* A host whose Lua module is linked in as bytecode.  Build greet.o with
   `luajit -b -n greet greet.lua greet.o` and link with -Wl,-E: require
   then finds the exported symbol luaJIT_BC_greet without any file. */
#include <stdio.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

int main(void)
{
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  if (luaL_dostring(L, "package.path, package.cpath = '', ''  " /* no files */
                       "local greet = require('greet')  "
                       "print(greet.hello('linked-in bytecode'))") != 0)
    printf("error: %s\n", lua_tostring(L, -1));
  lua_close(L);
  return 0;
}
