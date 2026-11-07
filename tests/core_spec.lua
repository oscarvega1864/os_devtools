local test,fixture,legacy=DevtoolsTest.test,DevtoolsTest.fixture,DevtoolsTest.legacy
test('Explicit character and numeric alias syntax cannot be confused with player or asset IDs',function()
    local c=fixture();local id=c.core.dto(2).characterId
    c.command('setmoney',1,{'char:'..id,'900','bank'});assert(c.snapshot().characters.client_test.bank==900)
    c.command('pagar',1,{'char:'..id,'50'});assert(c.snapshot().characters.client_test.cash==350)
    c.command('crearpropiedad',1,{'200','casa','villa','30','char:'..id});local property=c.snapshot().properties['200']
    assert(property.owner=='client_test' and property.position.x==c.players[1].point.x)
    c.command('crearpersonaje',1,{'1','123'});local aliasId=c.snapshot().characters['123'].id
    assert(c.core.resolve('alias:123')=='123' and not c.core.resolve('123') and c.core.resolve('char:'..aliasId)=='123')
end)
test('Vehicle recovery does not issue duplicate simultaneous spawn requests for one record',function()
    local c=fixture();c.command('recuperarvehiculo',1,{'1'});local count=#c.messages
    c.command('recuperarvehiculo',1,{'1'})
    for index=count+1,#c.messages do assert(c.messages[index].name~='osdev:spawnVehicle') end
end)
test('Server spawn timeout requests one safe fallback even if client timeout delivery is late',function()
    local c=fixture();assert(c.core.requestSpawn(1,'connect'));c.clock=c.clock+20000;assert(c.core.observe(1))
    local context=c.messages[#c.messages].args[1];assert(context.reason=='safe_fallback')
    c.clock=c.clock+20000;assert(not c.core.observe(1));local count=#c.messages
    c.core.observe(1);assert(#c.messages==count)
end)
test('A reconnecting dead character keeps the hospital policy even when its new ped initially has health',function()
    local c=fixture();c.players[1].health=0;assert(c.core.observe(1));local files=c.files
    local restarted=fixture(files);assert(restarted.core.observe(1));assert(restarted.snapshot().characters.oscar_vega.life=='dead')
    assert(restarted.core.spawnSelection(1).x==OSDevtools.CoreConfig.HospitalSpawn.x)
end)
local function ack(c,source)
    for i=#c.messages,1,-1 do
        local m=c.messages[i]
        if m.name=='osdev:spawnCharacter' and m.source==source then
            local context=m.args[1];c.players[source].point=OSDevtools.Util.copy(context.position);c.players[source].h=context.position.h;c.players[source].health=200
            assert(c.core.spawnAck(source,context.token));return context.token
        end
    end
    error('No spawn context')
end
test('Version-1 migration keeps original bytes, known ownership, money, jobs, assets and backup',function()
    local raw=json.encode(legacy());local c=fixture({['data.json']=raw});local d=c.snapshot()
    assert(d.version==2 and d.characters.oscar_vega.id~=d.characters.client_test.id)
    assert(d.characters.oscar_vega.account=='license:'..string.rep('a',40))
    assert(d.characters.oscar_vega.cash==1000 and d.vehicles['1'].owner=='oscar_vega')
    assert(c.files['data.json']==raw and c.files['data/migration-013-source.json']==raw)
    assert(not c.files['data/state.a.json'])
end)
test('Creation and selection preserve the previous live position, money and asset titles',function()
    local c=fixture();c.command('crearpersonaje',1,{'1','second_person'})
    local originalId=c.snapshot().characters.oscar_vega.id
    c.command('seleccionarpersonaje',1,{'1','second_person'});ack(c,1)
    local d=c.snapshot();assert(d.characters.oscar_vega.lastPosition.reason=='character_switch' and d.characters.oscar_vega.cash==1000)
    assert(d.bindings['license:'..string.rep('a',40)]=='second_person' and d.vehicles['1'].owner=='oscar_vega')
    c.command('personaje',1,{'char:'..originalId});ack(c,1)
    assert(c.snapshot().bindings['license:'..string.rep('a',40)]=='oscar_vega')
end)
test('Foreign selection and duplicate aliases are rejected without creating or transferring resources',function()
    local c=fixture();local before=c.writes
    c.command('seleccionarpersonaje',1,{'1','client_test'});c.command('personaje',1,{'client_test'})
    c.command('crearpersonaje',1,{'1','OSCAR_VEGA'});c.command('crearpersonaje',2,{'2','forged_person'})
    assert(c.writes==before and c.snapshot().characters.client_test.cash==300)
end)
test('An unknown legacy owner requires confirmed linking and never receives an automatic empty substitute',function()
    local data=legacy();data.characters.orphan={cash=700,bank=90,job='unemployed',rank='-',duty=false}
    local c=fixture({['data.json']=json.encode(data)})
    c.players[9]={identifiers={'license:'..string.rep('c',40)},point={x=20,y=10,z=40},h=0,bucket=0}
    assert(not c.core.ensure(9));local before=c.writes
    c.command('vincularpersonaje',1,{'9','orphan'});assert(c.writes==before)
    c.command('vincularpersonaje',1,{'9','orphan','CONFIRMAR'});ack(c,9)
    assert(c.core.dto(9).alias=='orphan' and c.snapshot().characters.orphan.cash==700)
    before=c.writes;c.command('vincularpersonaje',1,{'9','oscar_vega','CONFIRMAR'});assert(c.writes==before)
end)
test('Manual position save ignores invalid/zero coordinates and unauthorized buckets',function()
    local c=fixture();c.command('guardarpos',1);local before=c.writes;local position=c.snapshot().characters.oscar_vega.lastValidPosition
    c.players[1].point={x=0,y=0,z=0};c.command('guardarpos',1)
    c.players[1].point={x=0/0,y=20,z=30};c.command('guardarpos',1)
    c.players[1].point={x=20,y=30,z=40};c.players[1].bucket=99;c.command('guardarpos',1)
    assert(c.writes==before and OSDevtools.Util.equal(position,c.snapshot().characters.oscar_vega.lastValidPosition))
end)
test('Periodic positions are batched and unchanged positions do not trigger disk writes',function()
    local c=fixture();c.core.observe(1);c.core.observe(2)
    assert(c.core.savePositions({1,2},'periodic',false));local before=c.writes
    assert(not c.core.savePositions({1,2},'periodic',false));assert(c.writes==before)
    c.players[1].point.x=12;c.players[2].point.x=22
    assert(c.core.savePositions({1,2},'periodic',false));assert(c.writes==before+1)
end)
test('Logout can use the last server-observed point when identifiers and entity are no longer available',function()
    local c=fixture();c.core.observe(1);c.players[1].disconnected=true
    local position=GetEntityCoords
    GetEntityCoords=function() return nil end
    c.core.drop(1);GetEntityCoords=position
    local record=c.snapshot().characters.oscar_vega
    assert(record.lastLogoutPosition.x==10 and record.lastLogoutPosition.reason=='disconnect')
end)
test('Death is server-verified and deduplicated, separate from live/logout positions and followed by safe respawn',function()
    local c=fixture();c.command('guardarpos',1);c.players[1].point={x=200,y=300,z=40};c.players[1].health=0
    assert(c.core.observe(1));assert(c.core.observe(1))
    local record=c.snapshot().characters.oscar_vega
    assert(#record.deaths==1 and record.lastDeathPosition.x==200 and record.lastValidPosition.x==10 and not record.lastLogoutPosition)
    assert(record.deaths[1].cause=='unknown');c.timers[#c.timers].callback();ack(c,1)
    record=c.snapshot().characters.oscar_vega;assert(record.life=='alive' and record.lastValidPosition.x==OSDevtools.CoreConfig.HospitalSpawn.x and #record.deaths==1)
end)
test('A dead logout records its location without overwriting the last valid live location',function()
    local c=fixture();c.command('guardarpos',1);c.players[1].point={x=200,y=300,z=40};c.players[1].health=0;c.core.observe(1);c.core.drop(1)
    local record=c.snapshot().characters.oscar_vega
    assert(record.lastLogoutPosition.x==200 and record.lastDeathPosition.x==200 and record.lastValidPosition.x==10)
end)
test('Spawn selection, acknowledgements and safe fallback use server-controlled points and single-use contexts',function()
    local c=fixture();assert(c.core.requestSpawn(1,'connect'));local token=ack(c,1);local before=c.writes
    assert(c.core.spawnAck(1,token));assert(c.writes==before)
    assert(not c.core.spawnAck(2,token));assert(not c.core.requestSpawn(999,'connect'))
    assert(c.core.requestSpawn(1,'connect'));local context=c.messages[#c.messages].args[1]
    assert(c.core.spawnFailed(1,context.token));local fallback=c.messages[#c.messages].args[1]
    assert(fallback.position.x==OSDevtools.CoreConfig.DefaultSpawn.x)
    assert(not c.core.spawnFailed(1,fallback.token))
end)
test('Assigned spawn applies on the next spawn; teleport moves only the admin and validates bucket/entity',function()
    local c=fixture();c.command('setspawn',1,{'2'});assert(c.core.requestSpawn(2,'connect'));ack(c,2)
    assert(c.snapshot().characters.client_test.lastValidPosition.x==10)
    c.players[2].point.x=40;c.command('tpusuario',1,{'2'});assert(c.players[1].point.x==41 and c.players[2].point.x==40)
end)
test('Reconnection and restart preserve immutable character IDs, balances and saved positions',function()
    local c=fixture();c.command('guardarpos',1);local id=c.core.dto(1).characterId
    c.players[7]=c.players[1];c.players[1]=nil;assert(c.core.dto(7).characterId==id)
    local restarted=fixture(c.files);assert(restarted.core.dto(1).characterId==id and restarted.snapshot().characters.oscar_vega.lastValidPosition.x==10)
end)
test('Identity exports preserve the legacy alias contract while providing stable-ID DTOs only to trusted readers',function()
    local c=fixture();c.origin='os_inventory';local dto=c.exports.GetActiveCharacter(1)
    assert(dto.characterId:match('^oschar_') and dto.alias=='oscar_vega' and not dto.account and not dto.cash)
    assert(c.exports.GetCharacterId(1)=='oscar_vega' and c.exports.ResolveCharacter('char:'..dto.characterId).alias=='oscar_vega')
    c.origin='untrusted';assert(not c.exports.GetActiveCharacter(1))
end)
test('Corrupt legacy or snapshot files remain untouched and block all writes',function()
    local c=fixture({['data.json']='{corrupt'});local before=c.writes;c.command('setmoney',1,{'2','1'});assert(c.writes==before and c.files['data.json']=='{corrupt')
    c=fixture();local files=c.files;files['data/core.b.json']='{corrupt'
    local restarted=fixture(files);assert(not restarted.core.status() and restarted.writes==0 and files['data/core.b.json']=='{corrupt')
end)
test('Character/state validators reject duplicate IDs, cross-account bindings and deletion of preserved assets',function()
    local c=fixture();local before=c.snapshot();local changed=OSDevtools.Util.copy(before)
    changed.characters.client_test.id=changed.characters.oscar_vega.id;assert(not OSDevtools.State.snapshot(changed))
    changed=OSDevtools.Util.copy(before);changed.characters.client_test.account=changed.characters.oscar_vega.account;assert(not OSDevtools.State.snapshot(changed))
    changed=OSDevtools.Util.copy(before);changed.revision=changed.revision+1;changed.vehicles['1']=nil;assert(not OSDevtools.State.successor(before,changed))
end)
test('Verified integer-native writes work and failed backups cannot activate a migration',function()
    local c=fixture(nil,{nativeWrite=1});assert(c.core.status())
    local raw=json.encode(legacy());local failed=fixture({['data.json']=raw},{failAt=1})
    assert(not failed.core.status() and failed.files['data.json']==raw and not failed.files['data/core.a.json'])
end)
test('Ambiguous writes block further commands and recover only from a verified snapshot on restart',function()
    local c=fixture();c.failWrite=true;c.completeBeforeError=true;c.command('setmoney',1,{'2','123','cash'})
    assert(not c.core.status());local before=c.writes;c.command('setmoney',1,{'2','321','cash'});assert(c.writes==before)
    local restarted=fixture(c.files);assert(restarted.core.status() and restarted.snapshot().characters.client_test.cash==123)
end)
test('External edits are detected before overwriting a slot and partial corruption remains preserved',function()
    local c=fixture();c.files['data/core.a.json']='{external';local before=c.writes;c.command('setmoney',1,{'2','5','cash'})
    assert(not c.core.status() and c.writes==before and c.files['data/core.a.json']=='{external')
    c=fixture();c.failWrite=true;c.partial=true;c.command('setmoney',1,{'2','7','cash'})
    local restarted=fixture(c.files);assert(not restarted.core.status() and restarted.files['data/core.b.json']=='{partial')
end)
test('Shutdown/stop checkpoints preserve positions, while external spawn ownership never forces a spawn',function()
    local c=fixture();c.event('txAdmin:events:serverShuttingDown','monitor',{})
    assert(c.snapshot().characters.oscar_vega.lastPosition.reason=='server_shutdown')
    OSDevtools.SpawnConfig.Mode='external';local before=#c.messages
    assert(not c.core.requestSpawn(1,'connect'));assert(#c.messages==before)
end)
