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
    dt_t     tnt_dt_from_rdn     (int n);
    dt_t     tnt_dt_from_ymd     (int y, int m, int d);

    int      tnt_dt_rdn          (dt_t dt);

    // dt_parse_iso.h
    size_t tnt_dt_parse_iso_date          (const char *str, size_t len, dt_t *dt);
    size_t tnt_dt_parse_iso_time          (const char *str, size_t len, int *sod, int *nsec);
    size_t tnt_dt_parse_iso_zone_lenient  (const char *str, size_t len, int *offset);

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

local SECS_PER_DAY     = 86400

-- c-dt/dt_config.h

-- Unix, January 1, 1970, Thursday
local DT_EPOCH_1970_OFFSET = 719163


local datetime_t = ffi.typeof('struct datetime')
local interval_t = ffi.typeof('struct datetime_interval')

local function is_interval(o)
    return type(o) == 'cdata' and ffi.istype(interval_t, o)
end

local function is_datetime(o)
    return type(o) == 'cdata' and ffi.istype(datetime_t, o)
end

local function is_date_interval(o)
    return type(o) == 'cdata' and
           (ffi.istype(interval_t, o) or ffi.istype(datetime_t, o))
end

local function interval_new()
    local interval = ffi.new(interval_t)
    return interval
end

local function check_date(o, message)
    if not is_datetime(o) then
        return error(("%s: expected datetime, but received %s"):
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

local function datetime_new_raw(secs, nsec, offset)
    local dt_obj = ffi.new(datetime_t)
    dt_obj.secs = secs
    dt_obj.nsec = nsec
    dt_obj.offset = offset
    return dt_obj
end

local function datetime_new_dt(dt, secs, frac, offset)
    local epochV = dt ~= nil and (builtin.tnt_dt_rdn(dt) - DT_EPOCH_1970_OFFSET) *
                   SECS_PER_DAY or 0
    local secsV = secs ~= nil and secs or 0
    local fracV = frac ~= nil and frac or 0
    local ofsV = offset ~= nil and offset or 0
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
    local frac = 0
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
            s, frac = math_modf(value)
            frac = frac * 1e9 -- convert fraction to nanoseconds
            hms = true
        elseif key == 'tz' then
        -- tz offset in minutes
            check_range(value, {0, 720}, key)
            offset = value
        elseif key == 'isdst' or key == 'wday' or key =='yday' then -- luacheck: ignore 542
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

    return datetime_new_dt(dt, secs, frac, offset)
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

    local ch = str:sub(1,1)
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

    if str:sub(1,1) == ' ' then
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

-- Change the time-zone to the provided target_offset
-- Time `.secs`/`.nsec` are always UTC normalized, we need only to
-- reattribute object with different `.offset`
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
    __serialize = datetime_serialize,
    __eq = datetime_eq,
    __lt = datetime_lt,
    __le = datetime_le,
    __index = datetime_index,
    __newindex = datetime_newindex,
}

local interval_mt = {
    __serialize = interval_serialize,
    __eq = datetime_eq,
    __lt = datetime_lt,
    __le = datetime_le,
    __index = datetime_index,
}

ffi.metatype(interval_t, interval_mt)
ffi.metatype(datetime_t, datetime_mt)

return setmetatable(
    {
        new         = datetime_new,
        new_raw     = datetime_new_obj,
        interval    = interval_new,

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
