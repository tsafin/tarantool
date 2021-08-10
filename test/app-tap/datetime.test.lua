#!/usr/bin/env tarantool

local tap = require('tap')
local test = tap.test("errno")
local date = require('datetime')
local ffi = require('ffi')


test:plan(10)

test:test("Simple tests for parser", function(test)
    test:plan(2)
    test:ok(date("1970-01-01T01:00:00Z") ==
            date {year=1970, month=1, day=1, hour=1, minute=0, second=0})
    test:ok(date("1970-01-01T02:00:00+02:00") ==
            date {year=1970, month=1, day=1, hour=2, minute=0, second=0, tz=120})
end)

test:test("Multiple tests for parser (with nanoseconds)", function(test)
    test:plan(193)
    -- borrowed from p5-time-moments/t/180_from_string.t
    local tests =
    {
        {'1970-01-01T00:00Z',                  0,         0,    0, 1},
        {'1970-01-01T02:00+02:00',             0,         0,  120, 1},
        {'1970-01-01T01:30+01:30',             0,         0,   90, 1},
        {'1970-01-01T01:00+01:00',             0,         0,   60, 1},
        {'1970-01-01T00:01+00:01',             0,         0,    1, 1},
        {'1970-01-01T00:00Z',                  0,         0,    0, 1},
        {'1969-12-31T23:59-00:01',             0,         0,   -1, 1},
        {'1969-12-31T23:00-01:00',             0,         0,  -60, 1},
        {'1969-12-31T22:30-01:30',             0,         0,  -90, 1},
        {'1969-12-31T22:00-02:00',             0,         0, -120, 1},
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
        local str, epoch, nsec, offset, check
        str, epoch, nsec, offset, check = unpack(value)
        local dt = date(str)
        test:ok(dt.secs == epoch, ('%s: dt.secs == %d'):format(str, epoch))
        test:ok(dt.nsec == nsec, ('%s: dt.nsec == %d'):format(str, nsec))
        test:ok(dt.offset == offset, ('%s: dt.offset == %d'):format(str, offset))
        if check > 0 then
            test:ok(str == tostring(dt), ('%s == tostring(%s)'):
                    format(str, tostring(dt)))
        end
    end
end)

ffi.cdef [[
    void tzset(void);
]]

test:test("Datetime string formatting", function(test)
    test:plan(7)
    local str = "1970-01-01"
    local t = date(str)
    test:ok(t.secs == 0, ('%s: t.secs == %d'):format(str, tonumber(t.secs)))
    test:ok(t.nsec == 0, ('%s: t.nsec == %d'):format(str, t.nsec))
    test:ok(t.offset == 0, ('%s: t.offset == %d'):format(str, t.offset))
    test:ok(date.asctime(t) == 'Thu Jan  1 00:00:00 1970\n', ('%s: asctime'):format(str))
    -- ctime() is local timezone dependent. To make sure that
    -- test is deterministic we enforce timezone via TZ environment
    -- manipulations and calling tzset()

    -- redefine timezone to be always GMT-2
    os.setenv('TZ', 'GMT-2')
    ffi.C.tzset()
    test:ok(date.ctime(t) == 'Thu Jan  1 02:00:00 1970\n', ('%s: ctime with timezone'):format(str))
    test:ok(date.strftime('%d/%m/%Y', t) == '01/01/1970', ('%s: strftime #1'):format(str))
    test:ok(date.strftime('%A %d. %B %Y', t) == 'Thursday 01. January 1970', ('%s: strftime #2'):format(str))
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
        test:ok(len == date_part_len, ('%s: length check %d'):format(str, len))
        test:ok(expected_date == date_part, ('%s: expected date'):format(str))
    end
end)

test:test("Parse iso date - invalid strings", function(test)
    test:plan(62)
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
        local date_part, len
        date_part, len = date.parse_date(str)
        test:ok(len == 0, ('%s: length check %d'):format(str, len))
        test:ok(date_part == nil, ('%s: empty date check %s'):format(str, date_part))
    end
end)

test:test("Parse tiny date into seconds and other parts", function(test)
    test:plan(9)
    local str = '19700101 00:00:30.528'
    local tiny = date(str)
    test:ok(tiny.secs == 30, ("secs of '%s'"):format(str))
    test:ok(tiny.nsec == 528000000, ("nsec of '%s'"):format(str))
    test:ok(tiny.nanoseconds == 30528000000, "nanoseconds")
    test:ok(tiny.microseconds == 30528000, "microseconds")
    test:ok(tiny.milliseconds == 30528, "milliseconds")
    test:ok(tiny.seconds == 30.528, "seconds")
    test:ok(tiny.timestamp == 30.528, "timestamp")
    test:ok(tiny.minutes == 0.5088, "minutes")
    test:ok(tiny.hours == 0.00848, "hours")
end)

test:test("Stringization of dates and intervals", function(test)
    test:plan(13)
    local str = '19700101Z'
    local dt = date(str)
    test:ok(tostring(dt) == '1970-01-01T00:00Z', ('tostring(%s)'):format(str))
    test:ok(tostring(date.seconds(12)) == '+12 secs', '+12 seconds')
    test:ok(tostring(date.seconds(-12)) == '-12 secs', '-12 seconds')
    test:ok(tostring(date.minutes(12)) == '+12 minutes, 0 seconds', '+12 minutes')
    test:ok(tostring(date.minutes(-12)) == '-12 minutes, 0 seconds', '-12 minutes')
    test:ok(tostring(date.hours(12)) == '+12 hours, 0 minutes, 0 seconds',
            '+12 hours')
    test:ok(tostring(date.hours(-12)) == '-12 hours, 0 minutes, 0 seconds',
            '-12 hours')
    test:ok(tostring(date.days(12)) == '+12 days, 0 hours, 0 minutes, 0 seconds',
            '+12 days')
    test:ok(tostring(date.days(-12)) == '-12 days, 0 hours, 0 minutes, 0 seconds',
            '-12 days')
    test:ok(tostring(date.months(5)) == '+5 months', '+5 months')
    test:ok(tostring(date.months(-5)) == '-5 months', '-5 months')
    test:ok(tostring(date.years(4)) == '+4 years', '+4 years')
    test:ok(tostring(date.years(-4)) == '-4 years', '-4 years')
end)

test:test("Time interval operations", function(test)
    test:plan(12)

    -- check arithmetic with leap dates
    local T = date('1972-02-29')
    local M = date.months(2)
    local Y = date.years(1)
    test:ok(tostring(T + M) == '1972-04-29T00:00Z', ('T(%s) + M(%s'):format(T, M))
    test:ok(tostring(T + Y) == '1973-03-01T00:00Z', ('T(%s) + Y(%s'):format(T, Y))
    test:ok(tostring(T + M + Y) == '1973-04-30T00:00Z',
            ('T(%s) + M(%s) + Y(%s'):format(T, M, Y))
    test:ok(tostring(T + Y + M) == '1973-05-01T00:00Z',
            ('T(%s) + M(%s) + Y(%s'):format(T, M, Y))
    test:ok(tostring(T:add{years = 1, months = 2}) == '1973-04-30T00:00Z',
            ('T:add{years=1,months=2}(%s)'):format(T))

    -- check average, not leap dates
    T = date('1970-01-08')
    test:ok(tostring(T + M) == '1970-03-08T00:00Z', ('T(%s) + M(%s'):format(T, M))
    test:ok(tostring(T + Y) == '1971-01-08T00:00Z', ('T(%s) + Y(%s'):format(T, Y))
    test:ok(tostring(T + M + Y) == '1971-03-08T00:00Z',
            ('T(%s) + M(%s) + Y(%s'):format(T, M, Y))
    test:ok(tostring(T + Y + M) == '1971-03-08T00:00Z',
            ('T(%s) + Y(%s) + M(%s'):format(T, Y, M))
    test:ok(tostring(T:add{years = 1, months = 2}) == '1971-03-08T00:00Z',
            ('T:add{years=1,months=2}(%s)'):format(T))


    -- subtraction of 2 dates
    local T2 = date('19700103')
    local T1 = date('1970-01-01')
    test:ok(tostring(T2 - T1) == '+2 days, 0 hours, 0 minutes, 0 seconds',
            ('T2(%s) - T1(%s'):format(T2, T1))
    test:ok(tostring(T1 - T2) == '-2 days, 0 hours, 0 minutes, 0 seconds',
            ('T2(%s) - T1(%s'):format(T2, T1))
end)

local function catchadd(A, B)
    return pcall(function() return A + B end)
end

--[[
Matrix of addition operands eligibility and their result type

|                 |  datetime | interval | interval_months | interval_years |
+-----------------+-----------+----------+-----------------+----------------+
| datetime        |  datetime | datetime | datetime        | datetime       |
| interval        |  datetime | interval |                 |                |
| interval_months |  datetime |          | interval_months |                |
| interval_years  |  datetime |          |                 | interval_years |
]]

test:test("Matrix of allowed time and interval additions", function(test)
    test:plan(20)

    -- check arithmetic with leap dates
    local T1970 = date('1970-01-01')
    local T2000 = date('2000-01-01')
    local I1 = date.days(1)
    local M2 = date.months(2)
    local M10 = date.months(10)
    local Y1 = date.years(1)
    local Y5 = date.years(5)

    test:ok(catchadd(T1970, I1) == true, "status: T + I")
    test:ok(catchadd(T1970, M2) == true, "status: T + M")
    test:ok(catchadd(T1970, Y1) == true, "status: T + Y")
    test:ok(catchadd(T1970, T2000) == false, "status: T + T")
    test:ok(catchadd(I1, T1970) == true, "status: I + T")
    test:ok(catchadd(M2, T1970) == true, "status: M + T")
    test:ok(catchadd(Y1, T1970) == true, "status: Y + T")
    test:ok(catchadd(I1, Y1) == false, "status: I + Y")
    test:ok(catchadd(M2, Y1) == false, "status: M + Y")
    test:ok(catchadd(I1, Y1) == false, "status: I + Y")
    test:ok(catchadd(Y5, M10) == false, "status: Y + M")
    test:ok(catchadd(Y5, I1) == false, "status: Y + I")
    test:ok(catchadd(Y5, Y1) == true, "status: Y + Y")

    test:ok(tostring(T1970 + I1) == "1970-01-02T00:00Z", "value: T + I")
    test:ok(tostring(T1970 + M2) == "1970-03-01T00:00Z", "value: T + M")
    test:ok(tostring(T1970 + Y1) == "1971-01-01T00:00Z", "value: T + Y")
    test:ok(tostring(I1 + T1970) == "1970-01-02T00:00Z", "value: I + T")
    test:ok(tostring(M2 + T1970) == "1970-03-01T00:00Z", "value: M + T")
    test:ok(tostring(Y1 + T1970) == "1971-01-01T00:00Z", "value: Y + T")
    test:ok(tostring(Y5 + Y1) == "+6 years", "Y + Y")

end)

local function catchsub_status(A, B)
    return pcall(function() return A - B end)
end

--[[
Matrix of subtraction operands eligibility and their result type

|                 |  datetime | interval | interval_months | interval_years |
+-----------------+-----------+----------+-----------------+----------------+
| datetime        |  interval | datetime | datetime        | datetime       |
| interval        |           | interval |                 |                |
| interval_months |           |          | interval_months |                |
| interval_years  |           |          |                 | interval_years |
]]
test:test("Matrix of allowed time and interval subtractions", function(test)
    test:plan(18)

    -- check arithmetic with leap dates
    local T1970 = date('1970-01-01')
    local T2000 = date('2000-01-01')
    local I1 = date.days(1)
    local M2 = date.months(2)
    local M10 = date.months(10)
    local Y1 = date.years(1)
    local Y5 = date.years(5)

    test:ok(catchsub_status(T1970, I1) == true, "status: T - I")
    test:ok(catchsub_status(T1970, M2) == true, "status: T - M")
    test:ok(catchsub_status(T1970, Y1) == true, "status: T - Y")
    test:ok(catchsub_status(T1970, T2000) == true, "status: T - T")
    test:ok(catchsub_status(I1, T1970) == false, "status: I + T")
    test:ok(catchsub_status(M2, T1970) == false, "status: M + T")
    test:ok(catchsub_status(Y1, T1970) == false, "status: Y + T")
    test:ok(catchsub_status(I1, Y1) == false, "status: I - Y")
    test:ok(catchsub_status(M2, Y1) == false, "status: M - Y")
    test:ok(catchsub_status(I1, Y1) == false, "status: I - Y")
    test:ok(catchsub_status(Y5, M10) == false, "status: Y - M")
    test:ok(catchsub_status(Y5, I1) == false, "status: Y - I")
    test:ok(catchsub_status(Y5, Y1) == true, "status: Y - Y")

    test:ok(tostring(T1970 - I1) == "1969-12-31T00:00Z", "value: T - I")
    test:ok(tostring(T1970 - M2) == "1969-11-01T00:00Z", "value: T - M")
    test:ok(tostring(T1970 - Y1) == "1969-01-01T00:00Z", "value: T - Y")
    test:ok(tostring(T1970 - T2000) == "-10957 days, 0 hours, 0 minutes, 0 seconds",
            "value: T - T")
    test:ok(tostring(Y5 - Y1) == "+4 years", "value: Y - Y")

end)

os.exit(test:check() and 0 or 1)
