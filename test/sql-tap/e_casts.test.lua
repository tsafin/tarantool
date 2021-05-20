#!/usr/bin/env tarantool
local test = require("sqltester")
test:plan(222)

local yaml = require("yaml")
local ffi = require("ffi")

local verbose = 0

if arg[1] == '-v' or arg[1] == '--verbose' then
    verbose = 1
end

ffi.cdef [[
    enum field_type {
        FIELD_TYPE_ANY = 0,
        FIELD_TYPE_UNSIGNED,
        FIELD_TYPE_STRING,
        FIELD_TYPE_NUMBER,
        FIELD_TYPE_DOUBLE,
        FIELD_TYPE_INTEGER,
        FIELD_TYPE_BOOLEAN,
        FIELD_TYPE_VARBINARY,
        FIELD_TYPE_SCALAR,
        FIELD_TYPE_DECIMAL,
        FIELD_TYPE_UUID,
        FIELD_TYPE_ARRAY,
        FIELD_TYPE_MAP,
        field_type_MAX
    };
]]

-- Date/time/interval types to be uncommented and used
-- once corresponding box implementation completed
local t_any = ffi.C.FIELD_TYPE_ANY
local t_unsigned = ffi.C.FIELD_TYPE_UNSIGNED
local t_string = ffi.C.FIELD_TYPE_STRING
local t_number = ffi.C.FIELD_TYPE_NUMBER
local t_double = ffi.C.FIELD_TYPE_DOUBLE
local t_integer = ffi.C.FIELD_TYPE_INTEGER
local t_boolean = ffi.C.FIELD_TYPE_BOOLEAN
local t_varbinary = ffi.C.FIELD_TYPE_VARBINARY
local t_scalar = ffi.C.FIELD_TYPE_SCALAR
local t_decimal = ffi.C.FIELD_TYPE_DECIMAL
-- local t_date = -1
-- local t_time = -2
-- local t_timestamp = -3
-- local t_interval = -4
local t_uuid = ffi.C.FIELD_TYPE_UUID
local t_array = ffi.C.FIELD_TYPE_ARRAY
local t_map = ffi.C.FIELD_TYPE_MAP

local proper_order = {
    t_any,
    t_unsigned,
    t_string,
    t_double,
    t_integer,
    t_boolean,
    t_varbinary,
    t_number,
    t_decimal,
    t_uuid,
    -- t_date,
    -- t_time,
    -- t_timestamp,
    -- t_interval,
    t_array,
    t_map,
    t_scalar,
}

local type_names = {
    [t_any]       = 'any',
    [t_unsigned]  = 'unsigned',
    [t_string]    = 'string',
    [t_double]    = 'double',
    [t_integer]   = 'integer',
    [t_boolean]   = 'boolean',
    [t_varbinary] = 'varbinary',
    [t_number]    = 'number',
    [t_decimal]   = 'decimal',
    [t_uuid]      = 'uuid',
    -- [t_date]      = 'date',
    -- [t_time]      = 'time',
    -- [t_timestamp] = 'timestamp',
    -- [t_interval]  = 'interval',
    [t_array]     = 'array',
    [t_map]       = 'map',
    [t_scalar]    = 'scalar',
}

-- not all types implemented/enabled at the moment
-- but we do keep their projected status in the
-- spec table
local enabled_type = {
    [t_any]       = false, -- there is no way in SQL to instantiate ANY type expression
    [t_unsigned]  = true,
    [t_string]    = true,
    [t_double]    = true,
    [t_integer]   = true,
    [t_boolean]   = true,
    [t_varbinary] = true,
    [t_number]    = true,
    [t_decimal]   = false,
    [t_uuid]      = false,
    -- [t_date]     = false,
    -- [t_time]     = false,
    -- [t_timestamp]= false,
    -- [t_interval] = False,
    [t_array]     = false,
    [t_map]       = false,
    [t_scalar]    = true,
}

