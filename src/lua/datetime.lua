local ffi = require('ffi')

ffi.cdef [[

    /*
    `c-dt` library functions handles properly both positive and negative `dt`
    values, where `dt` is a number of dates since Rata Die date (0001-01-01).

    For better compactness of our typical data in MessagePack stream we shift
    root of our time to the Unix Epoch date (1970-01-01), thus our 0 is
    actually dt = 719163.

    So here is a simple formula how convert our epoch-based seconds to dt values
        dt = (secs / 86400) + 719163
    Where 719163 is an offset of Unix Epoch (1970-01-01) since Rata Die
    (0001-01-01) in dates.

    */
    typedef int dt_t;

    // dt_core.h
    typedef enum {
        DT_MON       = 1,
        DT_MONDAY    = 1,
        DT_TUE       = 2,
        DT_TUESDAY   = 2,
        DT_WED       = 3,
        DT_WEDNESDAY = 3,
        DT_THU       = 4,
        DT_THURSDAY  = 4,
        DT_FRI       = 5,
        DT_FRIDAY    = 5,
        DT_SAT       = 6,
        DT_SATURDAY  = 6,
        DT_SUN       = 7,
        DT_SUNDAY    = 7,
    } dt_dow_t;

    dt_t     dt_from_rdn     (int n);
    dt_t     dt_from_yd      (int y, int d);
    dt_t     dt_from_ymd     (int y, int m, int d);
    dt_t     dt_from_yqd     (int y, int q, int d);
    dt_t     dt_from_ywd     (int y, int w, int d);

    void     dt_to_yd        (dt_t dt, int *y, int *d);
    void     dt_to_ymd       (dt_t dt, int *y, int *m, int *d);
    void     dt_to_yqd       (dt_t dt, int *y, int *q, int *d);
    void     dt_to_ywd       (dt_t dt, int *y, int *w, int *d);

    int      dt_rdn          (dt_t dt);
    dt_dow_t dt_dow          (dt_t dt);

    // dt_arithmetic.h
    typedef enum {
        DT_EXCESS,
        DT_LIMIT,
        DT_SNAP
    } dt_adjust_t;

    dt_t    dt_add_years        (dt_t dt, int delta, dt_adjust_t adjust);
    dt_t    dt_add_quarters     (dt_t dt, int delta, dt_adjust_t adjust);
    dt_t    dt_add_months       (dt_t dt, int delta, dt_adjust_t adjust);

    // dt_parse_iso.h
    size_t dt_parse_iso_date          (const char *str, size_t len, dt_t *dt);

    size_t dt_parse_iso_time          (const char *str, size_t len, int *sod, int *nsec);
    size_t dt_parse_iso_time_basic    (const char *str, size_t len, int *sod, int *nsec);
    size_t dt_parse_iso_time_extended (const char *str, size_t len, int *sod, int *nsec);

    size_t dt_parse_iso_zone          (const char *str, size_t len, int *offset);
    size_t dt_parse_iso_zone_basic    (const char *str, size_t len, int *offset);
    size_t dt_parse_iso_zone_extended (const char *str, size_t len, int *offset);
    size_t dt_parse_iso_zone_lenient  (const char *str, size_t len, int *offset);

    // dt_tm.h
    dt_t    dt_from_struct_tm  (const struct tm *tm);
    void    dt_to_struct_tm    (dt_t dt, struct tm *tm);

    // datetime.c
    int
    datetime_to_string(const struct datetime * date, char *buf, uint32_t len);

    char *
    datetime_asctime(const struct datetime *date, char *buf);

    char *
    datetime_ctime(const struct datetime *date, char *buf);

    size_t
    datetime_strftime(const struct datetime *date, const char *fmt, char *buf,
                      uint32_t len);

    void
    datetime_now(struct datetime * now);

]]

local builtin = ffi.C
local math_modf = math.modf
local math_floor = math.floor

local SECS_PER_DAY     = 86400
local NANOS_PER_SEC    = 1000000000LL

-- c-dt/dt_config.h

-- Unix, January 1, 1970, Thursday
local DT_EPOCH_1970_OFFSET = 719163LL


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
    return type(o) == 'cdata' and
           (ffi.istype(interval_t, o) or
            ffi.istype(interval_months_t, o) or
            ffi.istype(interval_years_t, o))
