local ffi = require('ffi')

--[[
    `c-dt` library functions handles properly both positive and negative `dt`
    values, where `dt` is a number of dates since Rata Die date (0001-01-01).

    For better compactness of our typical data in MessagePack stream we shift
    root of our time to the Unix Epoch date (1970-01-01), thus our 0 is
    actually dt = 719163.

    So here is a simple formula how convert our epoch-based seconds to dt values
        dt = (secs / 86400) + 719163
    Where 719163 is an offset of Unix Epoch (1970-01-01) since Rata Die
    (0001-01-01) in dates.
]]

-- dt_core.h definitions
ffi.cdef [[

typedef int dt_t;

dt_t   tnt_dt_from_rdn     (int n);
dt_t   tnt_dt_from_ymd     (int y, int m, int d);
int    tnt_dt_rdn          (dt_t dt);

]]

-- dt_arithmetic.h definitions
ffi.cdef [[

typedef enum {
    DT_EXCESS,
    DT_LIMIT,
    DT_SNAP
} dt_adjust_t;

dt_t   tnt_dt_add_years    (dt_t dt, int delta, dt_adjust_t adjust);
dt_t   tnt_dt_add_quarters (dt_t dt, int delta, dt_adjust_t adjust);
dt_t   tnt_dt_add_months   (dt_t dt, int delta, dt_adjust_t adjust);

]]

-- dt_parse_iso.h definitions
ffi.cdef [[

size_t tnt_dt_parse_iso_date (const char *str, size_t len, dt_t *dt);
size_t tnt_dt_parse_iso_time (const char *str, size_t len, int *sod, int *nsec);
size_t tnt_dt_parse_iso_zone_lenient(const char *str, size_t len, int *offset);

]]

-- Tarantool functions - datetime.c
ffi.cdef [[

int    datetime_to_string(const struct datetime * date, char *buf, int len);
char  *datetime_asctime(const struct datetime *date, char *buf);
char  *datetime_ctime(const struct datetime *date, char *buf);
size_t datetime_strftime(const struct datetime *date, const char *fmt, char *buf,
                         uint32_t len);
void   datetime_now(struct datetime *now);

]]

local builtin = ffi.C
local math_modf = math.modf
local math_floor = math.floor

local SECS_PER_DAY     = 86400
local NANOS_PER_SEC    = 1000000000

-- c-dt/dt_config.h

-- Unix, January 1, 1970, Thursday
local DT_EPOCH_1970_OFFSET = 719163


local datetime_t = ffi.typeof('struct datetime')
local interval_t = ffi.typeof('struct datetime_interval')

ffi.cdef [[
    struct interval_months {
        int m;
    };

    struct interval_years {
        int y;
    };
]]
local interval_months_t = ffi.typeof('struct interval_months')
local interval_years_t = ffi.typeof('struct interval_years')

local function is_interval(o)
    return ffi.istype(interval_t, o) or
           ffi.istype(interval_months_t, o) or
           ffi.istype(interval_years_t, o)
end

local function is_datetime(o)
    return ffi.istype(datetime_t, o)
end

local function is_date_interval(o)
    return is_datetime(o) or is_interval(o)
end

local function interval_new()
    local interval = ffi.new(interval_t)
    return interval
end

local function check_number(n, message)
    if type(n) ~= 'number' then
        return error(("%s: expected number, but received %s"):
                     format(message, n), 2)
    end
end

local function check_date(o, message)
    if not is_datetime(o) then
        return error(("%s: expected datetime, but received %s"):
                     format(message, o), 2)
    end
end

local function check_date_interval(o, message)
    if not is_datetime(o) and not is_interval(o) then
        return error(("%s: expected datetime or interval, but received %s"):
                     format(message, o), 2)
    end
end

local function check_interval(o, message)
    if not is_interval(o) then
        return error(("%s: expected interval, but received %s"):
                     format(message, o), 2)
    end
end

local function check_str(s, message)
    if not type(s) == 'string' then
        return error(("%s: expected string, but received %s"):
                     format(message, s), 2)
    end
end

