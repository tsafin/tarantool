#!/usr/bin/env tarantool

local tap = require('tap')
local test = tap.test("errno")
local date = require('datetime')

test:plan(12)

local function assert_raises(test, error_msg, func, ...)
    local ok, err = pcall(func, ...)
    local err_tail = err:gsub("^.+:%d+: ", "")
    return test:ok(not ok and err_tail == error_msg,
                   ('"%s" received, "%s" expected'):format(err_tail, error_msg))
end

test:test("Default date creation", function(test)
    test:plan(9)
    -- check empty arguments
    local T1 = date.new()
    test:is(T1.epoch, 0, "T.epoch ==0")
    test:is(T1.nsec, 0, "T.nsec == 0")
    test:is(T1.tzoffset, 0, "T.tzoffset == 0")
    test:is(tostring(T1), "1970-01-01T00:00:00Z", "tostring(T1)")
    -- check empty table
    local T2 = date.new{}
    test:is(T2.epoch, 0, "T.epoch ==0")
    test:is(T2.nsec, 0, "T.nsec == 0")
    test:is(T2.tzoffset, 0, "T.tzoffset == 0")
    test:is(tostring(T2), "1970-01-01T00:00:00Z", "tostring(T2)")
    -- check their equivalence
    test:is(T1, T2, "T1 == T2")
end)

test:test("Simple tests for parser", function(test)
    test:plan(4)
    test:ok(date("1970-01-01T01:00:00Z") ==
            date {year=1970, mon=1, day=1, hour=1, min=0, sec=0})
    test:ok(date("1970-01-01T02:00:00+02:00") ==
            date {year=1970, mon=1, day=1, hour=2, min=0, sec=0, tzoffset=120})

    test:ok(date("1970-01-01T02:00:00Z") <
            date {year=1970, mon=1, day=1, hour=2, min=0, sec=1})
    test:ok(date("1970-01-01T02:00:00Z") <=
            date {year=1970, mon=1, day=1, hour=2, min=0, sec=0})
end)

