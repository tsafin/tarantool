test_run = require('test_run').new()
test_run:cmd("restart server default")

-- Deploy a cluster.
SERVERS = { 'autobootstrap1', 'autobootstrap2', 'autobootstrap3' }
test_run:create_cluster(SERVERS, "replication", {args="0.03"})
test_run:wait_fullmesh(SERVERS)

-- gh-3247 - Sequence-generated value is not replicated in case
-- the request was sent via iproto.
test_run:cmd("switch autobootstrap1")
net_box = require('net.box')
_ = box.schema.space.create('space1')
_ = box.schema.sequence.create('seq')
_ = box.space.space1:create_index('primary', {sequence = true} )
_ = box.space.space1:create_index('secondary', {parts = {2, 'unsigned'}})
box.schema.user.grant('guest', 'read,write', 'space', 'space1')
c = net_box.connect(box.cfg.listen)
c.space.space1:insert{box.NULL, "data"} -- fails, but bumps sequence value
c.space.space1:insert{box.NULL, 1, "data"}
box.space.space1:select{}
vclock = test_run:get_vclock("autobootstrap1")
vclock[0] = nil
_ = test_run:wait_vclock("autobootstrap2", vclock)
test_run:cmd("switch autobootstrap2")
box.space.space1:select{}
test_run:cmd("switch autobootstrap1")
box.space.space1:drop()

test_run:cmd("switch default")
test_run:drop_cluster(SERVERS)
test_run:cleanup_cluster()
