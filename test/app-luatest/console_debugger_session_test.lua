local t = require('luatest')
local popen = require('popen')
local tnt = require('tarantool')
local fio = require('fio')

local function unescape(s)
    return s and s:gsub('[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]', '') or ''
end

local function trim(s)
    return s and s:gsub('%s+$', '') or ''
end

local function tarantool_path(arg)
    local index = -2
    -- arg[-1] is guaranteed to be non-null
    while arg[index] do index = index - 1 end
    return arg[index + 1]
end

local TARANTOOL_PATH = tarantool_path(arg)
local DEBUGGER = 'luadebug'
local dbg_header = "Tarantool debugger " .. tnt.version
local dbg_prompt = DEBUGGER .. '>'
local dbg_failed_bp = 'command expects argument in format filename:NN or ' ..
                      'filename+NN, where NN should be a positive number.'
local dbg_failed_bpd = 'command expects argument specifying breakpoint or' ..
                      ' * for all breakpoints.'
local verbose = os.getenv("DEBUG") or false

local function debuglog(...)
    if not verbose then
        return
    end
    print(...)
end

--[[
    Convert passed multi-line literal script
    to the temporary file. Get rid of line annotations,
    leaving code alone.

    Annotated lines are in a form:
        1 | local date = require 'datetime'
        2 | local T = date.new{hour = 3, tzoffset = '+0300'}
]]
local function dbg_script(content)
    local tmpname = os.tmpname()
    local f = assert(io.open(tmpname, "wb"))
    -- process multi-line literal
    for line in string.gmatch(content, "[^\n]+") do
        --[[
            Process annotated code line, delimited with '|'.

        +-------- virtual line number (for easier maintaining)
        | +------ delimiter
        | | +---- Lua code to be executed
        V V V
        1 | local date = require 'datetime'

        ]]
        local delim = line:find('|')

        -- if there is no delimiter - write it as-is
        if not delim then
            f:write(line..'\n')
        else
            -- TODO - assert if there is incorrect line numbers
            -- at the moment just ignore annotation entirely.
            f:write(line:sub(delim + 1)..'\n')
        end
    end
    f:close()
    debuglog("temporary name:", tmpname)
    return tmpname
end

local cmd_aliases = {
    ['c'] = 'c|cont|continue',
    ['d'] = 'd|down',
    ['e'] = 'e|eval',
    ['f'] = 'f|finish|step_out',
    ['h'] = 'h|help|?',
    ['l'] = 'l|locals',
    ['n'] = 'n|next|step_over',
    ['p'] = 'p|print',
    ['q'] = 'q|quit',
    ['s'] = 's|st|step|step_into',
    ['t'] = 't|trace|bt',
    ['u'] = 'u|up',
    ['w'] = 'w|where',
}

local MAX_ALIASES_COUNT = 4