test:test("Multiple tests for parser (with nanoseconds)", function(test)
    test:plan(193)
    -- borrowed from p5-time-moments/t/180_from_string.t
    local tests =
    {
        {'1970-01-01T00:00:00Z',               0,         0,    0, 1},
        {'1970-01-01T02:00:00+02:00',          0,         0,  120, 1},
        {'1970-01-01T01:30:00+01:30',          0,         0,   90, 1},
        {'1970-01-01T01:00:00+01:00',          0,         0,   60, 1},
        {'1970-01-01T00:01:00+00:01',          0,         0,    1, 1},
        {'1970-01-01T00:00:00Z',               0,         0,    0, 1},
        {'1969-12-31T23:59:00-00:01',          0,         0,   -1, 1},
        {'1969-12-31T23:00:00-01:00',          0,         0,  -60, 1},
        {'1969-12-31T22:30:00-01:30',          0,         0,  -90, 1},
        {'1969-12-31T22:00:00-02:00',          0,         0, -120, 1},
        {'1970-01-01T00:00:00.123456789Z',     0, 123456789,    0, 1},
        {'1970-01-01T00:00:00.12345678Z',      0, 123456780,    0, 0},
        {'1970-01-01T00:00:00.1234567Z',       0, 123456700,    0, 0},
        {'1970-01-01T00:00:00.123456Z',        0, 123456000,    0, 1},
        {'1970-01-01T00:00:00.12345Z',         0, 123450000,    0, 0},
        {'1970-01-01T00:00:00.1234Z',          0, 123400000,    0, 0},
        {'1970-01-01T00:00:00.123Z',           0, 123000000,    0, 1},
        {'1970-01-01T00:00:00.12Z',            0, 120000000,    0, 0},
        {'1970-01-01T00:00:00.1Z',             0, 100000000,    0, 0},
        {'1970-01-01T00:00:00.01Z',            0,  10000000,    0, 0},
        {'1970-01-01T00:00:00.001Z',           0,   1000000,    0, 1},
        {'1970-01-01T00:00:00.0001Z',          0,    100000,    0, 0},
        {'1970-01-01T00:00:00.00001Z',         0,     10000,    0, 0},
        {'1970-01-01T00:00:00.000001Z',        0,      1000,    0, 1},
        {'1970-01-01T00:00:00.0000001Z',       0,       100,    0, 0},
        {'1970-01-01T00:00:00.00000001Z',      0,        10,    0, 0},
        {'1970-01-01T00:00:00.000000001Z',     0,         1,    0, 1},
        {'1970-01-01T00:00:00.000000009Z',     0,         9,    0, 1},
        {'1970-01-01T00:00:00.00000009Z',      0,        90,    0, 0},
        {'1970-01-01T00:00:00.0000009Z',       0,       900,    0, 0},
        {'1970-01-01T00:00:00.000009Z',        0,      9000,    0, 1},
        {'1970-01-01T00:00:00.00009Z',         0,     90000,    0, 0},
        {'1970-01-01T00:00:00.0009Z',          0,    900000,    0, 0},
        {'1970-01-01T00:00:00.009Z',           0,   9000000,    0, 1},
        {'1970-01-01T00:00:00.09Z',            0,  90000000,    0, 0},
        {'1970-01-01T00:00:00.9Z',             0, 900000000,    0, 0},
        {'1970-01-01T00:00:00.99Z',            0, 990000000,    0, 0},
        {'1970-01-01T00:00:00.999Z',           0, 999000000,    0, 1},
        {'1970-01-01T00:00:00.9999Z',          0, 999900000,    0, 0},
        {'1970-01-01T00:00:00.99999Z',         0, 999990000,    0, 0},
        {'1970-01-01T00:00:00.999999Z',        0, 999999000,    0, 1},
        {'1970-01-01T00:00:00.9999999Z',       0, 999999900,    0, 0},
        {'1970-01-01T00:00:00.99999999Z',      0, 999999990,    0, 0},
        {'1970-01-01T00:00:00.999999999Z',     0, 999999999,    0, 1},
        {'1970-01-01T00:00:00.0Z',             0,         0,    0, 0},
        {'1970-01-01T00:00:00.00Z',            0,         0,    0, 0},
        {'1970-01-01T00:00:00.000Z',           0,         0,    0, 0},
        {'1970-01-01T00:00:00.0000Z',          0,         0,    0, 0},
        {'1970-01-01T00:00:00.00000Z',         0,         0,    0, 0},
        {'1970-01-01T00:00:00.000000Z',        0,         0,    0, 0},
        {'1970-01-01T00:00:00.0000000Z',       0,         0,    0, 0},
        {'1970-01-01T00:00:00.00000000Z',      0,         0,    0, 0},
        {'1970-01-01T00:00:00.000000000Z',     0,         0,    0, 0},
        {'1973-11-29T21:33:09Z',       123456789,         0,    0, 1},
        {'2013-10-28T17:51:56Z',      1382982716,         0,    0, 1},
        {'9999-12-31T23:59:59Z',    253402300799,         0,    0, 1},
    }
    for _, value in ipairs(tests) do
        local str, epoch, nsec, tzoffset, check
        str, epoch, nsec, tzoffset, check = unpack(value)
        local dt = date(str)
        test:is(dt.epoch, epoch, ('%s: dt.epoch == %d'):format(str, epoch))
        test:is(dt.nsec, nsec, ('%s: dt.nsec == %d'):format(str, nsec))
        test:is(dt.tzoffset, tzoffset, ('%s: dt.tzoffset == %d'):format(str, tzoffset))
        if check > 0 then
            test:is(str, tostring(dt), ('%s == tostring(%s)'):
                    format(str, tostring(dt)))
        end
    end
end)

