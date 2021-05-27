#!/usr/bin/env tarantool
local tap = require("tap")
local test = tap.test("errno")

test:plan(3)

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
    [t_uuid]      = true,
    -- [t_date]     = false,
    -- [t_time]     = false,
    -- [t_timestamp]= false,
    -- [t_interval] = False,
    [t_array]     = false,
    [t_map]       = false,
    [t_scalar]    = true,
}

-- Enabled types which may be targets for explicit casts
local enabled_type_cast = table.deepcopy(enabled_type)
enabled_type_cast[t_any] = true

-- table of _TSV_ (tab separated values)
-- copied from sql-lua-tables-v5.xls
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

local implicit_casts_table_spec = {
    [t_any] =     {"Y", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S"},
    [t_unsigned]= {"Y", "Y", "Y", "Y", "Y", "" , "" , "Y", "Y", "" , "" , "" , "Y"},
    [t_string] =  {"Y", "S", "Y", "S", "S", "" , "Y", "S", "S", "S", "" , "" , "Y"},
    [t_double] =  {"Y", "S", "Y", "Y", "S", "" , "" , "Y", "Y", "" , "" , "" , "Y"},
    [t_integer] = {"Y", "S", "Y", "Y", "Y", "" , "" , "Y", "Y", "" , "" , "" , "Y"},
    [t_boolean] = {"Y", "" , "" , "" , "" , "Y", "" , "" , "" , "" , "" , "" , "Y"},
    [t_varbinary]={"Y", "" , "Y", "" , "" , "" , "Y", "" , "" , "S", "" , "" , "Y"},
    [t_number] =  {"Y", "S", "Y", "Y", "S", "" , "" , "Y", "Y", "" , "" , "" , "Y"},
    [t_decimal] = {"Y", "S", "Y", "S", "S", "" , "" , "Y", "Y", "" , "" , "" , "Y"},
    [t_uuid] =    {"Y", "" , "Y", "" , "" , "" , "Y", "" , "" , "Y", "" , "" , "Y"},
    [t_array] =   {"Y", "" , "" , "" , "" , "" , "" , "" , "" , "" , "Y", "" , "" },
    [t_map] =     {"Y", "" , "" , "" , "" , "" , "" , "" , "" , "" , "" , "Y", "" },
    [t_scalar] =  {"Y", "S", "S", "S", "S", "S", "S", "S", "S", "S", "" , "" , "S"},
}

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

local function load_casts_spec(spec_table, enabled_from, enabled_to)
    local casts = {}
    for _, t_from  in ipairs(proper_order) do
        casts[t_from] = {}
        for j, t_to  in ipairs(proper_order) do
            if enabled_from[t_from] and enabled_to[t_to] then
                casts[t_from][t_to] = normalize_cast(spec_table[t_from][j])
            end
        end
    end
    return casts
end

local function label_for(from, to, title)
    local parent_frame = debug.getinfo(2, "nSl")
    local filename = parent_frame.source:sub(1,1) == "@" and parent_frame.source:sub(2)
    local line = parent_frame.currentline
    return string.format("%s:%d [%s,%s] %s", filename, line,
                         type_names[from], type_names[to], title)
end

local function show_casts_table(table)
    local max_len = #"12. varbinary" + 1

    -- show banner
    local col_names = ''
    for _, t_val in ipairs(proper_order) do
        col_names = col_names .. string.format("%2d |", t_val)
    end
    col_names = string.sub(col_names, 1, #col_names-1)
    print(string.format("%"..max_len.."s|%s|", "", col_names))
    -- show splitter
    local banner = '+---+---+---+---+---+---+---+---+---+---+---+---+---+'
    print(string.format("%"..max_len.."s%s", "", banner))

    for _, from in ipairs(proper_order) do
        local line = ''
        for _, to in ipairs(proper_order) do
            line = line .. string.format("%2s |", human_cast(table[from][to]))
        end
        line = string.sub(line, 1, #line-1)
        local s = string.format("%2d.%10s |%s|", from, type_names[from], line)
        print(s)
    end
    print(string.format("%"..max_len.."s%s", "", banner))
end

local explicit_casts = load_casts_spec(explicit_casts_table_spec, enabled_type, enabled_type_cast)
local implicit_casts = load_casts_spec(implicit_casts_table_spec, enabled_type, enabled_type)

if verbose > 0 then
    show_casts_table(explicit_casts)
    show_casts_table(implicit_casts)
end

-- 0. check consistency of input conversion table

-- implicit conversion table is considered consistent if
-- it's sort of symmetric against diagonal
-- (not necessary that always/sometimes are matching
-- but at least something should be presented)
local function test_check_table_consistency(test)
    test:plan(169)
    for _, from in ipairs(proper_order) do
        for _, to in ipairs(proper_order) do
            test:ok((normalize_cast(implicit_casts[from][to]) ~= c_no) ==
                    (normalize_cast(implicit_casts[to][from]) ~= c_no),
                    label_for(from, to,
                              string.format("%s ~= %s",
                                            implicit_casts[from][to],
                                            implicit_casts[to][from])))
        end
    end
end

local function merge_tables(...)
    local n = select('#', ...)
    local tables = {...}
    local result = {}

    for i=1,n do
        local t = tables[i]
        assert(type(tables[i]) == 'table')
        for _, v in pairs(t) do
            table.insert(result, v)
        end
    end
    return result
end

local gen_type_samples = {
        [t_unsigned]  = {"0", "1", "2"},
        [t_integer]   = {"-678", "-1", "0", "1", "2", "3", "678"},
        [t_double]    = {"0.0", "123.4", "-567.8"},
        [t_string]    = {"''", "'1'", "'123.4'", "'-1.5'", "'abc'", "'def'",
                        "'TRUE'", "'FALSE'", "'22222222-1111-1111-1111-111111111111'"},
        [t_boolean]   = {"false", "true", "null"},
        [t_varbinary] = {"X'312E3233'", "X'2D392E3837'", "X'302E30303031'",
                        "x'22222222111111111111111111111111'"},
        [t_uuid]      = {'uuid()'},
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

-- explicit
local function gen_explicit_cast_from_to(t_from, t_to)
    local queries = {}
    local from_exprs = gen_type_exprs(t_from)
    local to_typename = type_names[t_to]
    for _, expr in pairs(from_exprs) do
        table.insert(queries,
                     string.format([[ select cast(%s as %s); ]], expr, to_typename))
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

-- 1. Check explicit casts table
local function test_check_explicit_casts(test)
    -- checking validity of all `CAST(from AS to)` combinations
    test:plan(322)
    for _, from in ipairs(proper_order) do
        for _, to in ipairs(proper_order) do
            -- skip ANY, DECIMAL, UUID, etc.
            if enabled_type[from] and enabled_type_cast[to] then
                local gen = gen_explicit_cast_from_to(from, to)
                local failures = {}
                local successes = {}
                local castable = false
                local expected = explicit_casts[from][to]

                if verbose > 0 then
                    print(expected, yaml.encode(gen))
                end

                for _, v in pairs(gen) do
                    local ok, result
                    ok, result = catch_query(v)

                    if verbose > 0 then
                        print(string.format("V> ok = %s, result = %s, query = %s",
                            ok, result, v))
                    end

                    local title  = string.format("%s => %s", v, human_cast(expected))
                    if expected == c_yes then
                        test:ok(true == ok, label_for(from, to, title))
                    elseif expected == c_no then
                        test:ok(false == ok, label_for(from, to, title))
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
                        local title  = string.format("%s => %s",
                                                    #gen and gen[1]..'...' or '',
                                                    human_cast(expected))
                        test:ok(castable, label_for(from, to, title),
                                failures)
                end
            end
        end
    end
end

local table_name = 'TCASTS'

local function _created_formatted_space(name)
    local space = box.schema.space.create(name)
    space:create_index('pk', {sequence = true})
    local format = {{name = 'ID', type = 'unsigned', is_nullable = false}}
    for _, type_id in ipairs(proper_order) do
        if enabled_type[type_id] then
            local type_name = type_names[type_id]
            table.insert(format, {name = type_name, type = type_name, is_nullable = true})
        end
    end
    if #format > 0 then
        space:format(format)
    end
    return space
end

local function _cleanup_space(space)
    space:drop()
end

-- implicit
local function gen_implicit_insert_from_to(table_name, from, to)
    local queries = {}
    local from_exprs = gen_type_exprs(from)
    for _, from_e in pairs(from_exprs) do
        table.insert(queries,
                        string.format([[ insert into %s("%s") values(%s); ]],
                                      table_name, type_names[to], from_e))
    end
    return queries
end


-- 2. Check implicit casts table
local function test_check_implicit_casts(test)
    test:plan(186)
    local space = _created_formatted_space(table_name)
    -- checking validity of all `from binop to` combinations
    for _, from in ipairs(proper_order) do
        for _, to in ipairs(proper_order) do
            -- skip ANY, DECIMAL, UUID, etc.
            if enabled_type[from] and enabled_type[to] then
                local gen = gen_implicit_insert_from_to(table_name, from, to)
                local failures = {}
                local successes = {}
                local castable = false
                local expected = implicit_casts[from][to]

                if verbose > 0 then
                    print(expected, yaml.encode(gen))
                end

                for _, v in pairs(gen) do
                    local ok, result
                    ok, result = catch_query(v)

                    if verbose > 0 then
                        print(string.format("V> ok = %s, result = %s, query = %s",
                            ok, result, v))
                    end

                    local title  = string.format("%s => %s", v, human_cast(expected))
                    if expected == c_yes then
                        test:ok(true == ok, label_for(from, to, title))
                    elseif expected == c_no then
                        test:ok(false == ok, label_for(from, to, title))
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
                        local title  = string.format("%s => %s",
                                                    #gen and gen[1]..'...' or '',
                                                    human_cast(expected))
                        test:ok(castable, label_for(from, to, title),
                                failures)
                end
            end
        end
    end
    _cleanup_space(space)
end

test:test("e_casts - check consistency of implicit conversion table", test_check_table_consistency)
test:test("e_casts - check explicit casts", test_check_explicit_casts)
test:test("e_casts - check implicit casts", test_check_implicit_casts)

test:check()
os.exit()