end

local function is_datetime(o)
    return type(o) == 'cdata' and ffi.istype(datetime_t, o)
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
    if not (is_datetime(o) or is_interval(o)) then
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

local function datetime_cmp(lhs, rhs)
    if not is_date_interval(lhs) or
       not is_date_interval(rhs) then
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

local function local_rd(o)
    return math_floor(tonumber(o.secs / SECS_PER_DAY)) + DT_EPOCH_1970_OFFSET
end

local function local_dt(o)
    return builtin.dt_from_rdn(local_rd(o))
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

local function check_range(v, range, txt)
    assert(#range == 2)
    if v < range[1] or v > range[2] then
        error(('value %d of %s is out of allowed range [%d, %d]'):
              format(v, txt, range[1], range[2]), 4)
    end
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

    local dt = local_dt(self)
    local secs, nsec
    secs, nsec = self.secs, self.nsec

    local handlers = {
        years = function(k, v)
            check_range(v, {0, 9999}, k)
            dt = builtin.dt_add_years(dt, direction * v, builtin.DT_LIMIT)
            ym_updated = true
        end,

        months = function(k, v)
            check_range(v, {0, 12}, k)
            dt = builtin.dt_add_months(dt, direction * v, builtin.DT_LIMIT)
            ym_updated = true
        end,

        weeks = function(k, v)
            check_range(v, {0, 52}, k)
            secs = secs + direction * 7 * v * SECS_PER_DAY
            dhms_updated = true
        end,

        days = function(k, v)
            check_range(v, {0, 31}, k)
            secs = secs + direction * v * SECS_PER_DAY
            dhms_updated = true
        end,

        hours = function(k, v)
            check_range(v, {0, 23}, k)
            secs = secs + direction * 60 * 60 * v
            dhms_updated = true
        end,

        minutes = function(k, v)
            check_range(v, {0, 59}, k)
            secs = secs + direction * 60 * v
        end,

        seconds = function(k, v)
            check_range(v, {0, 60}, k)
            local s, frac = math.modf(v)
            secs = secs + direction * s
            nsec = nsec + direction * frac * 1e9
            dhms_updated = true
        end,
    }
    for key, value in pairs(o) do
        handlers[key](key, value)
    end

    secs, nsec = normalize_nsec(secs, nsec)

    -- .days, .hours, .minutes, .seconds
    if dhms_updated then
        self.secs = secs
        self.nsec = nsec
    end

    -- .years, .months updated
    if ym_updated then
        self.secs = (builtin.dt_rdn(dt) - DT_EPOCH_1970_OFFSET) * SECS_PER_DAY +
                    secs % SECS_PER_DAY
    end

    return self
end

local datetime_index_handlers = {
    unixtime = function(self)
        return self.secs
    end,

    timestamp = function(self)
        return tonumber(self.secs) + self.nsec / 1e9
    end,

    nanoseconds = function(self)
        return self.secs * 1e9 + self.nsec
    end,

    microseconds = function(self)
        return self.secs * 1e6 + self.nsec / 1e3
    end,

    milliseconds = function(self)
        return self.secs * 1e3 + self.nsec / 1e6
    end,

    seconds = function(self)
        return tonumber(self.secs) + self.nsec / 1e9
    end,

    minutes = function(self)
        return (tonumber(self.secs) + self.nsec / 1e9) / 60
    end,

    hours = function(self)
        return (tonumber(self.secs) + self.nsec / 1e9) / (60 * 60)
    end,

    days = function(self)
        return (tonumber(self.secs) + self.nsec / 1e9) / (24 * 60 * 60)
    end,

    add = function(self)
        return function(self, o)
            return interval_increment(self, o, 1)
        end
    end,

    sub = function(self)
        return function(self, o)
            return interval_increment(self, o, -1)
        end
    end,
}

local datetime_index = function(self, key)
    local handler = datetime_index_handlers[key]
    return handler ~= nil and handler(self)
end

local datetime_newindex_handlers = {
    unixtime = function(self, value)
        self.secs = value
        self.nsec, self.offset = 0, 0
    end,

    timestamp = function(self, value)
        local secs, frac = math_modf(value)
        self.secs = secs
        self.nsec = frac * 1e9
        self.offset = 0
    end,
}

local function datetime_newindex(self, key, value)
    local handler = datetime_newindex_handlers[key]
    if handler ~= nil then
        handler(self, value)
    end
end

local function datetime_new_raw(secs, nsec, offset)
    local dt_obj = ffi.new(datetime_t)
    dt_obj.secs = secs
    dt_obj.nsec = nsec
    dt_obj.offset = offset
    return dt_obj
end

local function datetime_new_dt(dt, secs, frac, offset)
    local epochV = dt ~= nil and (builtin.dt_rdn(dt) - DT_EPOCH_1970_OFFSET) *
                   SECS_PER_DAY or 0
    local secsV = secs ~= nil and secs or 0
    local fracV = frac ~= nil and frac or 0
    local ofsV = offset ~= nil and offset or 0
    return datetime_new_raw(epochV + secsV - ofsV * 60, fracV, ofsV)
end

-- create datetime given attribute values from obj
local function datetime_new(obj)
    if obj == nil then
        return datetime_new_raw(0, 0, 0)
    end
    local secs = 0
    local nsec = 0
    local offset = 0
    local easy_way = false
    local y = 0
    local M = 0
    local d = 0
    local ymd = false

    local h = 0
    local m = 0
    local s = 0
    local frac = 0
    local hms = false

    local dt = 0

    local handlers = {
        secs = function(_, v)
            secs = v
            easy_way = true
        end,

        nsec = function(_, v)
            nsec = v
            easy_way = true
        end,

        offset = function (_, v)
            offset = v
            easy_way = true
        end,

        year = function(k, v)
            check_range(v, {1, 9999}, k)
            y = v
            ymd = true
        end,

        month = function(k, v)
            check_range(v, {1, 12}, k)
            M = v
            ymd = true
        end,

        day = function(k, v)
            check_range(v, {1, 31}, k)
            d = v
            ymd = true
        end,

        hour = function(k, v)
            check_range(v, {0, 23}, k)
            h = v
            hms = true
        end,

        minute = function(k, v)
            check_range(v, {0, 59}, k)
            m = v
            hms = true
        end,

        second = function(k, v)
            check_range(v, {0, 60}, k)
            s, frac = math_modf(v)
            frac = frac * 1e9 -- convert fraction to nanoseconds
            hms = true
        end,

        -- tz offset in minutes
        tz = function(k, v)
            check_range(v, {0, 720}, k)
            offset = v
        end
    }
    for key, value in pairs(obj) do
        local handler = handlers[key]
        if handler ~= nil then
            handler(key, value)
        else
            error(('unknown attribute %s'):format(key), 2)
        end
    end

    -- .sec, .nsec, .offset
    if easy_way then
        return datetime_new_raw(secs, nsec, offset)
    end

    -- .year, .month, .day
    if ymd then
        dt = dt + builtin.dt_from_ymd(y, M, d)
    end

    -- .hour, .minute, .second
    if hms then
        secs = h * 3600 + m * 60 + s
    end

    return datetime_new_dt(dt, secs, frac, offset)
end

local function datetime_tostring(o)
    if ffi.typeof(o) == datetime_t then
        local sz = 48
        local buff = ffi.new('char[?]', sz)
        local len = builtin.datetime_to_string(o, buff, sz)
        assert(len < sz)
        return ffi.string(buff)
    elseif ffi.typeof(o) == interval_years_t then
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
            local dt = local_dt(lhs)
            dt = builtin.dt_add_months(dt, -rhs.m, builtin.DT_LIMIT)
            return datetime_new_dt(dt, lhs.secs % SECS_PER_DAY,
                                   lhs.nsec, lhs.offset)

        -- 3. left is date, right is interval in years
        elseif right_t == interval_years_t then
            local dt = local_dt(lhs)
            dt = builtin.dt_add_years(dt, -rhs.y, builtin.DT_LIMIT)
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
        local dt = builtin.dt_add_months(local_dt(d), s.m, builtin.DT_LIMIT)
        local secs = d.secs % SECS_PER_DAY
        return datetime_new_dt(dt, secs, d.nsec, d.offset or 0)

    -- 3. left is date, right is interval in years
    elseif left_t == datetime_t and right_t == interval_years_t then
        local dt = builtin.dt_add_years(local_dt(d), s.y, builtin.DT_LIMIT)
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
]]

