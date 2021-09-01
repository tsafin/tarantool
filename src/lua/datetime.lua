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

dt_t   tnt_dt_from_rdn     (int n);
dt_t   tnt_dt_from_ymd     (int y, int m, int d);
void   tnt_dt_to_ymd       (dt_t dt, int *y, int *m, int *d);
void   tnt_dt_to_yqd       (dt_t dt, int *y, int *q, int *d);
void   tnt_dt_to_ywd       (dt_t dt, int *y, int *w, int *d);

int    tnt_dt_rdn          (dt_t dt);
dt_dow_t tnt_dt_dow        (dt_t dt);

// dt_util.h
bool    tnt_dt_leap_year       (int y);
int     tnt_dt_days_in_year    (int y);
int     tnt_dt_days_in_quarter (int y, int q);
int     tnt_dt_days_in_month   (int y, int m);
int     tnt_dt_weeks_in_year   (int y);

]]

-- dt_accessor.h
ffi.cdef [[

int     tnt_dt_year         (dt_t dt);
int     tnt_dt_month        (dt_t dt);
int     tnt_dt_doy          (dt_t dt);
int     tnt_dt_dom          (dt_t dt);

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

local function is_datetime(o)
    return ffi.istype(datetime_t, o)
end

local function check_date(o, message)
    if not is_datetime(o) then
        return error(("%s: expected datetime, but received %s"):
                     format(message, o), 2)
    end
end

local function check_table(o, message)
    if type(o) ~= 'table' then
        return error(("%s: expected table %s"):format(message, o), 2)
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

local function nyi(msg)
    local text = 'Not yet implemented'
    if msg ~= nil then
        text = ("%s : '%s'"):format(text, msg)
    end
    error(text, 3)
end

-- offset if __seconds__ of 1970-01-01 from 0000-01-01
local SECS_EPOCH_OFFSET = (DT_EPOCH_1970_OFFSET * SECS_PER_DAY)

-- convert from epoch related time to Rata Die related
local function local_rd(secs)
    return math_floor((secs + SECS_EPOCH_OFFSET) / SECS_PER_DAY)
end

-- convert UTC seconds to local seconds, adjusting by timezone
local function local_secs(obj)
    return tonumber(obj.epoch + obj.tzoffset * 60)
end

local function utc_secs(epoch, tzoffset)
    return tonumber(epoch - tzoffset * 60)
end

-- get epoch seconds, shift to the local timezone
-- adjust from 1970-related to 0000-related time
-- then return dt in those coordinates (number of days
-- since Rata Die date)
local function local_dt(obj)
    return builtin.tnt_dt_from_rdn(local_rd(local_secs(obj)))
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
    if not is_datetime(lhs) or not is_datetime(rhs) then
        return nil
    end
    local sdiff = lhs.epoch - rhs.epoch
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
    return { epoch = self.epoch, nsec = self.nsec,
             tzoffset = self.tzoffset, tzindex = 0 }
end

local parse_zone

local function datetime_new_raw(epoch, nsec, tzoffset, tzindex)
    local dt_obj = ffi.new(datetime_t)
    dt_obj.epoch = epoch
    dt_obj.nsec = nsec
    dt_obj.tzoffset = tzoffset or 0
    dt_obj.tzindex = tzindex or 0
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
-- { secs = N, nsec = M, offset = O}
local function datetime_new_obj(obj, ...)
    if obj == nil or type(obj) == 'table' then
        return ffi.new(datetime_t, obj)
    else
        return datetime_new_raw(obj, ...)
    end
end

local function get_timezone(offset)
    if type(offset) == 'number' then
        return offset
    elseif type(offset) == 'string' then
        local tzoffset = parse_zone(offset)
        if tzoffset == nil then
            error(('invalid time-zone format %s'):format(offset), 2)
        else
            return tzoffset
        end
    end
end

-- create datetime given attribute values from obj
local function datetime_new(obj)
    if obj == nil or type(obj) ~= 'table' then
        return datetime_new_raw(0, 0, 0)
    end

    local ymd = false
    local hms = false
    local dt = 0

    local y = obj.year
    if y ~= nil then
        check_range(y, {1, 9999}, 'year')
        ymd = true
    end
    local M = obj.month
    if M ~= nil then
        check_range(M, {1, 12}, 'month')
        ymd = true
    end
    local d = obj.day
    if d ~= nil then
        check_range(d, {1, 31}, 'day')
        ymd = true
    end
    local h = obj.hour
    if h ~= nil then
        check_range(h, {0, 23}, 'hour')
        hms = true
    end
    local m = obj.min
    if m ~= nil then
        check_range(m, {0, 59}, 'min')
        hms = true
    end
    local sec = obj.sec
    if sec ~= nil then
        check_range(sec, {0, 60}, 'sec')
        hms = true
    end
    local nsec, usec, msec = obj.nsec, obj.usec, obj.msec
    -- if there are separate nsec, usec, or msec provided then
    -- timestamp should be integer
    local int_ts = nsec ~= nil or usec ~= nil or msec ~= nil

    local ts = obj.timestamp
    local fraction
    if ts ~= nil then
        sec, fraction = math_modf(ts)
        if not int_ts then
            nsec = fraction * 1e9
        end
        hms = true
    end

    local offset = obj.tzoffset
    if offset ~= nil then
        offset = get_timezone(offset)
        check_range(offset, {-720, 720}, offset)
    end

    if obj.tz ~= nil then
        nyi('tz')
    end

    -- .year, .month, .day
    if ymd then
        dt = builtin.tnt_dt_from_ymd(y or 0, M or 1, d or 1)
    end

    -- .hour, .minute, .second
    local secs = 0
    if hms then
        secs = (h or 0) * 3600 + (m or 0) * 60 + (sec or 0)
    end

    return datetime_new_dt(dt, secs, nsec, offset or 0)
end

--[[
    Convert to text datetime values

    - datetime will use ISO-8601 format:
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
    Parse partial ISO-8601 date string

    Accepetd formats are:

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
    Basic    Extended
    Z        N/A
    +hh      N/A
    -hh      N/A
    +hhmm    +hh:mm
    -hhmm    -hh:mm

    Returns pair of constructed datetime object, and length of string
    which has been accepted by parser.
]]
parse_zone = function(str)
    check_str("datetime.parse_zone()")
    local offset = ffi.new('int[1]')
    local len = builtin.tnt_dt_parse_iso_zone_lenient(str, #str, offset)
    return len > 0 and offset[0], tonumber(len)
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
local function datetime_increment(self, o, direction)
    assert(direction == -1 or direction == 1)
    local title = direction > 0 and "datetime.add" or "datetime.sub"
    check_date(self, title)
    if type(o) ~= 'table' then
        error(('%s - object expected'):format(title), 2)
    end

    local secs, nsec = self.epoch, self.nsec
    local offset = self.tzoffset

    -- operations with intervals should be done using human dates
    -- not UTC dates, thus we normalize to UTC
    local dt = local_dt(self)

    local ym_updated = false
    local years, months, weeks = o.years, o.months, o.weeks

    if years ~= nil then
        check_range(years, {0, 9999}, 'years')
        dt = builtin.tnt_dt_add_years(dt, direction * years, builtin.DT_LIMIT)
        ym_updated = true
    end
    if months ~= nil then
        check_range(months, {0, 12}, 'months')
        dt = builtin.tnt_dt_add_months(dt, direction * months, builtin.DT_LIMIT)
        ym_updated = true
    end
    if ym_updated then
        secs = (builtin.tnt_dt_rdn(dt) - DT_EPOCH_1970_OFFSET) * SECS_PER_DAY +
                secs % SECS_PER_DAY
    end

    if weeks ~= nil then
        check_range(weeks, {0, 52}, 'weeks')
        secs = secs + direction * 7 * weeks * SECS_PER_DAY
    end

    local days, hours, minutes, seconds = o.days, o.hours, o.minutes, o.seconds
    if days ~= nil then
        check_range(days, {0, 31}, 'days')
        secs = secs + direction * days * SECS_PER_DAY
    end
    if hours ~= nil then
        check_range(hours, {0, 23}, 'hours')
        secs = secs + direction * 60 * 60 * hours
    end
    if minutes ~= nil then
        check_range(minutes, {0, 59}, 'minutes')
        secs = secs + direction * 60 * minutes
    end
    if seconds ~= nil then
        check_range(seconds, {0, 60}, 'seconds')
        local s, frac = math.modf(seconds)
        secs = secs + direction * s
        nsec = nsec + direction * frac * 1e9
    end

    secs, nsec = normalize_nsec(secs, nsec)

    return datetime_new_raw(secs, nsec, offset)
end

--[[
    Return table in os.date('*t') format, but with timezone
    and nanoseconds
]]
local function datetime_totable(self)
    local secs = local_secs(self) -- hour:minute should be in local timezone
    local dt = local_dt(self)

    return {
        year = builtin.tnt_dt_year(dt),
        month = builtin.tnt_dt_month(dt),
        yday = builtin.tnt_dt_doy(dt),
        day = builtin.tnt_dt_dom(dt),
        wday = ffi.cast('int32_t', builtin.tnt_dt_dow(dt)),
        hour = math_floor((secs / 3600) % 24),
        min = math_floor((secs / 60) % 60),
        sec = secs % 60,
        isdst = false, -- FIXME - after we introduced timezone/DST support
        nsec = self.nsec,
        tzoffset = self.tzoffset,
        -- tz = "MSK", -- FIXME - after we introduced timezone support
    }
end

local function datetime_update_dt(self, dt, new_offset)
    local epoch = local_secs(self)
    local secs_day = epoch % SECS_PER_DAY
    epoch = (builtin.tnt_dt_rdn(dt) - DT_EPOCH_1970_OFFSET) * SECS_PER_DAY + secs_day
    self.epoch = utc_secs(epoch, new_offset)
end

local function datetime_ymd_update(self, y, M, d, new_offset)
    if d > 28 then
        local day_in_month = builtin.tnt_dt_days_in_month(y, M)
        if d > day_in_month then
            error(('invalid number of days %d in month %d for %d'):
                  format(d, M, y), 3)
        end
    end
    local dt = builtin.tnt_dt_from_ymd(y or 0, M or 1, d or 1)
    datetime_update_dt(self, dt, new_offset)
end

local function datetime_hms_update(self, h, m, s, new_offset)
    local epoch = local_secs(self)
    local secs_day = epoch - (epoch % SECS_PER_DAY)
    self.epoch = utc_secs(secs_day + h * 3600 + m * 60 + s, new_offset)
end

local function bool2int(b)
    return b and 1 or 0
end

local function datetime_set(self, obj)
    check_table(obj, "datetime.set()")

    local ymd = false
    local hms = false

    local dt = local_dt(self)
    local y0 = ffi.new('int[1]')
    local M0 = ffi.new('int[1]')
    local d0 = ffi.new('int[1]')
    builtin.tnt_dt_to_ymd(dt, y0, M0, d0)
    y0, M0, d0 = y0[0], M0[0], d0[0]

    local y = obj.year
    if y ~= nil then
        check_range(y, {1, 9999}, 'year')
        ymd = true
    end
    local M = obj.month
    if M ~= nil then
        check_range(M, {1, 12}, 'month')
        ymd = true
    end
    local d = obj.day
    if d ~= nil then
        check_range(d, {1, 31}, 'day')
        ymd = true
    end

    local lsecs = local_secs(self)
    local h0 = math_floor(lsecs / (24 * 60)) % 24
    local m0 = math_floor(lsecs / 60) % 60
    local sec0 = lsecs % 60

    local h = obj.hour
    if h ~= nil then
        check_range(h, {0, 23}, 'hour')
        hms = true
    end
    local m = obj.min
    if m ~= nil then
        check_range(m, {0, 59}, 'min')
        hms = true
    end
    local sec = obj.sec
    if sec ~= nil then
        check_range(sec, {0, 60}, 'sec')
        hms = true
    end

    local nsec, usec, msec = obj.nsec, obj.usec, obj.msec
    local count_usec = bool2int(nsec ~= nil) + bool2int(usec ~= nil) +
                       bool2int(msec ~= nil)
    if count_usec > 1 then
        error('only one of nsec, usec or msecs may defined simultaneously', 2)
    end
    if usec ~= nil then
        nsec = usec * 1e3
    elseif msec ~= nil then
        nsec = msec * 1e6
    end

    local ts = obj.timestamp
    if ts ~= nil then
        local sec_int, fraction
        sec_int, fraction = math_modf(ts)
        -- if there is one of nsec, usec, msec provided
        -- then ignore fraction in timestamp
        -- otherwise - use nsec, usec, or msec
        if count_usec == 0 then
            nsec = fraction * 1e9
        end

        self.secs = sec_int
        self.nsec = nsec

        return self
    end

    local offset0 = self.tzoffset
    local offset = obj.tzoffset
    if offset ~= nil then
        offset = get_timezone(offset)
        check_range(offset, {-720, 720}, offset)
        -- self.tzoffset = offset
    end

    if obj.tz ~= nil then
        nyi('tz')
    end

    -- .year, .month, .day
    if ymd then
        datetime_ymd_update(self, y or y0, M or M0, d or d0, offset or offset0)
    end

    -- .hour, .minute, .second
    if hms then
        datetime_hms_update(self, h or h0, m or m0, sec or sec0, offset or offset0)
    end

    self.epoch, self.nsec = normalize_nsec(self.epoch, self.nsec)

    if offset ~= nil then
        self.tzoffset = offset
    end

    return self
end

local function strftime(fmt, o)
    check_date(o, "datetime.strftime()")
    local sz = 128
    local buff = ffi.new('char[?]', sz)
    builtin.datetime_strftime(o, fmt, buff, sz)
    return ffi.string(buff)
end

ffi.metatype(datetime_t, {
    __tostring = datetime_tostring,
    __serialize = datetime_serialize,
    __eq = datetime_eq,
    __lt = datetime_lt,
    __le = datetime_le,
    __index = {
        epoch = function(self) return self.epoch end,
        timestamp = function(self) return self.epoch + self.nsec / 1e9 end,

        nsec = function(self) return self.nsec end,
        usec = function(self) return self.nsec / 1e3 end,
        msec = function(self) return self.nsec / 1e6 end,

        dt = function(self) return local_dt(self) end,
        year = function(self) return builtin.tnt_dt_year(local_dt(self)) end,
        month = function(self) return builtin.tnt_dt_month(local_dt(self)) end,

        yday = function(self) return builtin.tnt_dt_doy(local_dt(self)) end,
        wday = function(self)
            return ffi.cast('int32_t', builtin.tnt_dt_dow(local_dt(self)))
        end,
        day = function(self)
            return builtin.tnt_dt_dom(local_dt(self))
        end,
        hour = function(self) return math_floor((local_secs(self) / 3600) % 24) end,
        minute = function(self) return math_floor((local_secs(self) / 60) % 60) end,
        second = function(self) return self.epoch % 60 end,

        add = function(self, obj) return datetime_increment(self, obj, 1) end,
        sub = function(self, obj) return datetime_increment(self, obj, -1) end,
        format = datetime_tostring,
        totable = datetime_totable,
        set = datetime_set,
    }
})

return setmetatable(
    {
        new         = datetime_new,
        new_raw     = datetime_new_obj,

        parse       = parse,
        parse_date  = parse_date,

        now         = local_now,
        strftime    = strftime,

        is_datetime = is_datetime,
    }, {
        __call = function(self, ...) return datetime_from(...) end
    }
)
