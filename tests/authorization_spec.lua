for _,file in ipairs({'config/authorization.lua','server/lib/util.lua','server/auth_identity.lua','server/authorization_hub.lua'}) do dofile('/repo/'..file) end
local total,failures=0,0
local function test(name,fn) total=total+1;local ok,err=pcall(fn);if not ok then failures=failures+1 end;__report(name,ok,tostring(err)) end
local function fixture()
    local c={now=10000,compatible=true,states={monitor='started'},ids={},aces={},logs={}}
    for id=1,4 do c.ids[id]='license:'..string.rep(string.char(96+id),40);c.aces[id]={} end
    c.aces[1]['osdev.admin']=true
    OSDevtools.AuthorizationConfig.ExternalProviders={}
    c.hub=OSDevtools.AuthorizationHub.new({
        now=function() return c.now end,identity=function(src) return c.ids[src] end,
        ace=function(src,permission) return c.aces[src] and c.aces[src][permission] or false end,
        txReady=function() return c.compatible and c.states.monitor=='started' end,
        resourceState=function(name) return c.states[name] end,log=function(s) c.logs[#c.logs+1]=s end
    })
    function c.auth(id) assert(c.hub.txEvent('monitor',{netid=id,isAdmin=true,username='Ignored visible name',permissions={'all_permissions'}})) end
    return c
end
test('Existing ACE and console administration remain effective independently of txAdmin',function()
    local c=fixture();assert(c.hub.can(1,'osdev.admin') and c.hub.can(1,'osdev.economy') and c.hub.can(0,'ossecurity.admin'))
    assert(not c.hub.can(1,'ossecurity.admin') and not c.hub.can(0,'unknown.permission'))
    c.auth(2);assert(c.hub.grant(0,2,'oscar_admin',10));assert(c.hub.can(2,'osdev.admin') and c.hub.can(2,'ossecurity.admin') and c.hub.can(2,'osinventory.admin'))
    c.compatible=false;assert(c.hub.can(1,'osdev.economy'))
end)
test('A second authenticated txAdmin administrator receives only an explicitly assigned profile',function()
    local c=fixture();c.auth(2)
    assert(not c.hub.can(2,'osdev.economy') and not c.hub.can(2,'osdev.admin'))
    assert(c.hub.grant(0,2,'finance',10));assert(c.hub.can(2,'osdev.economy'))
    assert(not c.hub.can(2,'osdev.assets') and not c.hub.can(2,'osdev.admin') and not c.hub.can(2,'ossecurity.admin'))
end)
test('Limited moderators can inspect without receiving money, assets, identity or security privileges',function()
    local c=fixture();c.auth(3);assert(c.hub.grant(0,3,'observer',10))
    assert(c.hub.can(3,'osdev.inspect'))
    for _,scope in ipairs({'osdev.admin','osdev.economy','osdev.assets','osdev.jobs','osdev.identity','ossecurity.admin'}) do assert(not c.hub.can(3,scope)) end
end)
test('Asset sub-permissions follow the parent chain and stay separate from each other',function()
    local c=fixture()
    assert(c.hub.can(1,'osdev.assets.factions') and c.hub.can(1,'osdev.assets.dealers')) -- osdev.admin -> osdev.assets -> sub
    c.aces[3]['osdev.assets.factions']=true
    assert(c.hub.can(3,'osdev.assets.factions') and not c.hub.can(3,'osdev.assets.properties') and not c.hub.can(3,'osdev.assets'))
    c.auth(2);assert(c.hub.grant(0,2,'assets',10));assert(c.hub.can(2,'osdev.assets.vehicles') and not c.hub.can(2,'osdev.economy'))
end)
test('Normal players cannot obtain a lease or authorize themselves',function()
    local c=fixture();assert(not c.hub.grant(0,4,'devtools_admin',10))
    assert(not c.hub.grant(4,4,'devtools_admin',10));assert(not c.hub.can(4,'osdev.admin'))
    assert(not c.hub.txEvent(nil,{netid=4,isAdmin=true}))
    assert(not c.hub.txEvent('client',{netid=4,isAdmin=true}))
end)
test('Visible names, forged permissions and events from other resources never authorize',function()
    local c=fixture();assert(not c.hub.txEvent('other_resource',{netid=4,isAdmin=true,username='owner',permissions={'all_permissions'}}))
    c.auth(2);assert(not c.hub.can(2,'osdev.admin'))
    assert(not c.hub.txEvent('monitor',{netid='2',isAdmin=true}))
    assert(not c.hub.txEvent('monitor',{netid=-1,isAdmin=true}))
    assert(not c.hub.txEvent('monitor',{netid=0,isAdmin=true}))
end)
test('Removing an administrator invalidates its lease immediately',function()
    local c=fixture();c.auth(2);assert(c.hub.grant(0,2,'devtools_admin',10));assert(c.hub.can(2,'osdev.admin'))
    assert(c.hub.txEvent('monitor',{netid=2,isAdmin=false}));assert(not c.hub.can(2,'osdev.admin'))
end)
test('Any admin-list or permission change invalidates old grants and requires explicit resynchronization',function()
    local c=fixture();c.auth(2);c.auth(3);assert(c.hub.grant(0,2,'devtools_admin',10));assert(c.hub.grant(0,3,'observer',10))
    assert(c.hub.updated('monitor'));assert(not c.hub.can(2,'osdev.admin') and not c.hub.can(3,'osdev.inspect'))
    c.auth(2);assert(not c.hub.can(2,'osdev.admin'));assert(c.hub.grant(0,2,'jobs',10));assert(c.hub.can(2,'osdev.jobs') and not c.hub.can(2,'osdev.economy'))
end)
test('Global txAdmin reauthentication revokes proofs for all sessions',function()
    local c=fixture();c.auth(2);assert(c.hub.grant(0,2,'finance',10))
    assert(c.hub.txEvent('monitor',{netid=-1,isAdmin=false}));assert(not c.hub.can(2,'osdev.economy'))
end)
test('Reconnection and server-ID reuse cannot inherit temporary privileges',function()
    local c=fixture();c.auth(2);assert(c.hub.grant(0,2,'devtools_admin',10))
    c.ids[9]=c.ids[2];assert(not c.hub.can(9,'osdev.admin'))
    c.hub.drop(2);assert(not c.hub.can(2,'osdev.admin'))
    c.auth(2);assert(c.hub.grant(0,2,'finance',10));c.ids[2]=c.ids[4];assert(not c.hub.can(2,'osdev.economy'))
end)
test('A fresh broker after a resource/server restart starts without txAdmin grants',function()
    local c=fixture();c.auth(2);assert(c.hub.grant(0,2,'finance',10));local restarted=fixture()
    assert(not restarted.hub.can(2,'osdev.economy'));assert(restarted.hub.can(1,'osdev.admin'))
end)
test('Lease expiry, proof expiry and clock rollback revoke authorization',function()
    local c=fixture();c.auth(2);assert(c.hub.grant(0,2,'finance',1));c.now=c.now+60000;assert(not c.hub.can(2,'osdev.economy'))
    c.auth(2);assert(c.hub.grant(0,2,'finance',60));c.now=c.now+OSDevtools.AuthorizationConfig.ProofSeconds*1000;assert(not c.hub.can(2,'osdev.economy'))
    c.auth(2);assert(c.hub.grant(0,2,'finance',1));c.now=0;assert(not c.hub.can(2,'osdev.economy'))
end)
test('Stopping or changing the txAdmin version disables its grants without disabling explicit ACE',function()
    local c=fixture();c.auth(2);assert(c.hub.grant(0,2,'finance',10));c.compatible=false
    assert(not c.hub.can(2,'osdev.economy') and c.hub.can(1,'osdev.economy'))
    c.compatible=true;c.auth(2);assert(c.hub.grant(0,2,'finance',10));c.hub.resourceStopped('monitor');assert(not c.hub.can(2,'osdev.economy'))
end)
test('Administrative management requires its own ACE and profile replacement removes previous capabilities',function()
    local c=fixture();c.auth(2);assert(not c.hub.grant(1,2,'finance',10))
    c.aces[1]['oscar.auth.manage']=true;assert(c.hub.grant(1,2,'finance',10));assert(c.hub.can(2,'osdev.economy'))
    assert(c.hub.grant(1,2,'jobs',10));assert(c.hub.can(2,'osdev.jobs') and not c.hub.can(2,'osdev.economy'))
    assert(not c.hub.revoke(2,2));assert(c.hub.revoke(1,2));assert(not c.hub.can(2,'osdev.jobs'))
end)
test('The Security consumer can request only its verified permission, without global access to other domains',function()
    local c=fixture();c.auth(2);assert(c.hub.grant(0,2,'security_admin',10))
    assert(c.hub.consumer('os_security',2,'ossecurity.admin'))
    assert(not c.hub.consumer('os_security',2,'osdev.admin') and not c.hub.consumer('unapproved',2,'ossecurity.admin'))
    assert(not c.hub.consumer('os_inventory',2,'osinventory.admin'))
    assert(c.hub.grant(0,2,'inventory_admin',10))
    assert(c.hub.consumer('os_inventory',2,'osinventory.admin') and not c.hub.consumer('os_inventory',2,'ossecurity.admin'))
    assert(not c.hub.consumer('os_security',2,'osinventory.admin'))
end)
test('External providers are explicitly allowed, scope-limited, checked live and invalidated when stopped',function()
    local c=fixture();assert(not c.hub.registerProvider('other',function() return true end))
    OSDevtools.AuthorizationConfig.ExternalProviders.trusted={['osdev.inspect']=true};c.states.trusted='started'
    local enabled=true
    assert(c.hub.registerProvider('trusted',function(source,principal,scope) assert(source==4 and principal==c.ids[4] and scope=='osdev.inspect');return enabled end))
    assert(c.hub.can(4,'osdev.inspect') and not c.hub.can(4,'osdev.economy'))
    enabled=false;assert(not c.hub.can(4,'osdev.inspect'));enabled=true;c.hub.resourceStopped('trusted');assert(not c.hub.can(4,'osdev.inspect'))
end)
test('Audit records grants/revocations without full persistent identifiers or usernames',function()
    local c=fixture();c.auth(2);assert(c.hub.grant(0,2,'finance',10));assert(c.hub.revoke(0,2))
    local log=table.concat(c.logs,'\n');assert(log:find('action=grant',1,true) and log:find('action=revoke',1,true))
    assert(not log:find(c.ids[2],1,true) and not log:find('Ignored visible name',1,true))
end)
test('Invalid profiles, sources, durations and identities never produce authorization',function()
    local c=fixture();c.auth(2)
    for _,minutes in ipairs({-1,0,1.5,61,math.huge}) do assert(not c.hub.grant(0,2,'devtools_admin',minutes)) end
    assert(not c.hub.grant(0,2,'not_a_profile',10));assert(not c.hub.can('2','osdev.admin'))
    c.aces[1]['oscar.auth.manage']=true;c.ids[1]=nil;assert(not c.hub.grant(1,2,'finance',10))
    c.ids[2]='Same visible name';assert(not c.hub.txEvent('monitor',{netid=2,isAdmin=true}) and not c.hub.can(2,'osdev.admin'))
end)
print(('Authorization tests: %d | Passed: %d | Failed: %d'):format(total,total-failures,failures));__failures=failures
-- Envio de bienes a la web del panel.
dofile('/repo/server/panel_sync.lua')
do
    local before=failures
    local label=function(category,id,r) return category..'#'..id end
    test('Panel sync sends new, changed and deleted assets and splits factions',function()
        local s={properties={['200']={id=200,price=50000,position={x=1.234,y=2,z=3}}},businesses={['1']={id=1,type='ltd',name='LTD',price=1},['2']={id=2,type='faccion',name='Ballas',price=0,job='ballas'}},vehicles={}}
        local changes,last=OSDevtools.PanelSync.diff(s,{},label)
        assert(#changes==3 and last['factions:2'] and last['businesses:1'] and last['properties:200'].x==1.23)
        assert(#OSDevtools.PanelSync.diff(s,last,label)==0)
        s.properties['200'].owner='oscar_vega';s.businesses['1']=nil
        changes,last=OSDevtools.PanelSync.diff(s,last,label)
        assert(#changes==2 and changes[1].deleted and changes[1].category=='businesses' and changes[2].owner=='oscar_vega')
    end)
    test('Panel sync forwards only audit entries after the marker',function()
        local audit={{time=1,actor='a',operation='x 1'},{time=2,actor='a',operation='y 2'}}
        local list,marker=OSDevtools.PanelSync.newAudit(audit,nil);assert(#list==0)
        audit[3]={time=3,actor='b',operation='crear 3'};table.remove(audit,1)
        list,marker=OSDevtools.PanelSync.newAudit(audit,marker);assert(#list==1 and list[1].operation=='crear 3')
        list=OSDevtools.PanelSync.newAudit(audit,marker);assert(#list==0)
    end)
    test('Panel sync sends business staff and character changes',function()
        local s={properties={},vehicles={},businesses={['3']={id=3,type='ltd',name='LTD',price=1,owner='ana_lopez',staff={oscar_vega='encargado'}}},
            characters={oscar_vega={id='oschar_0000000004',account='license:'..string.rep('a',40),cash=10,bank=20,job='ltd',rank='encargado',duty=true,life='alive'}}}
        local changes,last=OSDevtools.PanelSync.diff(s,{},label)
        assert(changes[1].extra.staff[1].alias=='oscar_vega' and changes[1].extra.staff[1].rank=='encargado')
        s.businesses['3'].staff.oscar_vega='empleado'
        assert(#OSDevtools.PanelSync.diff(s,last,label)==1)
        local people,known=OSDevtools.PanelSync.characters(s,{})
        assert(#people==1 and people[1].id==4 and people[1].ref=='oschar_0000000004' and people[1].duty==true)
        assert(#OSDevtools.PanelSync.characters(s,known)==0)
        s.characters.oscar_vega.cash=11;assert(#OSDevtools.PanelSync.characters(s,known)==1)
        s.characters.oscar_vega=nil;local gone=OSDevtools.PanelSync.characters(s,known);assert(gone[1].deleted and gone[1].id==4)
    end)
    __failures=failures
end
