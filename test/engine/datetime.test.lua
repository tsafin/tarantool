env = require('test_run')
test_run = env.new()
engine = test_run:get_cfg('engine')

date = require('datetime')

_ = box.schema.space.create('T', {engine = engine})
_ = box.space.T:create_index('pk', {parts={1,'datetime'}})

box.space.T:insert{date('1970-01-01')}\
box.space.T:insert{date('1970-01-02')}\
box.space.T:insert{date('1970-01-03')}\
box.space.T:insert{date('2000-01-01')}

o = box.space.T:select{}
assert(tostring(o[1][1]) == '1970-01-01T00:00Z')
assert(tostring(o[2][1]) == '1970-01-02T00:00Z')
assert(tostring(o[3][1]) == '1970-01-03T00:00Z')
assert(tostring(o[4][1]) == '2000-01-01T00:00Z')

for i = 1,16 do\
    box.space.T:insert{date.now()}\
end

a = box.space.T:select{}
err = {}
for i = 1, #a - 1 do\
    if a[i][1] >= a[i+1][1] then\
        table.insert(err, {a[i][1], a[i+1][1]})\
        break\
    end\
end

err
box.space.T:drop()