test:test("Datetime string formatting", function(test)
    test:plan(6)
    local str = "1970-01-01"
    local t = date(str)
    test:is(t.epoch, 0, ('%s: t.epoch == %d'):format(str, tonumber(t.epoch)))
    test:is(t.nsec, 0, ('%s: t.nsec == %d'):format(str, t.nsec))
    test:is(t.tzoffset, 0, ('%s: t.tzoffset == %d'):format(str, t.tzoffset))
    test:is(date.strftime('%d/%m/%Y', t), '01/01/1970', ('%s: strftime #1'):format(str))
    test:is(date.strftime('%A %d. %B %Y', t), 'Thursday 01. January 1970', ('%s: strftime #2'):format(str))
    test:is(date.strftime('%FT%T%z', t), '1970-01-01T00:00:00+0000', ('%s: strftime #3'):format(str))
end)

test:test("Parse iso date - valid strings", function(test)
    test:plan(32)
    local good = {
        {2012, 12, 24, "20121224",                   8 },
        {2012, 12, 24, "20121224  Foo bar",          8 },
        {2012, 12, 24, "2012-12-24",                10 },
        {2012, 12, 24, "2012-12-24 23:59:59",       10 },
        {2012, 12, 24, "2012-12-24T00:00:00+00:00", 10 },
        {2012, 12, 24, "2012359",                    7 },
        {2012, 12, 24, "2012359T235959+0130",        7 },
        {2012, 12, 24, "2012-359",                   8 },
        {2012, 12, 24, "2012W521",                   8 },
        {2012, 12, 24, "2012-W52-1",                10 },
        {2012, 12, 24, "2012Q485",                   8 },
        {2012, 12, 24, "2012-Q4-85",                10 },
        {   1,  1,  1, "0001-Q1-01",                10 },
        {   1,  1,  1, "0001-W01-1",                10 },
        {   1,  1,  1, "0001-01-01",                10 },
        {   1,  1,  1, "0001-001",                   8 },
    }

    for _, value in ipairs(good) do
        local year, month, day, str, date_part_len
        year, month, day, str, date_part_len = unpack(value)
        local expected_date = date{year = year, month = month, day = day}
        local date_part, len
        date_part, len = date.parse_date(str)
        test:is(len, date_part_len, ('%s: length check %d'):format(str, len))
        test:is(expected_date, date_part, ('%s: expected date'):format(str))
    end
end)

local function invalid_date_fmt_error(str)
    return ('invalid date format %s'):format(str)
end

test:test("Parse iso date - invalid strings", function(test)
    test:plan(31)
    local bad = {
        "20121232"   , -- Invalid day of month
        "2012-12-310", -- Invalid day of month
        "2012-13-24" , -- Invalid month
        "2012367"    , -- Invalid day of year
        "2012-000"   , -- Invalid day of year
        "2012W533"   , -- Invalid week of year
        "2012-W52-8" , -- Invalid day of week
        "2012Q495"   , -- Invalid day of quarter
        "2012-Q5-85" , -- Invalid quarter
        "20123670"   , -- Trailing digit
        "201212320"  , -- Trailing digit
        "2012-12"    , -- Reduced accuracy
        "2012-Q4"    , -- Reduced accuracy
        "2012-Q42"   , -- Invalid
        "2012-Q1-1"  , -- Invalid day of quarter
        "2012Q--420" , -- Invalid
        "2012-Q-420" , -- Invalid
        "2012Q11"    , -- Incomplete
        "2012Q1234"  , -- Trailing digit
        "2012W12"    , -- Incomplete
        "2012W1234"  , -- Trailing digit
        "2012W-123"  , -- Invalid
        "2012-W12"   , -- Incomplete
        "2012-W12-12", -- Trailing digit
        "2012U1234"  , -- Invalid
        "2012-1234"  , -- Invalid
        "2012-X1234" , -- Invalid
        "0000-Q1-01" , -- Year less than 0001
        "0000-W01-1" , -- Year less than 0001
        "0000-01-01" , -- Year less than 0001
        "0000-001"   , -- Year less than 0001
    }

    for _, str in ipairs(bad) do
        assert_raises(test, invalid_date_fmt_error(str),
                      function() date.parse_date(str) end)
    end
end)

