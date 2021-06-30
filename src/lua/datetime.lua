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

    // <asm-generic/posix_types.h>
    typedef long            __kernel_long_t;
    typedef unsigned long   __kernel_ulong_t;
    // /usr/include/x86_64-linux-gnu/bits/types/time_t.h
    typedef long            time_t;


    // <time.h>
    typedef __kernel_long_t	__kernel_time_t;
    typedef __kernel_long_t	__kernel_suseconds_t;

    struct timespec {
        __kernel_time_t	        tv_sec;     /* seconds */
        long                    tv_nsec;    /* nanoseconds */
    };

    struct timeval {
        __kernel_time_t	        tv_sec;	    /* seconds */
        __kernel_suseconds_t    tv_usec;    /* microseconds */
    };

    struct timezone {
        int	tz_minuteswest;     /* minutes west of Greenwich */
        int	tz_dsttime;	        /* type of dst correction */
    };

    // /usr/include/x86_64-linux-gnu/sys/time.h
    typedef struct timezone * __timezone_ptr_t;

    /* Get the current time of day and timezone information,
       putting it into *TV and *TZ.  If TZ is NULL, *TZ is not filled.
       Returns 0 on success, -1 on errors.

       NOTE: This form of timezone information is obsolete.
       Use the functions and variables declared in <time.h> instead.  */
    int gettimeofday (struct timeval *__tv, struct timezone * __tz);

    // /usr/include/x86_64-linux-gnu/bits/types/struct_tm.h
    /* ISO C `broken-down time' structure.  */
    struct tm
    {
        int tm_sec;	        /* Seconds.	[0-60] (1 leap second) */
        int tm_min;	        /* Minutes.	[0-59] */
        int tm_hour;        /* Hours.	[0-23] */
        int tm_mday;        /* Day.		[1-31] */
        int tm_mon;	        /* Month.	[0-11] */
        int tm_year;        /* Year	- 1900.  */
        int tm_wday;        /* Day of week.	[0-6] */
        int tm_yday;        /* Days in year.[0-365]	*/
        int tm_isdst;       /* DST.		[-1/0/1]*/

        long int tm_gmtoff; /* Seconds east of UTC.  */
        const char *tm_zone;/* Timezone abbreviation.  */
    };

    // <time.h>
    /* Return the current time and put it in *TIMER if TIMER is not NULL.  */
    time_t time (time_t *__timer);

    /* Format TP into S according to FORMAT.
    Write no more than MAXSIZE characters and return the number
    of characters written, or 0 if it would exceed MAXSIZE.  */
    size_t strftime (char * __s, size_t __maxsize, const char * __format,
                     const struct tm * __tp);

    /* Parse S according to FORMAT and store binary time information in TP.
    The return value is a pointer to the first unparsed character in S.  */
    char *strptime (const char * __s, const char * __fmt, struct tm *__tp);

    /* Return the `struct tm' representation of *TIMER in UTC,
    using *TP to store the result.  */
    struct tm *gmtime_r (const time_t * __timer, struct tm * __tp);

    /* Return the `struct tm' representation of *TIMER in local time,
    using *TP to store the result.  */
    struct tm *localtime_r (const time_t * __timer, struct tm * __tp);

    /* Return a string of the form "Day Mon dd hh:mm:ss yyyy\n"
    that is the representation of TP in this format.  */
    char *asctime (const struct tm *__tp);

    /* Equivalent to `asctime (localtime (timer))'.  */
    char *ctime (const time_t *__timer);

]]

local builtin = ffi.C

local SECS_PER_DAY     = 86400
local NANOS_PER_SEC    = 1000000000LL

-- c-dt/dt_config.h

-- Unix, January 1, 1970, Thursday
local DT_EPOCH_1970_OFFSET = 719163LL


local datetime_t = ffi.typeof('struct datetime_t')
local interval_t = ffi.typeof('struct datetime_interval_t')

local function is_interval(o)
    return type(o) == 'cdata' and ffi.istype(interval_t, o)
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

local function check_date(o, message, lvl)
    if lvl == nil then
        lvl = 2
    end
    if not is_datetime(o) then
        return error(("%s: expected datetime, but received %s"):
                     format(message, o), lvl)
    end
end

local function check_date_interval(o, message, lvl)
    if lvl == nil then
        lvl = 2
    end
    if not (is_datetime(o) or is_interval(o)) then
        return error(("%s: expected datetime or interval, but received %s"):
                     format(message, o), lvl)
    end
end

local function check_interval(o, message, lvl)
    if lvl == nil then
        lvl = 2
    end
    if not is_interval(o) then
        return error(("%s: expected interval, but received %s"):
                     format(message, o), lvl)
    end
