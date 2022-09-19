local t = require('luatest')
local fio = require('fio')
local g = t.group()


local function readfile(filename)
    local f = assert(io.open(filename, "rb"))
    return f:read('*a')
end

local files = {
    'strict',
    'debug',
    'errno',
    'fiber',
    'env',
    'datetime',
}

g.test_tarantool_debug_getsources = function()

    local fh = io.popen('git rev-parse --show-toplevel', 'r')
    local git_root = fh:read('*l')
    fh:close()
    t.assert_is_not(git_root, nil)
    t.assert(fio.stat(git_root):is_dir())
    local lua_src_dir = fio.pathjoin(git_root, '/src/lua')
    t.assert_is_not(lua_src_dir, nil)
    t.assert(fio.stat(lua_src_dir):is_dir())

    local tnt = require('tarantool')
    t.assert_is_not(tnt, nil)
    local luadebug = tnt.debug
    t.assert_is_not(luadebug, nil)

    for _, file in pairs(files) do
        local path = ('%s/%s.lua'):format(lua_src_dir, file)
        local text = readfile(path)
        t.assert_is_not(text, nil)
        local source = luadebug.getsources(file)
        t.assert_equals(source, text)
        source = luadebug.getsources(('@builtin/%s.lua'):format(file))
        t.assert_equals(source, text)
    end
end
