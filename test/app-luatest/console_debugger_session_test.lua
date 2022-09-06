local t = require('luatest')
local popen = require('popen')
local g = t.group()

local function normalize_path(s)
    return s:gsub("^@", ""):gsub("[^/]+$", "")
end

local function unescape(s)
    return s:gsub('[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]', '')
end

local function tarantool_path(arg)
    local index = -2
    -- arg[-1] is guaranteed to be non-null
    while arg[index] do index = index - 1 end
    return arg[index + 1]
end

local TARANTOOL_PATH = tarantool_path(arg)
local path_to_script = normalize_path(debug.getinfo(1, 'S').source)
local debug_target_script = path_to_script .. 'debug-target.lua'

local DEBUGGER = 'luadebug.lua'
local dbg_header = DEBUGGER .. ": Loaded for " .. jit.version
local dbg_prompt = DEBUGGER .. '>'

local sequence = {
    { [''] = dbg_header },
    { ['n\n'] = dbg_prompt },
    { ['n\n'] = dbg_prompt },
    { ['p T\n'] = 'T => 1970-01-01T03:00:00+0300' },
    { ['n\n'] = dbg_prompt },
    { ['n\n'] = dbg_prompt },
    { ['n\n'] = dbg_prompt },
    { ['n\n'] = dbg_prompt },
    { ['p S\n'] = 'S => "1970-01-01T0300+0300"' },
    { ['n\n'] = dbg_prompt },
    { ['n\n'] = dbg_prompt },
    { ['p T1\n'] = 'T1 => 1970-01-01T03:00:00+0300' },
    { ['n\n'] = dbg_prompt },
    { ['n\n'] = '' },
}

g.test_interactive_debugger_session = function()
    local cmd = { TARANTOOL_PATH, debug_target_script }
    local fh = popen.new(cmd, {
        stdout = popen.opts.PIPE,
        stderr = popen.opts.DEVNULL,
        stdin = popen.opts.PIPE,
    })
    t.assert_is_not(fh, nil)
    for _, row in pairs(sequence) do
        local cmd, expected = next(row)
        if cmd ~= '' then
            fh:write(cmd)
        end
        local result = unescape(fh:read({ timeout = 1.0 }))
        -- dirty hack to skip empty output if there is only command returned
        if result == cmd then
            result = unescape(fh:read({ timeout = 1.0 }))
        end
        t.assert_str_contains(result, expected, false)
    end
    fh:close()
end