end

local function check_str(s, message, lvl)
    if lvl == nil then
        lvl = 2
    end
    if not type(s) == 'string' then
        return error(("%s: expected string, but received %s"):
                     format(message, s), lvl)
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
    return rc ~= nil and rc == 0 or false
end

local function datetime_lt(lhs, rhs)
    local rc = datetime_cmp(lhs, rhs)
    return rc ~= nil and rc < 0 or false
end

local function datetime_le(lhs, rhs)
    local rc = datetime_cmp(lhs, rhs)
    return rc ~= nil and rc <= 0 or false
end

local function datetime_serialize(self)
    -- Allow YAML, MsgPack and JSON to dump objects with sockets
    return { secs = self.secs, nsec = self.nsec, offset = self.offset }
end

local function interval_serialize(self)
    -- Allow YAML and JSON to dump objects with sockets
    return { secs = self.secs, nsec = self.nsec }
end

local function local_rd(o)
    return math.floor(tonumber(o.secs / SECS_PER_DAY)) + DT_EPOCH_1970_OFFSET
end

local function local_dt(o)
    return builtin.dt_from_rdn(local_rd(o))
end

local function _normalize_nsec(secs, nsec)
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
    if not (v >= range[1] and v <= range[2]) then
        error(('value %d of %s is out of allowed range [%d, %d]'):
              format(v, txt, range[1], range[2]))
    end
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
        return (tonumber(self.secs) + self.nsec / 1e9) / (60 * 60) / 24
    end,
}

local datetime_index = function(self, key)
    return datetime_index_handlers[key] ~= nil and
           datetime_index_handlers[key](self) or nil
end

local datetime_newindex_handlers = {
    unixtime = function(self, value)
        self.secs = value
        self.nsec, self.offset = 0, 0
    end,

    timestamp = function(self, value)
        local secs, frac = math.modf(value)
        self.secs = secs
        self.nsec = frac * 1e9
        self.offset = 0
    end,
}

local function datetime_newindex(self, key, value)
    if datetime_newindex_handlers[key] ~= nil then
        datetime_newindex_handlers[key](self, value)
    end
end

local function datetime_new_raw(secs, nsec, offset)
    local dt_obj = ffi.new(datetime_t)
    dt_obj.secs = secs
    dt_obj.nsec = nsec
    dt_obj.offset = offset
    return dt_obj
end

local function mk_timestamp(dt, sp, fp, offset)
    local epochV = dt ~= nil and (builtin.dt_rdn(dt) - DT_EPOCH_1970_OFFSET) *
                   SECS_PER_DAY or 0
    local spV = sp ~= nil and sp or 0
    local fpV = fp ~= nil and fp or 0
    local ofsV = offset ~= nil and offset or 0
    return datetime_new_raw (epochV + spV - ofsV * 60, fpV, ofsV)
end

-- create @datetime_t given object @o fields
local function datetime_new(o)
    if o == nil then
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
        secs = function(k, v)
            secs = v
            easy_way = true
        end,

        nsec = function(k, v)
            nsec = v
            easy_way = true
        end,

        offset = function (k, v)
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
            s, frac = math.modf(v)
            frac = frac * 1e9 -- convert fraction to nanoseconds
            hms = true
        end,

        -- tz offset in minutes
        tz = function(k, v)
            check_range(v, {0, 720}, k)
            offset = v
        end
    }
    for key, value in pairs(o) do
        handlers[key](key, value)
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

    return mk_timestamp(dt, secs, frac, offset)
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

local function datetime_sub(lhs, rhs)
    check_date_interval(lhs, "operator -")
    local d, s = lhs, rhs
    local left_t = ffi.typeof(d)
    local right_t = ffi.typeof(s)
    local o

    if left_t == datetime_t then
        -- left is date, right is date or generic interval
        if (right_t == datetime_t or right_t == interval_t) then
            o = right_t == datetime_t and interval_new() or datetime_new()
            o.secs, o.nsec = _normalize_nsec(lhs.secs - rhs.secs,
                                            lhs.nsec - rhs.nsec)
            return o
        else
            error_incompatible("operator -")
        end
    -- both left and right are generic intervals
    elseif left_t == interval_t and right_t == interval_t then
        o = interval_new()
        o.secs, o.nsec = _normalize_nsec(lhs.secs - rhs.secs,
                                        lhs.nsec - rhs.nsec)
        return o
    else
        error_incompatible("operator -")
    end
end