test:test("Parse tiny date into seconds and other parts", function(test)
    test:plan(4)
    local str = '19700101 00:00:30.528'
    local tiny = date(str)
    test:is(tiny.epoch, 30, ("epoch of '%s'"):format(str))
    test:is(tiny.nsec, 528000000, ("nsec of '%s'"):format(str))
    test:is(tiny:second(), 30, "second")
    test:is(tiny:timestamp(), 30.528, "timestamp")
end)

test:test("totable{}", function(test)
    test:plan(9)
    local exp = {sec = 0, min = 0, wday = 5, day = 1,
                 nsec = 0, isdst = false, yday = 1,
                 tzoffset = 0, month = 1, year = 1970, hour = 0}
    local T = date.new()
    local TT = T:totable()
    test:is_deeply(TT, exp, "date:totable()")

    local D = os.date('*t')
    TT = date.new(D):totable()
    local keys = {
        'sec', 'min', 'wday', 'day', 'yday', 'month', 'year', 'hour'
    }
    for _, key in pairs(keys) do
        test:is(TT[key], D[key], ("[%s]: %s == %s"):format(key, TT[key], D[key]))
    end
end)

test:test("Time :set{} operations", function(test)
    test:plan(8)

    local T = date.new{ year = 2021, month = 8, day = 31,
                  hour = 0, min = 31, sec = 11, tzoffset = '+0300'}
    test:is(tostring(T), '2021-08-31T00:31:11+03:00', 'initial')
    test:is(tostring(T:set{ year = 2020 }), '2020-08-31T00:31:11+03:00', '2020 year')
    test:is(tostring(T:set{ month = 11, day = 30 }), '2020-11-30T00:31:11+03:00', 'month = 11, day = 30')
    test:is(tostring(T:set{ day = 9 }), '2020-11-09T00:31:11+03:00', 'day 9')
    test:is(tostring(T:set{ hour = 6 }),  '2020-11-09T06:31:11+03:00', 'hour 6')
    test:is(tostring(T:set{ min = 12, sec = 23 }), '2020-11-09T04:12:23+03:00', 'min 12, sec 23')
    test:is(tostring(T:set{ tzoffset = -8*60 }), '2020-11-08T17:12:23-08:00', 'offset -0800' )
    test:is(tostring(T:set{ tzoffset = '+0800' }), '2020-11-09T09:12:23+08:00', 'offset +0800' )
end)

local function range_check_error(name, value, range)
    return ('value %s of %s is out of allowed range [%d, %d]'):
              format(value, name, range[1], range[2])
end

local function range_check_3_error(v)
    return ('value %d of %s is out of allowed range [%d, %d..%d]'):
            format(v, 'day', -1, 1, 31)
end