local function get_cmd_alias(cmd, number)
    if not cmd_aliases[cmd] then
        return cmd
    end
    local cmds = {}
    for v, _ in cmd_aliases[cmd]:gmatch('[^|]+') do
        table.insert(cmds, v)
    end
    return cmds[number % #cmds + 1]
end

--[[
    Should handle equally well both:
    'n' and 'p obj'
]]
local function get_key_arg_pair(cmd)
    local gen = cmd:gmatch('[^%s]+')
    return gen(), gen()
end

local g = t.group('debug', {
    {sequence = 'full'},
    {sequence = 'bps_ok'},
    {sequence = 'bps_fail'},
    {sequence = 'bpd_ok'},
    {sequence = 'bpd_fail'},
})

local sequences = {

    -- full, complex sequence
    full = {
        dbg_script [[
     1|local date = require 'datetime'
     2|
     3|local T = date.new{hour = 3, tzoffset = '+0300'}
     4| print(T)
     5|
     6|local fmt = '%Y-%m-%dT%H%M%z'
     7|local S  = T:format(fmt)
     8|print(S)
     9|local T1 = date.parse(S, {format = fmt})
    10|print(T1)
    11|
    12|os.exit(0)
]],
        { ['\t'] = '' }, -- \t is a special value for start
        { ['n'] = dbg_prompt },
        { ['s'] = dbg_prompt },
        { ['n'] = dbg_prompt },
        { ['n'] = dbg_prompt },
        { ['p'] = 'command expects argument, but none received' },
        { ['p obj'] = 'obj => {"tzoffset" = "+0300", "hour" = 3}' },
        { ['n'] = dbg_prompt },
        { ['p ymd'] = 'ymd => false' },
        { ['w'] = 'local hms = false' },
        { ['h'] = dbg_prompt },
        { ['t'] = '=> builtin/datetime.lua' },
        { ['u'] = '{file}:3 in chunk at' },
        -- FIXME - we should not show calling side at luadebug.lua::start
        -- { ['u'] = 'Already at the bottom of the stack.' },
        { ['u'] = 'Inspecting frame: builtin/luadebug.lua' },
        { ['d'] = '{file}:3 in chunk at' },
        { ['d'] = 'Inspecting frame: builtin/datetime.lua' },
        { ['l'] = 'obj => {"tzoffset" = "+0300", "hour" = 3}' },
        { ['f'] = dbg_prompt },
        { ['n'] = dbg_prompt },
        { ['p T'] = 'T => 1970-01-01T03:00:00+0300' },
        { ['n'] = dbg_prompt },
        { [''] = dbg_prompt },
        { [''] = dbg_prompt },
        { [''] = dbg_prompt },
        { ['p S'] = 'S => "1970-01-01T0300+0300"' },
        { ['c'] = '' },
    },

    -- partial sequence with successful breakpoints added
    bps_ok = {
        dbg_script [[
     1|local date = require 'datetime'
     2|
     3|local T = date.new{hour = 3, tzoffset = '+0300'}
     4|print(T)
     5|
     6|local fmt = '%Y-%m-%dT%H%M%z'
     7|local S  = T:format(fmt)
     8|print(S)
     9|local T1 = date.parse(S, {format = fmt})
    10|print(T1)
    11|
    12|os.exit(0)
]],
        { ['\t'] = '' }, -- \t is a special value for start
        { ['b +9'] = dbg_prompt },
        { ['c'] = '{file}:9' },
        { ['n'] = dbg_prompt },
        { ['p S'] = 'S => "1970-01-01T0300+0300"' },
        { ['p T'] = 'T => 1970-01-01T03:00:00+0300' },
        { ['c'] = '' },
    },

    -- partial sequence with failed breakpoint addsitions
    bps_fail = {
        dbg_script [[
    1|local date = require 'datetime'
    2|local T = date.new{hour = 3, tzoffset = '+0300'}
    3|print(T)
    4|os.exit(0)
]],
        { ['\t'] = '' }, -- \t is a special value for start
        { ['b'] = 'command expects argument, but none received' },
        { ['b 11'] = dbg_failed_bp },
        { ['b {file}'] = dbg_failed_bp },
        { ['b {file}:'] = dbg_failed_bp },
        { ['b {file}:-10'] = dbg_failed_bp },
    },

    -- partial sequence with breakpoints additions and removals
    bpd_ok = {
        dbg_script [[
     1|local date = require 'datetime'
     2|
     3|local T = date.new{hour = 3, tzoffset = '+0300'}
     4|print(T)
     5|
     6|local fmt = '%Y-%m-%dT%H%M%z'
     7|local S  = T:format(fmt)
     8|print(S)
     9|local T1 = date.parse(S, {format = fmt})
    10|print(T1)
    11|
    12|os.exit(0)
]],
        { ['\t'] = '' }, -- \t is a special value for start
        { ['b +7'] = '{file}:7' },
        { ['bl'] = '{file}:7' },
        { ['b :5'] = '{file}:5' },
        { ['bl'] = '{file}:5' },
        { ['bd :5'] = '{file}:5' },
        { ['bl'] = '{file}:7' },
        { ['bd +7'] = '{file}:7' },
        { ['b :6'] = '{file}:6' },
        { ['bl'] = '{file}:6' },
        { ['bd *'] = 'Removed all breakpoints' },
        { ['bl'] = 'No active breakpoints defined' },
    },
    -- partial sequence with failed breakpoints removals
    bpd_fail = {
        dbg_script [[
    1|local date = require 'datetime'
    2|local T = date.new{hour = 3, tzoffset = '+0300'}
    3|print(T)
    4|os.exit(0)
]],
        { ['\t'] = '' }, -- \t is a special value for start
        { ['bd'] = 'command expects argument, but none received' },
        { ['bd 11'] = dbg_failed_bpd },
        { ['bd {file}'] = dbg_failed_bpd },
        { ['bd {file}:'] = dbg_failed_bpd },
        { ['bd {file}:-10'] = dbg_failed_bpd },
    },
}

local function debug_session(sequence)
    local tmpfile = table.remove(sequence, 1)
    t.assert(type(tmpfile) == 'string')
    local cmd = { TARANTOOL_PATH, '-d', tmpfile }
    local short_src = fio.basename(tmpfile)
    debuglog('short_src:', short_src)
    --[[
        repeat multiple times to check all command aliases
    ]]
    for i = 1, MAX_ALIASES_COUNT do
        local fh = popen.new(cmd, {
            stdout = popen.opts.PIPE,
            stderr = popen.opts.PIPE,
            stdin = popen.opts.PIPE,
        })
        t.assert_is_not(fh, nil)
        local first = true
        for _, row in pairs(sequence) do
            local cmd, expected = next(row)
            -- interpret template strings {file}
            expected = expected:gsub('{file}', short_src)
            if cmd ~= '\t' then
                if cmd ~= '' then
                    local key, arg = get_key_arg_pair(cmd)
                    arg = arg and (' ' .. arg) or ''
                    cmd = get_cmd_alias(key, i) .. arg .. '\n'
                else -- '' empty command - repeat prior one
                    cmd = cmd .. '\n'
                end
                fh:write(cmd)
                debuglog('cmd: "'..trim(cmd)..'"')
            end

            local result
            local clean_cmd = trim(cmd)
            -- there should be empty stderr - check it before stdout
            local errout = fh:read({ timeout = 0.05, stderr = true})
            debuglog('errout:', trim(errout))
            if first and errout then
                -- we do not expect anything on stderr
                -- with exception of initial debugger header
                t.assert_str_contains(trim(errout), dbg_header, false)
                first = false
            else
                t.assert(errout == nil or trim(errout) == '')
            end
            repeat
                result = trim(unescape(fh:read({ timeout = 0.5 })))
                debuglog('result:', result)
            until result ~= '' and result ~= clean_cmd
            if expected ~= '' then
                t.assert_str_contains(result, expected, false)
            end
        end
        fh:close()
    end
    debuglog('delete ', tmpfile)
    os.remove(tmpfile)
end

g.test_interactive_debugger_session = function(cg)
    local scenario_name = cg.params.sequence
    assert(scenario_name)
    assert(sequences[scenario_name])
    debug_session(sequences[scenario_name])
end
