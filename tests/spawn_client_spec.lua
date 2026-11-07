local test=DevtoolsTest.test
dofile('/repo/client/spawn_controller.lua')
local function fixture()
    local c={timers={},acks={},failures={},released=0,notices={}}
    c.controller=OSDevtools.SpawnClient.new({
        schedule=function(delay,fn) c.timers[#c.timers+1]={delay=delay,fn=fn} end,
        spawn=function(point,callback,isCurrent) c.position=point;c.complete=callback;c.isCurrent=isCurrent end,
        ack=function(token) c.acks[#c.acks+1]=token end,
        failed=function(token) c.failures[#c.failures+1]=token end,
        release=function() c.released=c.released+1 end,notify=function(s) c.notices[#c.notices+1]=s end
    })
    return c
end
test('Spawn client retries replication acknowledgement until the matching server acceptance',function()
    local c=fixture();c.controller.receive({token='one',position={x=1,y=2,z=3}});c.complete(true)
    assert(c.acks[1]=='one');local retry=c.timers[#c.timers];assert(retry.delay==500);retry.fn();assert(#c.acks==2)
    c.controller.accepted('forged');retry=c.timers[#c.timers];retry.fn();assert(#c.acks==3)
    c.controller.accepted('one');retry=c.timers[#c.timers];retry.fn();assert(#c.acks==3 and c.released==1)
end)
test('Spawn client releases controls on collision failure, timeout and resource stop without infinite retries',function()
    local c=fixture();c.controller.receive({token='one',position={}});c.complete(false);assert(c.failures[1]=='one' and c.released==1)
    c.controller.receive({token='two',position={}});c.timers[#c.timers].fn();assert(c.failures[2]=='two' and #c.notices==1)
    c.controller.receive({token='three',position={}});local late=c.complete;c.controller.stop();late(true);assert(#c.acks==0)
end)
test('A newer server spawn invalidates work belonging to an earlier generation',function()
    local c=fixture();c.controller.receive({token='one',position={x=1}});local old=c.complete
    local oldCurrent=c.isCurrent
    c.controller.receive({token='two',position={x=2}});old(true);assert(#c.acks==0 and not oldCurrent() and c.isCurrent())
    c.complete(true);assert(c.acks[1]=='two' and c.position.x==2)
end)