test:test("Time invalid :set{} operations", function(test)
    test:plan(17)

    local T = date.new{}

    assert_raises(test, range_check_error('year', 10000, {1, 9999}),
                  function() T:set{ year = 10000} end)
    assert_raises(test, range_check_error('year', -10, {1, 9999}),
                  function() T:set{ year = -10} end)

    assert_raises(test, range_check_error('month', 20, {1, 12}),
                  function() T:set{ month = 20} end)
    assert_raises(test, range_check_error('month', 0, {1, 12}),
                  function() T:set{ month = 0} end)
    assert_raises(test, range_check_error('month', -20, {1, 12}),
                  function() T:set{ month = -20} end)

    assert_raises(test,  range_check_3_error(40),
                  function() T:set{ day = 40} end)
    assert_raises(test,  range_check_3_error(0),
                  function() T:set{ day = 0} end)
    assert_raises(test,  range_check_3_error(-10),
                  function() T:set{ day = -10} end)

    assert_raises(test,  range_check_error('hour', 31, {0, 23}),
                  function() T:set{ hour = 31} end)
    assert_raises(test,  range_check_error('hour', -1, {0, 23}),
                  function() T:set{ hour = -1} end)

    assert_raises(test,  range_check_error('min', 60, {0, 59}),
                  function() T:set{ min = 60} end)
    assert_raises(test,  range_check_error('min', -1, {0, 59}),
                  function() T:set{ min = -1} end)

    assert_raises(test,  range_check_error('sec', 61, {0, 60}),
                  function() T:set{ sec = 61} end)
    assert_raises(test,  range_check_error('sec', -1, {0, 60}),
                  function() T:set{ sec = -1} end)

    local only1 = 'only one of nsec, usec or msecs may defined simultaneously'
    assert_raises(test, only1, function()
                    T:set{ nsec = 123456, usec = 123}
                  end)
    assert_raises(test, only1, function()
                    T:set{ nsec = 123456, msec = 123}
                  end)
    assert_raises(test, only1, function()
                    T:set{ nsec = 123456, usec = 1234, msec = 123}
                  end)
end)

local function invalid_tz_fmt_error(val)
    return ('invalid time-zone format %s'):format(val)
end

test:test("Time invalid tzoffset in :set{} operations", function(test)
    test:plan(10)

    local T = date.new{}
    local bad_strings = {
        'bogus',
        '0100',
        '+-0100',
        '+25:00',
        '+99:00',
        '-99:00',
    }
    for _, val in ipairs(bad_strings) do
        assert_raises(test, invalid_tz_fmt_error(val),
                      function() T:set{ tzoffset = val } end)
    end

    local bad_numbers = {
        800,
        -800,
        10000,
        -10000,
    }
    for _, val in ipairs(bad_numbers) do
        assert_raises(test, range_check_error('tzoffset', val, {-720, 720}),
                      function() T:set{ tzoffset = val } end)
    end
end)


test:test("Time :set{day = -1} operations", function(test)
    test:plan(14)
    local tests = {
        {{ year = 2000, month = 3, day = -1}, '2000-03-31T00:00:00Z'},
        {{ year = 2000, month = 2, day = -1}, '2000-02-29T00:00:00Z'},
        {{ year = 2001, month = 2, day = -1}, '2001-02-28T00:00:00Z'},
        {{ year = 1900, month = 2, day = -1}, '1900-02-28T00:00:00Z'},
        {{ year = 1904, month = 2, day = -1}, '1904-02-29T00:00:00Z'},
    }
    local T
    for _, row in ipairs(tests) do
        local args, str = unpack(row)
        T = date.new(args)
        test:is(tostring(T), str, ('checking -1 with %s'):format(str))
    end
    assert_raises(test, range_check_3_error(0), function() T = date.new{day = 0} end)
    assert_raises(test, range_check_3_error(-2), function() T = date.new{day = -2} end)
    assert_raises(test, range_check_3_error(-10), function() T = date.new{day = -10} end)

    T = date.new{ year = 1904, month = 2, day = -1 }
    test:is(tostring(T), '1904-02-29T00:00:00Z', 'base before :set{}')
    test:is(tostring(T:set{month = 3, day = 2}), '1904-03-02T00:00:00Z', '2 March')
    test:is(tostring(T:set{day = -1}), '1904-03-31T00:00:00Z', '31 March')

    assert_raises(test, range_check_3_error(0), function() T:set{day = 0} end)
    assert_raises(test, range_check_3_error(-2), function() T:set{day = -2} end)
    assert_raises(test, range_check_3_error(-10), function() T:set{day = -10} end)
end)

os.exit(test:check() and 0 or 1)
