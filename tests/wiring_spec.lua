local total,failures=0,0
local function test(name,run) total=total+1;local ok,err=pcall(run);if not ok then failures=failures+1 end;__report(name,ok,tostring(err)) end
local scripts={'config/spawn.lua','config/business.lua','config/authorization.lua','config/core.lua','server/lib/util.lua',
    'server/storage/codec.lua','server/storage/resource_files.lua','server/storage/json.lua','server/state.lua','server/appearance_xml.lua','server/storage.lua','server/core.lua',
    'server/auth_identity.lua','server/authorization_hub.lua','server/auth_boot.lua','server/identity_commands.lua','server/admin_section.lua','server/vehicles.lua','server.lua'}
local function legacy()
    return {version=1,nextVehicle=2,nextBusiness=2,characters={
        oscar_vega={cash=1000,bank=2000,job='gruppe6',rank='vigilante',duty=false,lastPosition={x=10,y=20,z=30,h=90,bucket=0,time=1700000000}},
        client_test={cash=300,bank=400,job='unemployed',rank='-',duty=false}},
        bindings={['license:'..string.rep('a',40)]='oscar_vega',['license:'..string.rep('b',40)]='client_test'},
        vehicles={['1']={id=1,model='sultan',primary=0,secondary=111,fixed=true,plate='OS000001',owner='oscar_vega'}},
        businesses={['1']={id=1,type='ltd',name='market',price=30,owner='client_test'}},properties={},audit={}}
