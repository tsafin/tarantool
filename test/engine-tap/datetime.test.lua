#!/usr/bin/env tarantool

local test = require('tester')
local date = require('datetime')

local engine = test:engine()

test:plan(1)
test:test("Simple engines tests for datetime indices", function(test)
    test:plan(23)
    local T = box.schema.space.create('T', {engine = engine})
    T:create_index('pk', {parts={1,'datetime'}})

    T:insert{date('1970-01-01')}
    T:insert{date('1970-01-02')}
    T:insert{date('1970-01-03')}
    T:insert{date('2000-01-01')}

    local o = box.space.T:select{}
    test:is(tostring(o[1][1]), '1970-01-01T00:00:00Z')
    test:is(tostring(o[2][1]), '1970-01-02T00:00:00Z')
    test:is(tostring(o[3][1]), '1970-01-03T00:00:00Z')
    test:is(tostring(o[4][1]), '2000-01-01T00:00:00Z')

    for _ = 1,16 do
        T:insert{date.now()}
    end

    local a = T:select{}
    for i = 1, #a - 1 do
        test:ok(a[i][1] < a[i + 1][1], ('%s < %s'):format(a[i][1], a[i + 1][1]))
    end

    T:drop()
end)

os.exit(test:check() and 0 or 1)
