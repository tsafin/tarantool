## feature/debugger

* Introduced a new console debugger `luadebug.lua` for debugging external and
  builtin Lua modules.
* Introduced a new Lua API `tarantool.debug.getsources()` which allows
  seeing sources of builtin modules in any external debugger.