end
local function fixture(files,behavior)
    local c={files=files or {['data.json']=json.encode(legacy())},commands={},events={},net={},exports={},threads={},messages={},players={},clock=10000,writes=0,
        aces={[1]={['osdev.admin']=true,['command']=true},[2]={}},states={monitor='started'},version='8.1.2'}
    for id=1,2 do c.players[id]={identifiers={'license:'..string.rep(string.char(96+id),40)},point={x=id*10,y=20,z=30},h=90,bucket=0} end
    for key,value in pairs(behavior or {}) do c[key]=value end
    local originalPrint,originalOpen=print,io.open
    RegisterCommand=function(name,fn) c.commands[name]=fn end
    RegisterNetEvent=function(name,fn) c.net[name]=fn end
    AddEventHandler=function(name,fn) c.events[name]=c.events[name] or {};table.insert(c.events[name],fn) end
    TriggerClientEvent=function(name,source,...) assert(source>0);c.messages[#c.messages+1]={name=name,source=source,args={...}} end
    GetCurrentResourceName=function() return 'os_devtools' end
    GetInvokingResource=function() return c.origin end
    GetResourceState=function(name) return c.states[name] or 'stopped' end
    GetResourceMetadata=function(name,key,index) assert(name=='monitor' and key=='version' and index==0);return c.version end
    GetPlayerName=function(source) return c.players[source] and not c.players[source].disconnected and 'Same display name' or nil end
    GetPlayerIdentifiers=function(source) return c.players[source] and c.players[source].identifiers or {} end
    GetPlayers=function() local result={};for source,player in pairs(c.players) do if not player.disconnected then result[#result+1]=tostring(source) end end;table.sort(result);return result end
    IsPlayerAceAllowed=function(source,permission)
        local result=c.aces[source] and c.aces[source][permission] or false
        return c.aceInteger and (result and 1 or 0) or result
    end
    GetPlayerPed=function(source) return c.players[source] and source+100 or 0 end
    c.executed={};ExecuteCommand=function(command) c.executed[#c.executed+1]=command end
    -- Mundo simulado de vehiculos de servidor (handles >1000, sin choque con peds 101+).
    c.world=c.world or {};c.nextEntity=c.nextEntity or 1000;c.onesync=c.onesync or 'on'
    GetConvar=function(name,default) if name=='onesync' then return c.onesync end;return default end
    GetHashKey=function(name) local h=0;for i=1,#name do h=(h*31+name:byte(i))%2147483647 end;return h end
    CreateVehicleServerSetter=function(model,kind,x,y,z,h)
        if c.failCreate then return 0 end
        c.nextEntity=c.nextEntity+1;c.world[c.nextEntity]={model=model,kind=kind,point={x=x,y=y,z=z},h=h,bucket=0,state={}};return c.nextEntity
    end
    SetEntityOrphanMode=function(e,mode) c.world[e].orphan=mode end
    SetEntityRoutingBucket=function(e,bucket) c.world[e].bucket=bucket end
    GetEntityRoutingBucket=function(e) return c.world[e].bucket end
    SetVehicleNumberPlateText=function(e,plate) c.world[e].plate=plate end
    SetVehicleColours=function(e,a,b) c.world[e].colours={a,b} end
    GetVehicleNumberPlateText=function(e) return c.world[e] and c.world[e].plate or '' end
    GetAllVehicles=function() local r={};for e in pairs(c.world) do r[#r+1]=e end;table.sort(r);return r end
    DeleteEntity=function(e) c.world[e]=nil end
    Entity=function(e)
        return {state=setmetatable({},{__index=function(_,key)
            if key=='set' then return function(_,name,value) c.world[e].state[name]=value end end
            return c.world[e] and c.world[e].state[key]
        end})}
    end
    GetEntityCoords=function(e) if c.world[e] then return c.world[e].point end;return c.players[e-100].point end
    GetEntityHeading=function(e) if c.world[e] then return c.world[e].h end;return c.players[e-100].h end
    GetEntityHealth=function(ped) return c.players[ped-100].health or 200 end
    GetPlayerRoutingBucket=function(source) return c.players[source].bucket end
    DoesEntityExist=function(e) return c.world[e]~=nil or c.players[e-100]~=nil end
    NetworkGetEntityFromNetworkId=function() return 0 end
    SetPlayerRoutingBucket=function(source,bucket) c.players[source].bucket=bucket end
    SetEntityCoords=function(ped,x,y,z) c.players[ped-100].point={x=x,y=y,z=z} end
    GetGameTimer=function() return c.clock end
    CreateThread=function(fn) c.threads[#c.threads+1]=coroutine.create(fn) end
    Wait=function() coroutine.yield() end
    SetTimeout=function(delay,callback) c.timers=c.timers or {};c.timers[#c.timers+1]={delay=delay,callback=callback} end
    TriggerEvent=function(name,...) c.changed={name,...} end
    LoadResourceFile=function(_,file) return c.files[file] end
    SaveResourceFile=function(_,file,bytes,length)
        assert(length==#bytes);c.writes=c.writes+1
        if c.failWrite or c.failAt==c.writes then
            if c.partial then c.files[file]='{partial' end
            if c.completeBeforeError then c.files[file]=bytes end
            return false
        end
        c.files[file]=bytes;return c.nativeWrite==nil and true or c.nativeWrite
    end
    io.open=function() return nil,'missing',2 end
    exports=function(name,fn) c.exports[name]=fn end
    print=function() end
    local ok,err=pcall(function()
        for _,file in ipairs(scripts) do dofile('/repo/'..file) end
        for _,thread in ipairs(c.threads) do local success,reason=coroutine.resume(thread);assert(success,reason) end
    end)
    print,io.open=originalPrint,originalOpen;assert(ok,err);c.core=OSDevtools.Runtime
    function c.command(name,source,args) c.origin=nil;assert(c.commands[name],name)(source,args or {}) end
    function c.event(name,origin,...) source=0;c.origin=origin;for _,fn in ipairs(c.events[name] or {}) do fn(...) end;c.origin=nil end
    function c.auth(id) c.event('txAdmin:events:adminAuth','monitor',{netid=id,isAdmin=true}) end
    function c.snapshot()
        local a=c.files['data/core.a.json'];local b=c.files['data/core.b.json']
        a=a and OSDevtools.JsonCodec.decode(a);b=b and OSDevtools.JsonCodec.decode(b)
        return a and b and (a.revision>b.revision and a or b) or a or b or json.decode(c.files['data.json'])
    end
    function c.text(source) local result={};for _,msg in ipairs(c.messages) do if msg.source==source and (msg.name=='osdev:msg' or msg.name=='osdev:list') then result[#result+1]=msg.args[1] end end;return table.concat(result,'\n') end
    return c
end
test('All Lua syntax and actual manifest paths load while preserving pretest position commands',function()
    for _,file in ipairs(__files) do assert(loadfile('/repo/'..file),file) end
    local environment={fx_version=function(v) assert(v=='cerulean') end,game=function(v) assert(v=='gta5') end,lua54=function() end,author=function() end,description=function() end,
        version=function(v) assert(v=='0.1.3') end,server_scripts=function(files) for _,file in ipairs(files) do assert(loadfile('/repo/'..file)) end end,
        shared_script=function(file) assert(loadfile('/repo/'..file)) end,shared_scripts=function(files) for _,file in ipairs(files) do assert(loadfile('/repo/'..file)) end end,
        client_scripts=function(files) for _,file in ipairs(files) do assert(loadfile('/repo/'..file)) end end,ui_page=function() end,files=function() end}
    assert(loadfile('/repo/fxmanifest.lua','t',environment))()
    local c=fixture();assert(not c.commands.setpj and c.commands.guardarpos and c.commands.ultimaubicacion and c.commands.setspawn)
    for _,name in ipairs({'setuser','setmoney','givemoney','removemoney','setjob','setduty','crearpropiedad','crearnegocio','crearvehiculo','setpropiedad','setnegocio','setvehiculo','recuperarvehiculo','setcolor','setlivery','listliveries','verpropiedades','listvehiculos','listnegocios','listpropiedades','infovehiculo','infonegocio','infopropiedad','pagar','ceder','dinero','misbienes','mispropiedades','osautorizar','osrevocar','ospermisos'}) do assert(c.commands[name],name) end
end)
test('Existing primary ACE admin works and native integer 0 never grants a normal player privileges',function()
    local c=fixture();c.aceInteger=true;local before=c.writes
    c.command('setmoney',2,{'1','9999','cash'});assert(c.writes==before)
    c.command('setmoney',1,{'2','999','cash'});assert(c.snapshot().characters.client_test.cash==999)
end)
test('Verified txAdmin event plus explicit console synchronization activates only the selected operation category',function()
    local c=fixture();c.auth(2);local before=c.writes;c.command('setmoney',2,{'1','50','cash'});assert(c.writes==before)
    c.command('osautorizar',0,{'2','finance','10','CONFIRMAR'});c.command('setmoney',2,{'1','50','cash'})
    assert(c.snapshot().characters.oscar_vega.cash==50)
    before=c.writes;c.command('setjob',2,{'1','police','officer'});c.command('setvehiculo',2,{'1','2'});c.command('setspawn',2,{'1'});assert(c.writes==before)
    c.command('osautorizar',2,{'2','devtools_admin','10','CONFIRMAR'});assert(not OSDevtools.AuthHub.can(2,'osdev.admin'))
end)
test('Moderator inspection is usable but every mutating admin category remains protected',function()
    local c=fixture();c.auth(2);c.command('osautorizar',0,{'2','observer','10','CONFIRMAR'})
    local before=c.writes;c.command('verpropiedades',2,{'1'});assert(c.text(2):find('oscar_vega',1,true))
    for name,args in pairs({setmoney={'1','10'},givemoney={'1','10'},removemoney={'1','10'},setjob={'1','gruppe6','vigilante'},setduty={'1','on'},setvehiculo={'1','2'},setnegocio={'1','2'},setpropiedad={'200','2'},crearvehiculo={'sultan','0'},crearnegocio={'ltd','market','30'},crearpropiedad={'200','50000'},setcolor={'0','111'},setlivery={'0','native'},listliveries={},recuperarvehiculo={'1'},setspawn={'1'},setuser={}}) do c.command(name,2,args) end
    assert(c.writes==before)
end)
test('All protected command categories execute with the unchanged broad osdev.admin ACE',function()
    local c=fixture();c.command('setmoney',1,{'2','5000','bank'});c.command('givemoney',1,{'2','20','cash'});c.command('removemoney',1,{'2','5','cash'})
    c.command('setjob',1,{'2','gruppe6','vigilante'});c.command('setduty',1,{'2','on'})
    c.command('crearpropiedad',1,{'200','50000'});c.command('crearnegocio',1,{'ltd','shop','30'});c.command('crearvehiculo',1,{'sultan','0','111','fijo','2'})
    c.command('setpropiedad',1,{'200','2'});c.command('setnegocio',1,{'1','oscar_vega'});c.command('setvehiculo',1,{'1','2'});c.command('setspawn',1,{'2'})
    c.command('recuperarvehiculo',1,{'1'});c.command('setcolor',1,{'0','111'});c.command('setlivery',1,{'0','native'});c.command('listliveries',1)
    for _,name in ipairs({'setuser','verpropiedades','listvehiculos','listnegocios','listpropiedades','infovehiculo','infonegocio'}) do c.command(name,1,{'1'}) end
    c.command('infopropiedad',1,{'200'})
    local d=c.snapshot();assert(d.characters.client_test.bank==5000 and d.characters.client_test.cash==315 and d.characters.client_test.duty)
    assert(d.vehicles['1'].owner=='client_test' and d.properties['200'].owner=='client_test' and d.businesses['1'].owner=='oscar_vega')
end)
test('Live revocation, changed permissions and stopped monitor take effect on the next command',function()
    local c=fixture();c.auth(2);c.command('osautorizar',0,{'2','finance','10','CONFIRMAR'})
    c.command('osrevocar',0,{'2'});local before=c.writes;c.command('setmoney',2,{'1','50'});assert(c.writes==before)
    c.command('osautorizar',0,{'2','finance','10','CONFIRMAR'});c.event('txAdmin:events:adminsUpdated','monitor',{})
    c.command('setmoney',2,{'1','50'});assert(c.writes==before)
    c.auth(2);c.command('osautorizar',0,{'2','finance','10','CONFIRMAR'});c.states.monitor='stopped';c.command('setmoney',2,{'1','50'});assert(c.writes==before)
end)
test('A new/restarted resource does not restore delegated privileges while existing account balances remain',function()
    local c=fixture();c.auth(2);c.command('osautorizar',0,{'2','finance','10','CONFIRMAR'});c.command('setmoney',2,{'1','500'})
    local restarted=fixture(c.files);local before=restarted.writes;restarted.command('setmoney',2,{'1','9'});assert(restarted.writes==before and restarted.snapshot().characters.oscar_vega.cash==500)
end)
test('Client events cannot fake local txAdmin authentication or choose another identity',function()
    local c=fixture();assert(not c.net['txAdmin:events:adminAuth'] and not c.net['txAdmin:events:adminsUpdated'])
    c.event('txAdmin:events:adminAuth','untrusted',{netid=2,isAdmin=true,permissions={'all_permissions'}})
    c.command('osautorizar',0,{'2','devtools_admin','10','CONFIRMAR'});assert(not OSDevtools.AuthHub.can(2,'osdev.admin'))
    local before=c.writes;source=2;c.net['osdev:vehicleAppearance']('OS000001',0,111);c.net['osdev:vehicleModelTypes']('forged',{sultan='automobile'});assert(c.writes==before)
end)
test('txAdmin admins join group.admin for their session only while txAdmin recognizes them',function()
    local c=fixture()
    c.event('txAdmin:events:adminAuth','untrusted',{netid=2,isAdmin=true});assert(#c.executed==0)
    c.auth(2);assert(c.executed[1]=='add_principal player.2 group.admin' and #c.executed==1)
    c.auth(2);assert(#c.executed==1) -- sin duplicar
    c.event('txAdmin:events:adminAuth','monitor',{netid=2,isAdmin=false});assert(c.executed[2]=='remove_principal player.2 group.admin')
    c.auth(2);c.event('txAdmin:events:adminAuth','monitor',{netid=-1,isAdmin=false});assert(c.executed[4]=='remove_principal player.2 group.admin')
    c.auth(2);source=2;for _,fn in ipairs(c.events.playerDropped) do fn() end;assert(c.executed[6]=='remove_principal player.2 group.admin')
    c.event('txAdmin:events:adminAuth','monitor',{netid=9,isAdmin=true});assert(#c.executed==6) -- jugador inexistente
end)
test('Only approved resource consumers can query their own verified scopes',function()
    local c=fixture();c.auth(2);c.command('osautorizar',0,{'2','security_admin','10','CONFIRMAR'})
    c.origin='os_security';assert(c.exports.HasOscarPermission(2,'ossecurity.admin') and not c.exports.HasOscarPermission(2,'osdev.admin'))
    c.origin='os_inventory';assert(not c.exports.HasOscarPermission(2,'ossecurity.admin'))
    c.origin='untrusted';assert(not c.exports.HasOscarPermission(2,'ossecurity.admin'))
end)
test('Diagnostic is personal and masked, with separate ACE and effective permission results',function()
    local c=fixture();c.auth(2);c.command('osautorizar',0,{'2','finance','10','CONFIRMAR'});c.command('ospermisos',2,{'1'})
    local text=c.text(2);assert(text:find('Sesion 2',1,true) and text:find('osdev.economy=true (txadmin_explicit_lease)',1,true))
    assert(not text:find(string.rep('a',40),1,true) and not text:find(string.rep('b',40),1,true))
    local count=#c.messages;c.command('ospermisos',2);assert(#c.messages==count)
end)
test('Persistent auth identity comes from the server and rejects malformed or ambiguous identifiers',function()
    local c=fixture();c.players[2].identifiers={'fivem:12345','license2:'..string.rep('c',40),'license:'..string.rep('b',40)}
    assert(OSDevtools.AuthIdentity.resolve(2)=='license:'..string.rep('b',40))
    c.players[2].identifiers={'license:invalid'};assert(not OSDevtools.AuthIdentity.resolve(2));c.auth(1)
    c.players[1].identifiers={'license:'..string.rep('a',40),'license:'..string.rep('b',40)};assert(not OSDevtools.AuthHub.can(1,'osdev.admin'))
end)
test('Existing automatic identity, oscar_vega, balances, assets and pretest position fields are preserved',function()
    local initial=legacy();local c=fixture();local d=c.snapshot()
    for alias,character in pairs(initial.characters) do for field,value in pairs(character) do
        if field=='lastPosition' then for axis,number in pairs(value) do assert(d.characters[alias][field][axis]==number,axis) end
        else assert(OSDevtools.Util.equal(value,d.characters[alias][field]),field) end
    end end
    assert(d.vehicles['1'].owner=='oscar_vega' and d.businesses['1'].owner=='client_test')
    c.players[7]=c.players[1];c.players[1]=nil;assert(c.exports.GetCharacterId(7)=='oscar_vega')
    c.players[9]={identifiers={'license:'..string.rep('c',40)},point={x=30,y=20,z=30},h=90,bucket=0}
    local created=c.exports.GetCharacterId(9);assert(created and c.snapshot().characters[created].cash==0)
end)
test('Personal payments remain usable for normal players and reject negative, missing, self and excessive amounts',function()
    local c=fixture();c.command('dinero',2);c.command('misbienes',2);c.command('pagar',2,{'1','100'})
    assert(c.snapshot().characters.client_test.cash==200 and c.snapshot().characters.oscar_vega.cash==1100)
    local before=c.writes
    for _,args in ipairs({{'client_test','1'},{'1','-1'},{'1','0'},{'1','999999'},{'99','1'}}) do c.command('pagar',2,args) end
    assert(c.writes==before)
end)
test('Personal asset requests do not bypass inspection scopes or expose other accounts',function()
    local c=fixture();c.command('mispropiedades',2)
    local message=c.messages[#c.messages];assert(message.name=='osdev:own' and message.source==2)
    assert(not message.args[1]['1'] and message.args[2]['1'].owner=='client_test')
    assert(not message.args[5].lastPosition and not json.encode(message):find('license:',1,true))
end)
DevtoolsTest={fixture=fixture,test=test,legacy=legacy}
dofile('/repo/tests/core_spec.lua')
dofile('/repo/tests/spawn_client_spec.lua')
dofile('/repo/tests/character_select_spec.lua')
DevtoolsTest=nil
print(('Wiring/core tests: %d | Passed: %d | Failed: %d'):format(total,total-failures,failures));__failures=failures
