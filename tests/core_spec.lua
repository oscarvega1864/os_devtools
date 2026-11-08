local test,fixture,legacy=DevtoolsTest.test,DevtoolsTest.fixture,DevtoolsTest.legacy
test('Explicit character and numeric alias syntax cannot be confused with player or asset IDs',function()
    local c=fixture();local id=c.core.dto(2).characterId
    c.command('setmoney',1,{'char:'..id,'900','bank'});assert(c.snapshot().characters.client_test.bank==900)
    c.command('pagar',1,{'char:'..id,'50'});assert(c.snapshot().characters.client_test.cash==350)
    c.command('crearpropiedad',1,{'200','30'});c.command('setpropiedad',1,{'200','char:'..id});local property=c.snapshot().properties['200']
    assert(property.owner=='client_test' and property.position.x==c.players[1].point.x)
    c.command('crearpersonaje',1,{'1','123'});local aliasId=c.snapshot().characters['123'].id
    assert(c.core.resolve('alias:123')=='123' and not c.core.resolve('123') and c.core.resolve('char:'..aliasId)=='123')
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

local function look(model,drawable)
    local components={};for i=1,12 do components[i]={d=i==12 and drawable or 0,t=0,p=0} end
    local overlays={};for i=1,13 do overlays[i]={v=255,o=1,ct=0,c=0,c2=0} end
    local features={};for i=1,20 do features[i]=0 end;features[1]=0.123
    return {model=model,components=components,props={{i=0,d=-1,t=-1},{i=1,d=3,t=0}},
        head={blend={sf=21,ss=4,st=0,kf=21,ks=4,kt=0,sm=0.5,km=0.25,tm=0},features=features,overlays=overlays,hair={c=3,h=5},eyes=2}}
end
test('Appearance is saved per active character, survives restart and travels only with that character spawn',function()
    local c=fixture();c.core.ensure(1)
    assert(c.core.saveAppearance(1,look(1885233650,7)))
    local saved=c.snapshot().characters.oscar_vega.appearance
    assert(saved.model==1885233650 and saved.components[12].d==7 and saved.head.blend.km==0.25)
    local restarted=fixture(c.files);assert(restarted.core.requestSpawn(1,'connect'))
    local context=restarted.messages[#restarted.messages].args[1]
    assert(context.appearance and context.appearance.components[12].d==7);ack(restarted,1)
    restarted.command('crearpersonaje',1,{'1','second_person'});restarted.command('seleccionarpersonaje',1,{'1','second_person'})
    local switched
    for _,m in ipairs(restarted.messages) do if m.name=='osdev:spawnCharacter' then switched=m.args[1] end end
    assert(switched.reason=='character_switch' and switched.appearance==nil)
    assert(restarted.snapshot().characters.oscar_vega.appearance.components[12].d==7)
end)
test('Appearance writes are skipped when unchanged and refused while spawning, dead or invalid',function()
    local c=fixture();c.core.ensure(1)
    assert(c.core.saveAppearance(1,look(1885233650,7)));local before=c.writes
    local ok,detail=c.core.saveAppearance(1,look(1885233650,7));assert(ok and detail=='unchanged' and c.writes==before)
    assert(c.core.requestSpawn(1,'connect'));assert(not c.core.saveAppearance(1,look(1885233650,9)))
    ack(c,1);before=c.writes
    local bad=look(1885233650,7);bad.components[13]={d=0,t=0,p=0};assert(not c.core.saveAppearance(1,bad))
    bad=look(0,7);assert(not c.core.saveAppearance(1,bad))
    bad=look(1885233650,7);bad.head.features[1]=2;assert(not c.core.saveAppearance(1,bad))
    bad=look(1885233650,7);bad.extra='x';assert(not c.core.saveAppearance(1,bad))
    c.players[1].health=0;assert(c.core.observe(1));local afterDeath=c.writes
    assert(not c.core.saveAppearance(1,look(1885233650,9)));assert(c.writes==afterDeath and before+1==afterDeath)
    assert(c.snapshot().characters.oscar_vega.appearance.components[12].d==7)
end)
test('Appearance net event rate-limits automatic saves and answers manual saves',function()
    local c=fixture();c.core.ensure(1)
    source=1;c.net['osdev:saveAppearance'](look(1885233650,7),false);local before=c.writes
    c.clock=c.clock+1000;source=1;c.net['osdev:saveAppearance'](look(1885233650,8),false);assert(c.writes==before)
    c.clock=c.clock+1000;source=1;c.net['osdev:saveAppearance'](look(1885233650,8),true)
    assert(c.writes==before+1 and c.text(1):find('Ropa y aspecto guardados',1,true))
    c.clock=c.clock+500;source=1;c.net['osdev:saveAppearance'](look(1885233650,9),true);assert(c.writes==before+1)
end)
test('Stored data with a corrupted appearance is rejected instead of loaded or overwritten',function()
    local c=fixture();c.core.ensure(1);assert(c.core.saveAppearance(1,look(1885233650,7)))
    local data=c.snapshot();data.characters.oscar_vega.appearance.components[1].d=-5
    assert(not OSDevtools.State.snapshot(data))
end)

local MENYOO=[[<?xml version="1.0" encoding="ISO-8859-1"?>
<OutfitPedData><ModelHash>0x705E61F2</ModelHash><PedProperties><PedProps><_0>5,2</_0><_1>-1,-1</_1><_6>-1,-1</_6></PedProps>
<PedComps><_0>0,0</_0><_2>21,0</_2><_11>15,3</_11></PedComps><HeadFeatures WasInArray="true"><ShapeAndSkinTone><ShapeFatherId>3</ShapeFatherId><ShapeMotherId>4</ShapeMotherId><ShapeOverrideId>0</ShapeOverrideId><ToneFatherId>5</ToneFatherId><ToneMotherId>0</ToneMotherId><ToneOverrideId>1</ToneOverrideId><ShapeVal>0.95</ShapeVal><ToneVal>0</ToneVal><OverrideVal>0</OverrideVal><IsP>0</IsP></ShapeAndSkinTone>
<HairColour>58</HairColour><HairColourStreaks>3</HairColourStreaks><EyeColour>2</EyeColour><FacialFeatures><_0>0.25</_0><_19>-1</_19></FacialFeatures>
<Overlays><_0 index="255" colour="0" colourSecondary="0" opacity="1"/><_1 index="7" colour="4" colourSecondary="0" opacity="1"/><_7 index="0" colour="0" colourSecondary="0" opacity="0.2"/></Overlays></HeadFeatures>
<TattooLogoDecals><:anonymous collection="0x23a7a83b" value="0x13e7aad"/></TattooLogoDecals></PedProperties></OutfitPedData>]]
test('Menyoo XML maps model, clothes, props, head blend, features, overlays, hair and eyes',function()
    local a,skipped=OSDevtools.AppearanceXml.parse(MENYOO)
    assert(a and skipped=='tatuajes/logos' and a.model==1885233650)
    assert(a.components[3].d==21 and a.components[12].d==15 and a.components[12].t==3 and a.components[5].d==0)
    assert(a.props[1].i==0 and a.props[1].d==5 and a.props[1].t==2 and a.props[2].d==-1)
    local b=a.head.blend;assert(b.sf==3 and b.ss==4 and b.kf==5 and b.kt==1 and b.sm==0.95 and b.km==0)
    assert(a.head.features[1]==0.25 and a.head.features[20]==-1 and #a.head.features==20)
    assert(a.head.overlays[1].v==255 and a.head.overlays[2].v==7 and a.head.overlays[2].c==4 and a.head.overlays[2].ct==1)
    assert(a.head.overlays[8].o==0.2 and a.head.overlays[13].v==255 and #a.head.overlays==13)
    assert(a.head.hair.c==58 and a.head.hair.h==3 and a.head.eyes==2)
    local female=OSDevtools.AppearanceXml.parse(MENYOO:gsub('0x705E61F2','0x9C9EFFD8'))
    assert(female.model==-1667301416)
    assert(not OSDevtools.AppearanceXml.parse('<root/>'))
    assert(not OSDevtools.AppearanceXml.parse(MENYOO:gsub('<HairColour>58','<HairColour>99')))
end)
test('importarropa requires identity permission, writes an audited import and applies it to the connected owner',function()
    local c=fixture();c.core.ensure(1);c.core.ensure(2);c.files['data/look_test.xml']=MENYOO
    local before=c.writes;c.command('importarropa',2,{'1','look_test'});assert(c.writes==before)
    c.command('importarropa',1,{'1','../core.a'});c.command('importarropa',1,{'1','missing'});assert(c.writes==before)
    c.command('importarropa',1,{'2','look_test.xml'})
    local d=c.snapshot();assert(d.characters.client_test.appearance.head.hair.c==58 and not d.characters.oscar_vega.appearance)
    assert(d.audit[#d.audit].operation:find('import_appearance',1,true))
    local applied=false;for _,m in ipairs(c.messages) do if m.name=='osdev:applyAppearance' and m.source==2 then applied=true end end;assert(applied)
    assert(c.text(1):find('no incluye: tatuajes',1,true))
    source=2;local count=c.writes;c.net['osdev:saveAppearance'](d.characters.client_test.appearance,false);c.clock=c.clock+9000
    local old=OSDevtools.Util.copy(d.characters.client_test.appearance);old.components[12].d=1
    source=2;c.net['osdev:saveAppearance'](old,false);assert(c.writes==count)
    c.clock=c.clock+16000;source=2;c.net['osdev:saveAppearance'](old,false);assert(c.writes==count+1)
end)

test('crearpropiedad takes only number and price, stores exact position and heading without owner, and rejects duplicates',function()
    local c=fixture();c.players[1].point={x=123.5,y=-45.25,z=30};c.players[1].h=271.5
    local before=c.writes;c.command('crearpropiedad',1,{'200','casa','villa','50000'});assert(c.writes==before)
    c.command('crearpropiedad',1,{'200','50000'})
    local p=c.snapshot().properties['200'];assert(p.id==200 and p.price==50000 and p.owner==nil and p.name==nil and p.type==nil)
    assert(p.position.x==123.5 and p.position.y==-45.25 and p.position.h==271.5)
    assert(c.text(1):find('Propiedad #200 creada',1,true));before=c.writes
    c.command('crearpropiedad',1,{'200','90'});assert(c.writes==before and c.text(1):find('La propiedad ID 200 ya existe.',1,true))
    c.command('setpropiedad',1,{'200','2'});assert(c.snapshot().properties['200'].owner=='client_test')
    c.command('misbienes',2);assert(c.text(2):find('Propiedad #200',1,true))
end)
test('crearnegocio uses fixed categories, multi-word names, automatic IDs and no owner',function()
    local c=fixture();local before=c.writes
    c.command('crearnegocio',1,{'casino','Royal','100'});c.command('crearnegocio',1,{'bar','Vanilla'});c.command('crearnegocio',1,{'bar','~r~X','10'})
    assert(c.writes==before)
    c.command('crearnegocio',1,{'LTD','LTD','Mirror','Park','30000'})
    local b=c.snapshot().businesses['2'];assert(b.type=='ltd' and b.name=='LTD Mirror Park' and b.price==30000 and b.owner==nil and b.position.h==90)
    assert(c.snapshot().businesses['1'].name=='market' and c.snapshot().businesses['1'].owner=='client_test')
    c.command('crearnegocio',1,{'discoteca','Vanilla','50000'});assert(c.snapshot().businesses['3'].type=='discoteca' and c.snapshot().nextBusiness==4)
    c.command('setnegocio',1,{'3','oscar_vega'});assert(c.snapshot().businesses['3'].owner=='oscar_vega')
end)
test('Business blips reach every player on change, on request, and are not resent when nothing visible changed',function()
    local c=fixture();local function last(source)
        for i=#c.messages,1,-1 do local m=c.messages[i];if m.name=='osdev:businessBlips' and m.source==source then return m.args[1],i end end
    end
    c.command('crearnegocio',1,{'medico','Pillbox','1'})
    local list=last(1);local other=last(2);assert(list and other and #list==1 and list[1].type=='medico' and list[1].name=='Pillbox')
    local _,index=last(2);c.core.savePositions({1,2},'manual',true);local _,after=last(2);assert(index==after)
    c.clock=c.clock+6000;source=2;c.net['osdev:requestBusinessBlips']();local _,requested=last(2);assert(requested>after)
    source=2;c.net['osdev:requestBusinessBlips']();local _,limited=last(2);assert(limited==requested)
end)
test('Legacy properties with type and name remain valid and keep their metadata',function()
    local data=legacy();data.properties['7']={id=7,type='casa',name='villa',price=30,position={x=1,y=2,z=3,h=0,bucket=0}}
    local c=fixture({['data.json']=json.encode(data)});local p=c.snapshot().properties['7']
    assert(p.type=='casa' and p.name=='villa')
    c.command('listpropiedades',1);assert(c.text(1):find('Propiedad #7 (villa)',1,true))
end)

local function answer(c,source,types)
    for i=#c.messages,1,-1 do local m=c.messages[i]
        if m.name=='osdev:inspectVehicleModels' and m.source==source then _G.source=source;c.net['osdev:vehicleModelTypes'](m.args[1],types);return true end
    end
    error('No inspection request')
end
local function entities(c) local n=0;for _ in pairs(c.world) do n=n+1 end;return n end
test('crearvehiculo is created by the server ahead of the admin after a model type check, with plate, colours and state bag',function()
    local c=fixture();c.command('crearvehiculo',1,{'rebla','1','1','fijo','1'});assert(entities(c)==0)
    answer(c,1,{rebla='automobile'})
    local v=c.snapshot().vehicles['2'];assert(v.vtype=='automobile' and v.fixed and v.owner=='oscar_vega' and v.plate=='OS000002')
    assert(math.abs(v.position.x-6)<0.001 and math.abs(v.position.y-20)<0.001 and v.position.h==90)
    local e=next(c.world);local w=c.world[e]
    assert(w.kind=='automobile' and w.plate=='OS000002' and w.orphan==2 and w.colours[1]==1 and w.state.osdev.id==2)
    local before=c.writes;c.command('crearvehiculo',1,{'notacar','0'});answer(c,1,{notacar=false})
    assert(c.writes==before and entities(c)==1 and not c.snapshot().vehicles['3'])
    source=2;c.net['osdev:vehicleModelTypes']('1:1',{rebla='automobile'});assert(c.writes==before)
end)
test('Fixed vehicles are recreated after a server restart at their last saved position and never duplicated on resource restart',function()
    local c=fixture();c.command('crearvehiculo',1,{'rebla','1','1','fijo'});answer(c,1,{rebla='automobile'})
    c.command('crearvehiculo',1,{'faggio','0','temporal'});answer(c,1,{faggio='bike'});assert(entities(c)==2)
    local e;for handle,w in pairs(c.world) do if w.plate=='OS000002' then e=handle end end
    c.world[e].point={x=500,y=600,z=40};c.world[e].h=180
    assert(OSDevtools.VehicleRuntime.savePositions('periodic'));local before=c.writes
    assert(not OSDevtools.VehicleRuntime.savePositions('periodic'));assert(c.writes==before)
    local p=c.snapshot().vehicles['2'].position;assert(p.x==500 and p.y==600 and p.h==180)
    c.event('onResourceStop',nil,'os_devtools');assert(entities(c)==1 and c.world[e])
    local again=fixture(c.files,{world=c.world,nextEntity=c.nextEntity});assert(entities(again)==1)
    local server=fixture(c.files);assert(entities(server)==1)
    local _,w=next(server.world);assert(w.plate=='OS000002' and w.point.x==500 and w.h==180 and w.kind=='automobile')
end)
test('Old fixed vehicles without a type are completed by an admin client, persisted and then restored',function()
    local data=legacy();data.vehicles['1'].position={x=1,y=2,z=3,h=0,bucket=0}
    local c=fixture({['data.json']=json.encode(data)});assert(entities(c)==0)
    source=2;c.net['osdev:vehiclesReady']();for _,m in ipairs(c.messages) do assert(m.name~='osdev:inspectVehicleModels') end
    source=1;c.net['osdev:vehiclesReady']();answer(c,1,{sultan='automobile'})
    assert(c.snapshot().vehicles['1'].vtype=='automobile' and entities(c)==1)
    local _,w=next(c.world);assert(w.plate=='OS000001' and w.point.x==1)
end)
test('recuperarvehiculo refuses duplicates and recreates a missing vehicle ahead of the admin',function()
    local c=fixture();c.command('crearvehiculo',1,{'rebla','1','1','fijo'});answer(c,1,{rebla='automobile'})
    c.command('recuperarvehiculo',1,{'2'});assert(entities(c)==1 and c.text(1):find('ya existe en el mundo',1,true))
    for handle in pairs(c.world) do c.world[handle]=nil end
    c.players[1].point={x=100,y=200,z=30};c.command('recuperarvehiculo',1,{'2'})
    assert(entities(c)==1 and math.abs(c.snapshot().vehicles['2'].position.x-96)<0.001)
    c.command('recuperarvehiculo',1,{'1'});answer(c,1,{sultan='automobile'})
    assert(entities(c)==2 and c.snapshot().vehicles['1'].vtype=='automobile')
end)
test('Without OneSync no vehicle is created or registered',function()
    local c=fixture(nil,{onesync='off'});local before=c.writes
    c.command('crearvehiculo',1,{'rebla','1'});assert(c.writes==before and entities(c)==0)
    for _,m in ipairs(c.messages) do assert(m.name~='osdev:inspectVehicleModels') end
end)