local function parse_date(str)
    check_str("datetime.parse_date()")
    local dt = ffi.new('dt_t[1]')
    local len = builtin.dt_parse_iso_date(str, #str, dt)
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
]]
local function parse_time(str)
    check_str("datetime.parse_time()")
    local sp = ffi.new('int[1]')
    local fp = ffi.new('int[1]')
    local len = builtin.dt_parse_iso_time(str, #str, sp, fp)
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
]]
local function parse_zone(str)
    check_str("datetime.parse_zone()")
    local offset = ffi.new('int[1]')
    local len = builtin.dt_parse_iso_zone_lenient(str, #str, offset)
    return len > 0 and datetime_new_dt(nil, nil, nil, offset[0]) or nil,
           tonumber(len)
end


--[[
    aggregated parse functions
    assumes to deal with date T time time_zone
    at once

    date [T] time [ ] time_zone
]]
local function parse(str)
    check_str("datetime.parse()")
    local dt = ffi.new('dt_t[1]')
    local len = #str
    local n = builtin.dt_parse_iso_date(str, len, dt)
    local dt_ = dt[0]
    if n == 0 or len == n then
        return datetime_new_dt(dt_)
    end

    str = str:sub(tonumber(n) + 1)

    local ch = str:sub(1,1)
    if ch:match('[Tt ]') == nil then
        return datetime_new_dt(dt_)
    end

    str = str:sub(2)
    len = #str

    local sp = ffi.new('int[1]')
    local fp = ffi.new('int[1]')
    local n = builtin.dt_parse_iso_time(str, len, sp, fp)
    if n == 0 then
        return datetime_new_dt(dt_)
    end
    local sp_ = sp[0]
    local fp_ = fp[0]
    if len == n then
        return datetime_new_dt(dt_, sp_, fp_)
    end

    str = str:sub(tonumber(n) + 1)

    if str:sub(1,1) == ' ' then
        str = str:sub(2)
    end

    len = #str

    local offset = ffi.new('int[1]')
    n = builtin.dt_parse_iso_zone_lenient(str, len, offset)
    if n == 0 then
        return datetime_new_dt(dt_, sp_, fp_)
    end
    return datetime_new_dt(dt_, sp_, fp_, offset[0])
end

local function datetime_from(o)
    if o == nil or type(o) == 'table' then
        return datetime_new(o)
    elseif type(o) == 'string' then
        return parse(o)
    end
end

local function local_now()
    local d = datetime_new_raw(0, 0, 0)
    builtin.datetime_now(d)
    return d
end

-- sizeof("Wed Jun 30 21:49:08 1993\n")
local buf_len = 26

local function asctime(o)
    check_date(o, "datetime:asctime()")
    local buf = ffi.new('char[?]', buf_len)
    return ffi.string(builtin.datetime_asctime(o, buf))
end

local function ctime(o)
    check_date(o, "datetime:ctime()")
    local buf = ffi.new('char[?]', buf_len)
    return ffi.string(builtin.datetime_ctime(o, buf))
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

    add = function(self, o)
        self = interval_increment(self, o, 1)
        return self
    end,

    sub = function(self, o)
        self = interval_increment(self, o, -1)
        return self
    end
}

local interval_mt = {
    __tostring = datetime_tostring,
    __serialize = interval_serialize,
    __eq = datetime_eq,
    __lt = datetime_lt,
    __le = datetime_le,
    __sub = datetime_sub,
    __add = datetime_add,
    __index = datetime_index,
}

local interval_tiny_mt = {
    __tostring = datetime_tostring,
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
        years       = interval_years_new,
        months      = interval_months_new,
        weeks       = interval_weeks_new,
        days        = interval_days_new,
        hours       = interval_hours_new,
        minutes     = interval_minutes_new,
        seconds     = interval_seconds_new,
        interval    = interval_new,

        parse       = parse,
        parse_date  = parse_date,
        parse_time  = parse_time,
        parse_zone  = parse_zone,

        tostring    = datetime_tostring,

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