local function datetime_add(lhs, rhs)
    local d, s = date_first(lhs, rhs)

    check_date_interval(d, "operator +")
    check_interval(s, "operator +")
    local left_t = ffi.typeof(d)
    local right_t = ffi.typeof(s)
    local o

    -- left is date, right is date or interval
    if left_t == datetime_t and right_t == interval_t then
        o = datetime_new()
        o.secs, o.nsec = _normalize_nsec(d.secs + s.secs, d.nsec + s.nsec)
        return o
    -- both left and right are generic intervals
    elseif left_t == interval_t and right_t == interval_t then
        o = interval_new()
        o.secs, o.nsec = _normalize_nsec(d.secs + s.secs, d.nsec + s.nsec)
        return o
    else
        error_incompatible("operator +")
    end
end

-- simple parse functions:
-- parse_date/parse_time/parse_zone

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
    return len > 0 and mk_timestamp(dt[0]) or nil, tonumber(len)
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
    return len > 0 and mk_timestamp(nil, sp[0], fp[0]) or nil,
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
    return len > 0 and mk_timestamp(nil, nil, nil, offset[0]) or nil,
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
        return mk_timestamp(dt_)
    end

    str = str:sub(tonumber(n) + 1)

    local ch = str:sub(1,1)
    if ch:match('[Tt ]') == nil then
        return mk_timestamp(dt_)
    end

    str = str:sub(2)
    len = #str

    local sp = ffi.new('int[1]')
    local fp = ffi.new('int[1]')
    local n = builtin.dt_parse_iso_time(str, len, sp, fp)
    if n == 0 then
        return mk_timestamp(dt_)
    end
    local sp_ = sp[0]
    local fp_ = fp[0]
    if len == n then
        return mk_timestamp(dt_, sp_, fp_)
    end

    str = str:sub(tonumber(n) + 1)

    if str:sub(1,1) == ' ' then
        str = str:sub(2)
    end

    len = #str

    local offset = ffi.new('int[1]')
    n = builtin.dt_parse_iso_zone_lenient(str, len, offset)
    if n == 0 then
        return mk_timestamp(dt_, sp_, fp_)
    end
    return mk_timestamp(dt_, sp_, fp_, offset[0])
end

local function datetime_from(o)
    if o == nil or type(o) == 'table' then
        return datetime_new(o)
    elseif type(o) == 'string' then
        return parse(o)
    end
end

local function local_now()
    local p_tv = ffi.new('struct timeval [1]')
    local rc = builtin.gettimeofday(p_tv, nil)
    assert(rc == 0)

    local secs = p_tv[0].tv_sec
    local nsec = p_tv[0].tv_usec * 1000

    local p_time = ffi.new('time_t[1]')
    local p_tm = ffi.new('struct tm[1]')
    builtin.time(p_time)
    builtin.localtime_r(p_time, p_tm)
    local ofs = p_tm[0].tm_gmtoff / 60 -- convert seconds to minutes

    return datetime_new_raw(secs, nsec, ofs)
end

local function datetime_to_tm_ptr(o)
    assert(is_datetime(o))
    local p_tm = ffi.new('struct tm[1]')
    -- dt_to_struct_tm() fills only date data
    builtin.dt_to_struct_tm(local_dt(o), p_tm)

    -- calculate the smaller data (hour, minute,
    -- seconds) using datetime seconds value
    local seconds_of_day = o.secs % 86400
    local hour = (seconds_of_day / 3600) % 24
    local minute = (seconds_of_day / 60) % 60
    p_tm[0].tm_sec = seconds_of_day % 60
    p_tm[0].tm_min = minute
    p_tm[0].tm_hour = hour

    p_tm[0].tm_gmtoff = o.offset * 60

    return p_tm
end

local function asctime(o)
    check_date(o, "datetime:asctime()")

    local p_tm = datetime_to_tm_ptr(o)
    return ffi.string(builtin.asctime(p_tm))
end

local function ctime(o)
    check_date(o, "datetime:ctime()")
    local p_time = ffi.new('time_t[1]')
    p_time[0] = o.secs
    return ffi.string(builtin.ctime(p_time))
end

local function strftime(fmt, o)
    check_date(o, "datetime.strftime()")
    local p_tm = datetime_to_tm_ptr(o)
    local sz = builtin.strftime(nil, 1024, fmt, p_tm) + 1
    local buff = ffi.new('char[?]', sz)
    builtin.strftime(buff, sz, fmt, p_tm)
    return ffi.string(buff)
end

local datetime_mt = {
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
    __serialize = interval_serialize,
    __eq = datetime_eq,
    __lt = datetime_lt,
    __le = datetime_le,
    __sub = datetime_sub,
    __add = datetime_add,
    __index = datetime_index,
}

ffi.metatype(interval_t, interval_mt)
ffi.metatype(datetime_t, datetime_mt)

return setmetatable(
    {
        new         = datetime_new,
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