local function check_range(v, range, txt)
    assert(#range == 2)
    if v < range[1] or v > range[2] then
        error(('value %d of %s is out of allowed range [%d, %d]'):
              format(v, txt, range[1], range[2]), 4)
    end
end

local function interval_years_new(y)
    check_number(y, "years(number)")
    local o = ffi.new(interval_years_t)
    o.y = y
    return o
end

local function interval_months_new(m)
    check_number(m, "months(number)")
    local o = ffi.new(interval_months_t)
    o.m = m
    return o
end

local function interval_weeks_new(w)
    check_number(w, "weeks(number)")
    local o = ffi.new(interval_t)
    o.secs = w * SECS_PER_DAY * 7
    return o
end

local function interval_days_new(d)
    check_number(d, "days(number)")
    local o = ffi.new(interval_t)
    o.secs = d * SECS_PER_DAY
    return o
end

local function interval_hours_new(h)
    check_number(h, "hours(number)")
    local o = ffi.new(interval_t)
    o.secs = h * 60 * 60
    return o
end

local function interval_minutes_new(m)
    check_number(m, "minutes(number)")
    local o = ffi.new(interval_t)
    o.secs = m * 60
    return o
end

local function interval_seconds_new(s)
    check_number(s, "seconds(number)")
    local o = ffi.new(interval_t)
    o.nsec = s % 1 * 1e9
    o.secs = s - (s % 1)
    return o
end

local SECS_EPOCH_OFFSET = (DT_EPOCH_1970_OFFSET * SECS_PER_DAY)

local function local_rd(secs)
    return math_floor((secs + SECS_EPOCH_OFFSET) / SECS_PER_DAY)
end

local function local_dt(secs)
    return builtin.tnt_dt_from_rdn(local_rd(secs))
end

local function normalize_nsec(secs, nsec)
    if nsec < 0 then
        secs = secs - 1
        nsec = nsec + NANOS_PER_SEC
    elseif nsec >= NANOS_PER_SEC then
        secs = secs + 1
        nsec = nsec - NANOS_PER_SEC
    end
    return secs, nsec
end

local function datetime_cmp(lhs, rhs)
    if not is_date_interval(lhs) or not is_date_interval(rhs) then
        return nil
    end
    local sdiff = lhs.secs - rhs.secs
    return sdiff ~= 0 and sdiff or (lhs.nsec - rhs.nsec)
end

local function datetime_eq(lhs, rhs)
    local rc = datetime_cmp(lhs, rhs)
    return rc ~= nil and rc == 0
end

local function datetime_lt(lhs, rhs)
    local rc = datetime_cmp(lhs, rhs)
    return rc == nil and error('incompatible types for comparison', 2) or
           rc < 0
end

local function datetime_le(lhs, rhs)
    local rc = datetime_cmp(lhs, rhs)
    return rc == nil and error('incompatible types for comparison', 2) or
           rc <= 0
end

local function datetime_serialize(self)
    return { secs = self.secs, nsec = self.nsec, offset = self.offset }
end

local function interval_serialize(self)
    return { secs = self.secs, nsec = self.nsec }
end

local function datetime_new_raw(secs, nsec, offset)
    local dt_obj = ffi.new(datetime_t)
    dt_obj.secs = secs
    dt_obj.nsec = nsec
    dt_obj.offset = offset
    return dt_obj
end

local function datetime_new_dt(dt, secs, fraction, offset)
    local epochV = dt ~= nil and (builtin.tnt_dt_rdn(dt) - DT_EPOCH_1970_OFFSET) *
                   SECS_PER_DAY or 0
    local secsV = secs or 0
    local fracV = fraction or 0
    local ofsV = offset or 0
    return datetime_new_raw(epochV + secsV - ofsV * 60, fracV, ofsV)
end

-- create datetime given attribute values from obj
-- in the "easy mode", providing builder with
-- .secs, .nsec, .offset
local function datetime_new_obj(obj, ...)
    if obj == nil or type(obj) ~= 'table' then
        return datetime_new_raw(obj, ...)
    end
    local secs = 0
    local nsec = 0
    local offset = 0

    for key, value in pairs(obj) do
        if key == 'secs' then
            secs = value
        elseif key == 'nsec' then
            nsec = value
        elseif key == 'offset' then
            offset = value
        else
            error(('unknown attribute %s'):format(key), 2)
        end
    end

    return datetime_new_raw(secs, nsec, offset)
end

-- create datetime given attribute values from obj
local function datetime_new(obj)
    if obj == nil or type(obj) ~= 'table' then
        return datetime_new_raw(0, 0, 0)
    end
    local y = 0
    local M = 0
    local d = 0
    local ymd = false

    local h = 0
    local m = 0
    local s = 0
    local nsec = 0
    local hms = false
    local offset = 0

    local dt = 0

    for key, value in pairs(obj) do
        if key == 'year' then
            check_range(value, {1, 9999}, key)
            y = value
            ymd = true
        elseif key == 'month' then
            check_range(value, {1, 12}, key)
            M = value
            ymd = true
        elseif key == 'day' then
            check_range(value, {1, 31}, key)
            d = value
            ymd = true
        elseif key == 'hour' then
            check_range(value, {0, 23}, key)
            h = value
            hms = true
        elseif key == 'min' or key == 'minute' then
            check_range(value, {0, 59}, key)
            m = value
            hms = true
        elseif key == 'sec' or key == 'second' then
            check_range(value, {0, 60}, key)
            s, nsec = math_modf(value)
            nsec = nsec * 1e9 -- convert fraction to nanoseconds
            hms = true
        elseif key == 'tz' then
            -- tz offset in minutes
            check_range(value, {0, 720}, key)
            offset = value
        elseif key == 'isdst' or key == 'wday' or
               key == 'yday' then -- luacheck: ignore 542
            -- ignore unused os.date attributes
        else
            error(('unknown attribute %s'):format(key), 2)
        end
    end

    -- .year, .month, .day
    if ymd then
        dt = builtin.tnt_dt_from_ymd(y, M, d)
    end

    -- .hour, .minute, .second
    local secs = 0
    if hms then
        secs = h * 3600 + m * 60 + s
    end

    return datetime_new_dt(dt, secs, nsec, offset)
end

--[[
    Convert to text datetime values

    - datetime will use ISO-8601 forat:
        1970-01-01T00:00Z
        2021-08-18T16:57:08.981725+03:00
]]
local function datetime_tostring(o)
    if ffi.typeof(o) == datetime_t then
        local sz = 48
        local buff = ffi.new('char[?]', sz)
        local len = builtin.datetime_to_string(o, buff, sz)
        assert(len < sz)
        return ffi.string(buff)
    end
end

--[[
    Convert to text interval values of different types

    - depending on a values stored there generic interval
      values may display in following format:
        +12 secs
        -23 minutes, 0 seconds
        +12 hours, 23 minutes, 1 seconds
        -7 days, 23 hours, 23 minutes, 1 seconds
    - years will be displayed as
        +10 years
    - months will be displayed as:
         +2 months
]]
local function interval_tostring(o)
    if ffi.typeof(o) == interval_years_t then
        return ('%+d years'):format(o.y)
    elseif ffi.typeof(o) == interval_months_t then
        return ('%+d months'):format(o.m)
    elseif ffi.typeof(o) == interval_t then
        local ts = o.timestamp
        local sign = '+'

        if ts < 0 then
            ts = -ts
            sign = '-'
        end

        if ts < 60 then
            return ('%s%s secs'):format(sign, ts)
        elseif ts < 60 * 60 then
            return ('%+d minutes, %s seconds'):format(o.minutes, ts % 60)
        elseif ts < 24 * 60 * 60 then
            return ('%+d hours, %d minutes, %s seconds'):format(
                    o.hours, o.minutes % 60, ts % 60)
        else
            return ('%+d days, %d hours, %d minutes, %s seconds'):format(
                    o.days, o.hours % 24, o.minutes % 60, ts % 60)
        end
    end
end

local function date_first(lhs, rhs)
    if is_datetime(lhs) then
        return lhs, rhs
    else
        return rhs, lhs
    end
end

local function error_incompatible(name)
    error(("datetime:%s() - incompatible type of arguments"):
          format(name), 3)
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
local function datetime_sub(lhs, rhs)
    check_date_interval(lhs, "operator -")
    local d, s = lhs, rhs
    local left_t = ffi.typeof(d)
    local right_t = ffi.typeof(s)
    local o

    if left_t == datetime_t then
        -- 1. left is date, right is date or generic interval
        if right_t == datetime_t or right_t == interval_t then
            o = right_t == datetime_t and interval_new() or datetime_new()
            o.secs, o.nsec = normalize_nsec(lhs.secs - rhs.secs,
                                            lhs.nsec - rhs.nsec)
            return o
        -- 2. left is date, right is interval in months
        elseif right_t == interval_months_t then
            local dt = local_dt(lhs.secs)
            dt = builtin.tnt_dt_add_months(dt, -rhs.m, builtin.DT_LIMIT)
            return datetime_new_dt(dt, lhs.secs % SECS_PER_DAY,
                                   lhs.nsec, lhs.offset)

        -- 3. left is date, right is interval in years
        elseif right_t == interval_years_t then
            local dt = local_dt(lhs.secs)
            dt = builtin.tnt_dt_add_years(dt, -rhs.y, builtin.DT_LIMIT)
            return datetime_new_dt(dt, lhs.secs % SECS_PER_DAY,
                                   lhs.nsec, lhs.offset)
        else
            error_incompatible("operator -")
        end
    -- 4. both left and right are generic intervals
    elseif left_t == interval_t and right_t == interval_t then
        o = interval_new()
        o.secs, o.nsec = normalize_nsec(lhs.secs - rhs.secs,
                                        lhs.nsec - rhs.nsec)
        return o
    -- 5. both left and right are intervals in months
    elseif left_t == interval_months_t and right_t == interval_months_t then
        return interval_months_new(lhs.m - rhs.m)
    -- 5. both left and right are intervals in years
    elseif left_t == interval_years_t and right_t == interval_years_t then
        return interval_years_new(lhs.y - rhs.y)
    else
        error_incompatible("operator -")
    end
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
local function datetime_add(lhs, rhs)
    local d, s = date_first(lhs, rhs)

    check_date_interval(d, "operator +")
    check_interval(s, "operator +")
    local left_t = ffi.typeof(d)
    local right_t = ffi.typeof(s)
    local o

    -- 1. left is date, right is date or interval
    if left_t == datetime_t and right_t == interval_t then
        o = datetime_new()
        o.secs, o.nsec = normalize_nsec(d.secs + s.secs, d.nsec + s.nsec)
        return o
    -- 2. left is date, right is interval in months
    elseif left_t == datetime_t and right_t == interval_months_t then
        local dt = builtin.tnt_dt_add_months(local_dt(d.secs), s.m, builtin.DT_LIMIT)
        local secs = d.secs % SECS_PER_DAY
        return datetime_new_dt(dt, secs, d.nsec, d.offset or 0)

    -- 3. left is date, right is interval in years
    elseif left_t == datetime_t and right_t == interval_years_t then
        local dt = builtin.tnt_dt_add_years(local_dt(d.secs), s.y, builtin.DT_LIMIT)
        local secs = d.secs % SECS_PER_DAY
        return datetime_new_dt(dt, secs, d.nsec, d.offset or 0)
    -- 4. both left and right are generic intervals
    elseif left_t == interval_t and right_t == interval_t then
        o = interval_new()
        o.secs, o.nsec = normalize_nsec(d.secs + s.secs, d.nsec + s.nsec)
        return o
    -- 5. both left and right are intervals in months
    elseif left_t == interval_months_t and right_t == interval_months_t then
        return interval_months_new(d.m + s.m)
    -- 6. both left and right are intervals in years
    elseif left_t == interval_years_t and right_t == interval_years_t then
        return interval_years_new(d.y + s.y)
    else
        error_incompatible("operator +")
    end
end

--[[
    Basic      Extended
    20121224   2012-12-24   Calendar date   (ISO 8601)
    2012359    2012-359     Ordinal date    (ISO 8601)
    2012W521   2012-W52-1   Week date       (ISO 8601)
    2012Q485   2012-Q4-85   Quarter date

    Returns pair of constructed datetime object, and length of string
    which has been accepted by parser.
]]

local function parse_date(str)
    check_str("datetime.parse_date()")
    local dt = ffi.new('dt_t[1]')
    local len = builtin.tnt_dt_parse_iso_date(str, #str, dt)
    return len > 0 and datetime_new_dt(dt[0]) or nil, tonumber(len)
end

--[[
    Basic               Extended
    T12                 N/A
    T1230               T12:30
    T123045             T12:30:45
    T123045.123456789   T12:30:45.123456789
    T123045,123456789   T12:30:45,123456789

    The time designator [T] may be omitted.

    Returns pair of constructed datetime object, and length of string
    which has been accepted by parser.
]]
local function parse_time(str)
    check_str("datetime.parse_time()")
    local sp = ffi.new('int[1]')
    local fp = ffi.new('int[1]')
    local len = builtin.tnt_dt_parse_iso_time(str, #str, sp, fp)
    return len > 0 and datetime_new_dt(nil, sp[0], fp[0]) or nil,
           tonumber(len)
end

--[[
    Basic    Extended
    Z        N/A
    +hh      N/A
    -hh      N/A
    +hhmm    +hh:mm
    -hhmm    -hh:mm

    Returns pair of constructed datetime object, and length of string
    which has been accepted by parser.
]]
local function parse_zone(str)
    check_str("datetime.parse_zone()")
    local offset = ffi.new('int[1]')
    local len = builtin.tnt_dt_parse_iso_zone_lenient(str, #str, offset)
    return len > 0 and datetime_new_dt(nil, nil, nil, offset[0]) or nil,
           tonumber(len)
end

--[[
    aggregated parse functions
    assumes to deal with date T time time_zone
    at once

    date [T] time [ ] time_zone

    Returns constructed datetime object.
]]
local function parse(str)
    check_str("datetime.parse()")
    local dt = ffi.new('dt_t[1]')
    local len = #str
    local n = builtin.tnt_dt_parse_iso_date(str, len, dt)
    local dt_ = dt[0]
    if n == 0 or len == n then
        return datetime_new_dt(dt_)
    end

    str = str:sub(tonumber(n) + 1)

    local ch = str:sub(1, 1)
    if ch:match('[Tt ]') == nil then
        return datetime_new_dt(dt_)
    end

    str = str:sub(2)
    len = #str

    local sp = ffi.new('int[1]')
    local fp = ffi.new('int[1]')
    local n = builtin.tnt_dt_parse_iso_time(str, len, sp, fp)
    if n == 0 then
        return datetime_new_dt(dt_)
    end
    local sp_ = sp[0]
    local fp_ = fp[0]
    if len == n then
        return datetime_new_dt(dt_, sp_, fp_)
    end

    str = str:sub(tonumber(n) + 1)

    if str:sub(1, 1) == ' ' then
        str = str:sub(2)
    end

    len = #str

    local offset = ffi.new('int[1]')
    n = builtin.tnt_dt_parse_iso_zone_lenient(str, len, offset)
    if n == 0 then
        return datetime_new_dt(dt_, sp_, fp_)
    end
    return datetime_new_dt(dt_, sp_, fp_, offset[0])
end

--[[
    Dispatch function to create datetime from string or table.
    Creates default timeobject (pointing to Epoch date) if
    called without arguments.
]]
local function datetime_from(o)
    if o == nil or type(o) == 'table' then
        return datetime_new(o)
    elseif type(o) == 'string' then
        return parse(o)
    end
end

--[[
    Create datetime object representing current time using microseconds
    platform timer and local timezone information.
]]
local function local_now()
    local d = datetime_new_raw(0, 0, 0)
    builtin.datetime_now(d)
    return d
end

-- addition or subtraction from date/time of a given interval
-- described via table direction should be +1 or -1
local function interval_increment(self, o, direction)
    assert(direction == -1 or direction == 1)
    local title = direction > 0 and "datetime.add" or "datetime.sub"
    check_date(self, title)
    if type(o) ~= 'table' then
        error(('%s - object expected'):format(title), 2)
    end

    local ym_updated = false
    local dhms_updated = false

    local secs, nsec
    secs, nsec = self.secs, self.nsec
    -- operations with intervals should be done using human dates
    -- not UTC dates, thus we normalize to UTC
    local dt = local_dt(secs)

    for key, value in pairs(o) do
        if key == 'years' then
            check_range(value, {0, 9999}, key)
            dt = builtin.tnt_dt_add_years(dt, direction * value, builtin.DT_LIMIT)
            ym_updated = true
        elseif key == 'months' then
            check_range(value, {0, 12}, key)
            dt = builtin.tnt_dt_add_months(dt, direction * value, builtin.DT_LIMIT)
            ym_updated = true
        elseif key == 'weeks' then
            check_range(value, {0, 52}, key)
            secs = secs + direction * 7 * value * SECS_PER_DAY
            dhms_updated = true
        elseif key == 'days' then
            check_range(value, {0, 31}, key)
            secs = secs + direction * value * SECS_PER_DAY
            dhms_updated = true
        elseif key == 'hours' then
            check_range(value, {0, 23}, key)
            secs = secs + direction * 60 * 60 * value
            dhms_updated = true
        elseif key == 'minutes' then
            check_range(value, {0, 59}, key)
            secs = secs + direction * 60 * value
        elseif key == 'seconds' then
            check_range(value, {0, 60}, key)
            local s, frac = math.modf(value)
            secs = secs + direction * s
            nsec = nsec + direction * frac * 1e9
            dhms_updated = true
        end
    end

    secs, nsec = normalize_nsec(secs, nsec)

    -- .days, .hours, .minutes, .seconds
    if dhms_updated then
        self.secs = secs
        self.nsec = nsec
    end

    -- .years, .months updated
    if ym_updated then
        self.secs = (builtin.tnt_dt_rdn(dt) - DT_EPOCH_1970_OFFSET) * SECS_PER_DAY +
                    secs % SECS_PER_DAY
    end

    return self
end

--[[
    Create new object with modified to target_offset time-zone.
    If target timezone does not differ to the original one - we
    return original object unmodified.

    Time `.secs`/`.nsec` are always UTC normalized, we need only to
    reattribute object with different `.offset`
]]
local function datetime_to_tz(self, tgt_ofs)
    if self.offset == tgt_ofs then
        return self
    end
    if type(tgt_ofs) == 'string' then
        local obj = parse_zone(tgt_ofs)
        if obj == nil then
            error(('%s: invalid time-zone format %s'):format(self, tgt_ofs), 2)
        else
            tgt_ofs = obj.offset
        end
    end
    return datetime_new_raw(self.secs, self.nsec, tgt_ofs)
end

--[[
    Provide a set of accessor to datetime attributes:
    - .epoch or .unixtime - return timestamp as seconds represented as double
      typed value, and measured since Epoch;
    - .ts or .timestamp - the same timestamp, but with extended precision and
      fraction part;

    All accessors below convert time distance from Epoch date to different
    units:
    - .ns or .nanoseconds - seconds and fraction converted to nanoseconds;
    - .us or .microseconds - seconds and fraction converted to microseconds;
    - .ms or .milliseconds - seconds and fraction converted to milliseconds;
    - .s or .seconds - seconds with extended precision and fraction part;
    - .m or .min or minutes - minutes with extended precision;
    - .hr or .hours - hours with extended precision;
    - .d or .days - days with extended precision;

    .add or .sub methods provide friendlier way for interval arithmetics;

    .to_utc and .to_tz allows to create equivalent datetime object but in
    particular timezone or as UTC. Time moment remains the same, only time-zone
    information changed, thus textual representation will be impacted also.
]]
local function datetime_index(self, key)
    if key == 'epoch' or key == 'unixtime' then
        return self.secs
    elseif key == 'ts' or key == 'timestamp' then
        return self.secs + self.nsec / 1e9
    elseif key == 'ns' or key == 'nanoseconds' then
        return self.secs * 1e9 + self.nsec
    elseif key == 'us' or key == 'microseconds' then
        return self.secs * 1e6 + self.nsec / 1e3
    elseif key == 'ms' or key == 'milliseconds' then
        return self.secs * 1e3 + self.nsec / 1e6
    elseif key == 's' or key == 'seconds' then
        return self.secs + self.nsec / 1e9
    elseif key == 'm' or key == 'min' or key == 'minutes' then
        return (self.secs + self.nsec / 1e9) / 60
    elseif key == 'hr' or key == 'hours' then
        return (self.secs + self.nsec / 1e9) / (60 * 60)
    elseif key == 'd' or key == 'days' then
        return (self.secs + self.nsec / 1e9) / (24 * 60 * 60)
    elseif key == 'add' then
        return function(self, obj)
            return interval_increment(self, obj, 1)
        end
    elseif key == 'sub' then
        return function(self, obj)
            return interval_increment(self, obj, -1)
        end
    elseif key == 'to_utc' then
        return function(self)
            return datetime_to_tz(self, 0)
        end
    elseif key == 'to_tz' then
        return function(self, offset)
            return datetime_to_tz(self, offset)
        end
    else
        error(('unknown attribute %s'):format(key), 2)
    end
end

--[[
    Allow to change datetime attributes via:
    - .epoch or .unixtime - change datetime via provided interval to Unix Epoch;
    - .ts or .timestamp - change both seconds and nanoseconds fields via given
    timestamp with extended precision. Timestamp fraction part changes
    nanoseconds information.
]]
local function datetime_newindex(self, key, value)
    if key == 'epoch' or key == 'unixtime' then
        self.secs = value
        self.nsec, self.offset = 0, 0
    elseif key == 'ts' or key == 'timestamp' then
        local secs, frac = math_modf(value)
        self.secs = secs
        self.nsec = frac * 1e9
        self.offset = 0
    else
        error(('assigning to unknown attribute %s'):format(key), 2)
    end
end

-- sizeof("Wed Jun 30 21:49:08 1993\n")
local buf_len = 26
local asctime_buffer = ffi.new('char[?]', buf_len)

local function asctime(o)
    check_date(o, "datetime:asctime()")
    return ffi.string(builtin.datetime_asctime(o, asctime_buffer))
end

local ctime_buffer = ffi.new('char[?]', buf_len)

local function ctime(o)
    check_date(o, "datetime:ctime()")
    return ffi.string(builtin.datetime_ctime(o, ctime_buffer))
end

local function strftime(fmt, o)
    check_date(o, "datetime.strftime()")
    local sz = 128
    local buff = ffi.new('char[?]', sz)
    builtin.datetime_strftime(o, fmt, buff, sz)
    return ffi.string(buff)
end

local datetime_mt = {
    __tostring = datetime_tostring,
    __serialize = datetime_serialize,
    __eq = datetime_eq,
    __lt = datetime_lt,
    __le = datetime_le,
    __sub = datetime_sub,
    __add = datetime_add,
    __index = datetime_index,
    __newindex = datetime_newindex,
}

local interval_mt = {
    __tostring = interval_tostring,
    __serialize = interval_serialize,
    __eq = datetime_eq,
    __lt = datetime_lt,
    __le = datetime_le,
    __sub = datetime_sub,
    __add = datetime_add,
    __index = datetime_index,
}

local interval_tiny_mt = {
    __tostring = interval_tostring,
    __serialize = interval_serialize,
    __sub = datetime_sub,
    __add = datetime_add,
    __index = datetime_index,
}

ffi.metatype(interval_t, interval_mt)
ffi.metatype(datetime_t, datetime_mt)
ffi.metatype(interval_years_t, interval_tiny_mt)
ffi.metatype(interval_months_t, interval_tiny_mt)

return setmetatable(
    {
        new         = datetime_new,
        new_raw     = datetime_new_obj,
        years       = interval_years_new,
        months      = interval_months_new,
        weeks       = interval_weeks_new,
        days        = interval_days_new,
        hours       = interval_hours_new,
        minutes     = interval_minutes_new,
        seconds     = interval_seconds_new,

        parse       = parse,
        parse_date  = parse_date,
        parse_time  = parse_time,
        parse_zone  = parse_zone,

        now         = local_now,
        strftime    = strftime,
        asctime     = asctime,
        ctime       = ctime,

        is_datetime = is_datetime,
        is_interval = is_interval,
    }, {
        __call = function(self, ...) return datetime_from(...) end
    }
)
