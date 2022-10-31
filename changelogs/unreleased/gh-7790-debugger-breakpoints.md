## feature/debugger

* Added breakpoints support to the builtin console debugger `luadebug.lua`;
* Created wrapper `tdbg` for convenient activation of debugger session
  without any massaging of target scripts;
* Swapped 'up' and 'down' commands in debugger - to make them behave more
  like in `gdb`/`lldb`.
