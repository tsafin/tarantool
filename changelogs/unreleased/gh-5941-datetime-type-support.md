## feature/lua/datetime

 * Introduce new builtin module `datetime.lua` for date, time, and interval
   support;
 * Support of a new datetime type in storage engines allows to store datetime
   fields and build indices with them (gh-5941, gh-5946).