-- table of _TSV_ (tab separated values)
-- copied from sql-lua-tables-v5.xls // TNT implicit today
local explicit_casts_table_spec = {
    [t_any] =     {"Y", "S", "Y", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S"},
    [t_unsigned]= {"Y", "Y", "Y", "Y", "Y", "" , "" , "Y", "Y", "" , "" , "" , "Y"},
    [t_string] =  {"Y", "S", "Y", "S", "S", "S", "Y", "S", "S", "S", "S", "S", "Y"},
    [t_double] =  {"Y", "S", "Y", "Y", "S", "" , "" , "Y", "Y", "" , "" , "" , "Y"},
    [t_integer] = {"Y", "S", "Y", "Y", "Y", "" , "" , "Y", "Y", "" , "" , "" , "Y"},
    [t_boolean] = {"Y", "" , "Y", "" , "" , "Y", "" , "" , "" , "" , "" , "" , "Y"},
    [t_varbinary]={"Y", "" , "Y", "N", "" , "" , "Y", "" , "" , "S", "" , "" , "Y"},
    [t_number] =  {"Y", "S", "Y", "Y", "S", "" , "" , "Y", "Y", "" , "" , "" , "Y"},
    [t_decimal] = {"Y", "S", "Y", "S", "S", "" , "" , "Y", "Y", "" , "" , "" , "Y"},
    [t_uuid] =    {"Y", "" , "Y", "" , "" , "" , "Y", "" , "" , "Y", "" , "" , "Y"},
    [t_array] =   {"Y", "N", "Y", "N", "N", "N", "" , "" , "" , "" , "Y", "" , "N"},
    [t_map] =     {"Y", "N", "Y", "N", "N", "N", "" , "" , "" , "" , "" , "Y", "N"},
    [t_scalar] =  {"Y", "S", "Y", "S", "S", "S", "S", "S", "S", "S", "" , "" , "Y"},
}

-- local extra_checks = false
local explicit_casts = {}
-- local implicit_casts = {}

-- implicit conversion table is considered consistent if
-- it's sort of symmetric against diagonal
-- (not necessary that always/sometimes are matching
-- but at least something should be presented)

--[[ local function check_table_consistency(table)
    for _, i in ipairs(proper_order) do
        local string = ''
        for _, j in ipairs(proper_order) do
            print(i, j)
            -- local item = implicit_casts[i][j]
            -- string = string .. (xlat[item] or ' ')
        end
        print(string)
    end
end
]]

    -- if there is enabled extra checks then check ocnsistency of input tables
    -- just to make sure their sanity
--[[     if extra_checks then
        check_table_consistency()
    end
 ]]

local c_no = 0
local c_maybe = 1
local c_yes = 2

local function normalize_cast(v)
    local xlat =  {
        ['Y'] = c_yes,
        ['S'] = c_maybe,
        ['N'] = c_no,
    }
    return xlat[v ~= nil and v or 'N']
end

local function human_cast(v)
    local xlat = {
        [c_yes] = 'Y',
        [c_maybe] = 'S',
        [c_no] = ' '
    }
    return xlat[v ~= nil and v or c_no]
end

local function load_casts_spec(spec_table)
    local casts = {}
    for i, t_from  in ipairs(proper_order) do
        local row = spec_table[t_from]
        casts[t_from] = {}
        for j, t_to  in ipairs(proper_order) do
            if enabled_type[t_from] and enabled_type[t_to] then
                casts[t_from][t_to] = normalize_cast(spec_table[t_from][j])
            end
        end
    end
    -- if there is enabled extra checks then check ocnsistency of input tables
    -- just to make sure their sanity
--[[     if extra_checks then
        check_table_consistency()
    end ]]

    return casts
end

explicit_casts = load_casts_spec(explicit_casts_table_spec)

if verbose > 0 then
    local function show_casts_table(table)
        local max_len = #"12. varbinary" + 1

        -- show banner
        local col_names = ''
        for i, t_val in ipairs(proper_order) do
            col_names = col_names .. string.format("%2d |", t_val)
        end
        col_names = string.sub(col_names, 1, #col_names-1)
        print(string.format("%"..max_len.."s|%s|", "", col_names))
        -- show splitter
        local banner = '+---+---+---+---+---+---+---+---+---+---+---+---+---+'
        print(string.format("%"..max_len.."s%s", "", banner))

        for i, from in ipairs(proper_order) do
            local line = ''
            for j, to in ipairs(proper_order) do
                line = line .. string.format("%2s |", human_cast(table[from][to]))
            end
            line = string.sub(line, 1, #line-1)
            local s = string.format("%2d.%10s |%s|", from, type_names[from], line)
            print(s)
        end
        print(string.format("%"..max_len.."s%s", "", banner))
    end

    show_casts_table(explicit_casts)
end

local function merge_tables(...)
    local n = select('#', ...)
    local tables = {...}
    local result = {}

    for i=1,n do
        local t = tables[i]
        --print(yaml.encode(t))
        assert(type(tables[i]) == 'table')
        for j,v in pairs(t) do
            table.insert(result, v)
        end
    end
    return result
end

local gen_type_samples = {
        [t_unsigned]  = {"0", "1", "2"},
        [t_integer]   = {"-678", "-1", "0", "1", "2", "3", "678"},
        [t_double]    = {"0.0", "123.4", "-567.8"},
        [t_string]    = {"''", "'1'", "'abc'", "'def'", "'TRUE'", "'FALSE'"},
        [t_boolean]   = {"false", "true", "null"},
        [t_varbinary] = {"X'312E3233'", "X'2D392E3837'", "X'302E30303031'"},
}

local function gen_type_exprs(type)
    if type == t_number then
        return merge_tables(gen_type_samples[t_unsigned],
                            gen_type_samples[t_integer],
                            gen_type_samples[t_double])
    end
    if type == t_scalar then
        return merge_tables(gen_type_samples[t_unsigned],
                            gen_type_samples[t_integer],
                            gen_type_samples[t_double],
                            gen_type_samples[t_string],
                            gen_type_samples[t_boolean],
                            gen_type_samples[t_varbinary])
    end
    return gen_type_samples[type] or {}
end

local function gen_sql_cast_from_to(t_from, t_to)
    local queries = {}
    local from_exprs = gen_type_exprs(t_from)
    local to_typename = type_names[t_to]
    for _, expr in pairs(from_exprs) do
        local query = string.format([[ select cast(%s as %s); ]], expr, to_typename)
        table.insert(queries, query)
    end
    return queries
end

local function catch_query(query)
    local result = {pcall(box.execute, query)}

    if not result[1] or result[3] ~= nil then
        return false, result[3]
    end
    return true, result[2]
end

local function label_for(from, to, query)
    local parent_frame = debug.getinfo(2, "nSl")
    local filename = parent_frame.source:sub(1,1) == "@" and parent_frame.source:sub(2)
    local line = parent_frame.currentline
    return string.format("%s+%d:[%s,%s] %s", filename, line,
                         type_names[from], type_names[to], query)
end

for i, from in ipairs(proper_order) do
    for j, to in ipairs(proper_order) do
        -- skip ANY, DECIMAL, UUID, etc.
        if enabled_type[from] and enabled_type[to] then
            local cell = explicit_casts[from][to]
            local gen = gen_sql_cast_from_to(from, to)
            local failures = {}
            local successes = {}
            local castable = false
            local expected = explicit_casts[from][to]
            if verbose > 0 then
                print(expected, yaml.encode(gen))
            end
            for i, v in pairs(gen) do
                local ok, result
                ok, result = catch_query(v)
                if verbose > 0 then
                    print(string.format("ok = %s, result = %s, query = %s",
                         ok, result, v))

                end
                -- print(v, 'ok'..yaml.encode(ok), 'result'..yaml.encode(result))
                if expected == c_yes then
                    test:ok(true == ok, label_for(from, to, v))
                elseif expected == c_no then
                    test:ok(false == ok, label_for(from, to, v))
                else
                -- we can't report immediately for c_maybe because some 
                -- cases allowed to fail, so postpone decision
                    if ok then
                        castable = true
                        table.insert(successes, {result, v})
                    else
                        table.insert(failures, {result, v})
                    end
                end
            end

            -- ok, we aggregated stats for c_maybe mode - check it now
            if expected == c_maybe then
                    test:ok(castable, label_for(from, to, #gen and gen[1] or ''),
                            failures)
            end
        end
    end
end


test:finish_test()
