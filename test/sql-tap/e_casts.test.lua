#!/usr/bin/env tarantool
local test = require("sqltester")
test:plan(100)

local ffi = require("ffi")

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
    t_array,
    t_map,
    t_scalar,
}
-- table of _TSV_ (tab separated values)
-- copied from sql-lua-tables-v4.xls // TNT implicit today
local implicit_casts_spec = {
    t_any =     [[Y	S	S	S	S	S	S	S			]],
    t_unsigned= [[Y	Y	Y	Y	Y			Y			Y]],
    t_string =  [[Y	S	Y	S	S			S			Y]],
    t_double =  [[Y	S	Y	Y	S			Y			Y]],
    t_integer = [[Y	S	Y	Y	Y			Y			Y]],
    t_boolean = [[Y					Y					Y]],
    t_varbinary=[[Y		Y				Y				Y]],
    t_number =  [[Y	S		Y	S			Y			Y]],
    t_decimal = [[]],
    t_uuid =    [[]],
    t_array =   [[Y								Y		N]],
    t_map =     [[Y									Y	N]],
    t_scalar =  [[Y	S	S	S	S	S	S	S	N	N	Y]],
}

yaml = require 'yaml'

local implicit_casts = {}
-- print(yaml.encode(implicit_casts))

for i_type, tsv in pairs(implicit_casts_spec) do
    local i = 1 -- first column
    local debug_line = ''
    implicit_casts[i_type] = {}
    -- split words by tab
    for word in (string.gmatch(tsv, "(.-)\t")) do
        implicit_casts[i_type][proper_order[i]] = word
        i = i + 1
    end
end
-- print(yaml.encode(implicit_casts))

function do_exec(...)
    local args = {...}
    local res, err = box.execute('select ?, ? ;', args)
    if err ~= nil then
        error(err)
    end
    print(yaml.encode(res))
end

pcall(do_exec, 1,2)
pcall(do_exec, 1,2,3)
pcall(do_exec, 1)

local literal_values_samples = {
    t_any =     {},
    t_unsigned= {0, 1, 2},
    t_string =  {"''", "'1'", "'abc'", "'def'"},
    t_double =  {0.0, 123.4, -567.8},
    t_integer = {-678, -1, 0, 1, 2, 3, 678},
    t_boolean = {false, true},
    t_varbinary = {},
    t_number =  {},
    t_decimal = {},
    t_uuid =    {},
    t_array =   {},
    t_map =     {},
    t_scalar =  {},
}
local expected_sql_type = {
    t_any = 'any',
    t_unsigned= 'unsigned',
    t_string =  'string',
    t_double =  'double',
    t_integer = 'integer',
    t_boolean = 'boolean',
    t_varbinary = '',
    t_number =  '',
    t_decimal = '',
    t_uuid =    '',
    t_array =   '',
    t_map =     '',
    t_scalar =  '',
}

for i_type, vals in pairs(literal_values_samples) do
    --print(vals)
    if #vals > 1 then
        for i, val in pairs(vals) do
            local title = string.format("e_casts.%s.%d", i_type, i)
            local query = string.format(" select typeof(%s)", val)
            test:do_execsql_test(title, query, {expected_sql_type[i_type]})
        end
    end
end

test:do_execsql_test(
    "e_casts-1.0", [[ select 1 < 2]], { true }
)

test:do_execsql_test(
    "e_casts-1.1", [[ select cast(1 as string)]], { "1" }
)

test:finish_test()
