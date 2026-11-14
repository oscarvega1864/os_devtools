-- Selector de personaje: lista propia, eleccion validada en servidor, creacion propia y cambio en juego.
local test,fixture=DevtoolsTest.test,DevtoolsTest.fixture
local A='license:'..string.rep('a',40)
local function net(c,name,player,...) source=player;c.clock=c.clock+2000;c.net[name](...) end
local function last(c,name,player)
    for i=#c.messages,1,-1 do local m=c.messages[i];if m.name==name and m.source==player then return m.args[1],i end end
end
local function ack(c,player)
    local context=last(c,'osdev:spawnCharacter',player);assert(context,'No spawn context')
    c.players[player].point=OSDevtools.Util.copy(context.position);c.players[player].h=context.position.h;c.players[player].health=200
    assert(c.core.spawnAck(player,context.token));return context
end
local function withSecond(c) c.command('crearpersonaje',1,{'1','second_person'});assert(c.snapshot().characters.second_person) end

test('Connect selection lists only own characters, spawns nothing and never leaks account identifiers',function()
    local c=fixture();withSecond(c)
    net(c,'osdev:requestCharacterSelect',1)
    local payload=last(c,'osdev:characterSelect',1);assert(payload and payload.mode=='connect' and payload.allowCreate)
    assert(#payload.characters==2 and payload.characters[1].alias=='oscar_vega' and payload.characters[1].active)
    for _,row in ipairs(payload.characters) do assert(row.alias~='client_test') end
    assert(not json.encode(payload):find('license',1,true) and not last(c,'osdev:spawnCharacter',1))
    assert(c.core.isSelecting(1) and not c.core.isSelecting(2))
end)

test('While selecting, the placeholder ped never overwrites positions or records a death',function()
    local c=fixture();net(c,'osdev:requestCharacterSelect',1)
    local before=c.snapshot().characters.oscar_vega.lastValidPosition;local writes=c.writes
    c.players[1].point={x=500,y=500,z=50};c.players[1].health=0
    assert(c.core.observe(1));c.core.savePositions({1},'periodic',true)
    source=1;for _,fn in ipairs(c.events.playerDropped) do fn() end
    local after=c.snapshot().characters.oscar_vega
    assert(c.writes==writes and after.life~='dead' and OSDevtools.Util.equal(before,after.lastValidPosition))
end)

test('Choosing validates ownership on the server and spawns the chosen character at its own position',function()
    local c=fixture();withSecond(c);net(c,'osdev:requestCharacterSelect',1)
    local writes=c.writes
    net(c,'osdev:chooseCharacter',1,'client_test')
    assert(last(c,'osdev:characterSelectResult',1).ok==false and c.writes==writes and not last(c,'osdev:spawnCharacter',1))
    net(c,'osdev:chooseCharacter',1,'second_person')
    assert(last(c,'osdev:characterSelectResult',1).ok and c.snapshot().bindings[A]=='second_person')
    local context=ack(c,1);assert(context.reason=='character_select' and context.position.x==OSDevtools.CoreConfig.DefaultSpawn.x)
    assert(not c.core.isSelecting(1) and c.core.hasSpawned(1))
    -- La posicion del personaje anterior no se toca: no habia ped real que guardar.
    assert(c.snapshot().characters.oscar_vega.lastPosition.x==10)
end)

test('Choosing the bound character keeps its last valid position and a second request no longer opens selection',function()
    local c=fixture();net(c,'osdev:requestCharacterSelect',1);net(c,'osdev:chooseCharacter',1,'oscar_vega')
    local context=ack(c,1);assert(context.position.x==10 and context.position.y==20)
    local count=#c.messages;net(c,'osdev:requestCharacterSelect',1)
    for i=count+1,#c.messages do assert(c.messages[i].name~='osdev:characterSelect') end
    net(c,'osdev:chooseCharacter',1,'oscar_vega');assert(last(c,'osdev:characterSelectResult',1).ok)
end)

test('Self-service creation validates names and duplicates, then enters with the new character and asks for its design',function()
    local c=fixture();net(c,'osdev:requestCharacterSelect',1)
    for _,args in ipairs({{'A','Lopez'},{'Ana','L'},{'An4','Lopez'},{'Ana_x','Lopez'},{'Oscar','Vega'},{string.rep('a',17),'Lopez'}}) do
        local writes=c.writes;net(c,'osdev:createOwnCharacter',1,args[1],args[2])
        assert(last(c,'osdev:characterSelectResult',1).ok==false and c.writes==writes,args[1])
    end
    net(c,'osdev:createOwnCharacter',1,'Ana','Lopez')
    local d=c.snapshot();assert(d.characters.ana_lopez and d.characters.ana_lopez.account==A and d.bindings[A]=='ana_lopez')
    assert(last(c,'osdev:characterSelectResult',1).ok and not c.core.isSelecting(1))
    local context=ack(c,1);assert(context.design==true and context.appearance==nil and context.reason=='character_select')
    -- El personaje anterior conserva su posicion: en la entrada no habia ped real.
    assert(c.snapshot().characters.oscar_vega.lastPosition.x==10)
end)

test('Creation respects cooldown and the per-account limit; in game it switches with the live position saved',function()
    local c=fixture();net(c,'osdev:requestCharacterSelect',1);net(c,'osdev:chooseCharacter',1,'oscar_vega');ack(c,1)
    c.players[1].point={x=55,y=66,z=30}
    net(c,'osdev:createOwnCharacter',1,'Eva','Diaz')
    local d=c.snapshot();assert(d.bindings[A]=='eva_diaz' and d.characters.oscar_vega.lastPosition.x==55)
    assert(last(c,'osdev:spawnCharacter',1).design==true);ack(c,1)
    source=1;c.clock=c.clock+1500;c.net['osdev:createOwnCharacter']('Luis','Gil')
    assert(not c.snapshot().characters.luis_gil and last(c,'osdev:characterSelectResult',1).ok==false)
    local max=OSDevtools.CoreConfig.CharacterSelect.MaxCharacters
    for i=3,max do c.clock=c.clock+10000;source=1;c.net['osdev:createOwnCharacter']('Extra','P'..string.rep('x',i));ack(c,1) end
    local owned=0;for _,ch in pairs(c.snapshot().characters) do if ch.account==A then owned=owned+1 end end;assert(owned==max)
    c.clock=c.clock+10000;source=1;c.net['osdev:createOwnCharacter']('Over','Limit')
    assert(not c.snapshot().characters.over_limit and last(c,'osdev:characterSelectResult',1).ok==false)
end)

test('A character with saved appearance never asks for the designer, and the designer saves through the validated path',function()
    local c=fixture();net(c,'osdev:requestCharacterSelect',1);net(c,'osdev:createOwnCharacter',1,'Ana','Lopez');ack(c,1)
    local components={};for i=1,12 do components[i]={d=0,t=0,p=0} end
    source=1;c.clock=c.clock+10000;c.net['osdev:saveAppearance']({model=1885233650,components=components,props={}},true)
    assert(c.snapshot().characters.ana_lopez.appearance.model==1885233650)
    source=1;c.clock=c.clock+10000;c.net['osdev:saveAppearance']({model=0,components=components,props={}},true) -- invalido: rechazado
    assert(c.snapshot().characters.ana_lopez.appearance.model==1885233650)
    c.command('personaje',1,{'oscar_vega'});ack(c,1);c.command('personaje',1,{'ana_lopez'})
    assert(last(c,'osdev:spawnCharacter',1).design==nil)
end)

test('In game, /personajes opens the switch list and choosing saves the live position before switching',function()
    local c=fixture();withSecond(c);net(c,'osdev:requestCharacterSelect',1);net(c,'osdev:chooseCharacter',1,'oscar_vega');ack(c,1)
    c.command('personajes',1);local payload=last(c,'osdev:characterSelect',1);assert(payload.mode=='switch')
    c.players[1].point={x=77,y=88,z=30}
    net(c,'osdev:chooseCharacter',1,'second_person')
    local d=c.snapshot();assert(d.bindings[A]=='second_person' and d.characters.oscar_vega.lastPosition.x==77)
    assert(last(c,'osdev:spawnCharacter',1).reason=='character_switch')
end)

test('Disabled selector keeps the direct connect spawn',function()
    local c=fixture();OSDevtools.CoreConfig.CharacterSelect.Enabled=false
    local ok,err=pcall(function()
        net(c,'osdev:requestCharacterSelect',1)
        assert(not last(c,'osdev:characterSelect',1) and last(c,'osdev:spawnCharacter',1).reason=='connect')
    end)
    OSDevtools.CoreConfig.CharacterSelect.Enabled=true;assert(ok,err)
end)

test('Loading preview shows only the connecting account own bound character and is restricted to authorized readers',function()
    local c=fixture();withSecond(c)
    c.origin='os_loadscreen';local preview=c.exports.GetLoadingPreview(1)
    assert(preview.alias=='oscar_vega' and preview.characters==2 and preview.job=='gruppe6' and not json.encode(preview):find('license',1,true))
    c.players[9]={identifiers={'license:'..string.rep('c',40)},point={x=1,y=2,z=3},h=0,bucket=0}
    local fresh=c.exports.GetLoadingPreview(9);assert(fresh.characters==0 and fresh.alias==nil and not c.snapshot().bindings['license:'..string.rep('c',40)])
    c.origin='untrusted';assert(c.exports.GetLoadingPreview(1)==nil);c.origin=nil
end)

test('Weapons are saved per character, given back on spawn, ignored while switching and validated',function()
    local c=fixture();withSecond(c);net(c,'osdev:requestCharacterSelect',1);net(c,'osdev:chooseCharacter',1,'oscar_vega')
    local context=ack(c,1);assert(type(context.weapons)=='table' and #context.weapons==0)
    local list={{name='WEAPON_PISTOL',ammo=60,components={'COMPONENT_AT_PI_SUPP','COMPONENT_AT_PI_FLSH'}},{name='WEAPON_KNIFE',ammo=0,tint=0}}
    net(c,'osdev:weapons',1,list)
    local saved=c.snapshot().characters.oscar_vega.weapons
    assert(saved and #saved==2 and saved[1].name=='WEAPON_KNIFE' and saved[2].ammo==60 and saved[2].components[1]=='COMPONENT_AT_PI_FLSH' and saved[1].tint==nil)
    local writes=c.writes;net(c,'osdev:weapons',1,{list[2],list[1]});assert(c.writes==writes) -- mismo equipo: no se reescribe
    -- Rechazos: arma o accesorio fuera de la lista, municion fuera de rango, duplicados, campos extra.
    for _,bad in ipairs({{{name='WEAPON_RAILGUN_FAKE',ammo=1}},{{name='WEAPON_PISTOL',ammo=-1}},{{name='WEAPON_PISTOL',ammo=99999}},
        {{name='WEAPON_PISTOL',ammo=1},{name='WEAPON_PISTOL',ammo=2}},{{name='WEAPON_PISTOL',ammo=1,components={'COMPONENT_FAKE'}}},{{name='WEAPON_PISTOL',ammo=1,extra=true}},'x'}) do
        net(c,'osdev:weapons',1,bad);assert(#c.snapshot().characters.oscar_vega.weapons==2)
    end
    -- Cambio de personaje: lo que llegue antes de aparecer el nuevo no se guarda en ninguno.
    net(c,'osdev:requestCharacterSelect',1);net(c,'osdev:chooseCharacter',1,'second_person')
    net(c,'osdev:weapons',1,{{name='WEAPON_RPG',ammo=5}})
    assert(c.snapshot().characters.second_person.weapons==nil and #c.snapshot().characters.oscar_vega.weapons==2)
    local second=ack(c,1);assert(#second.weapons==0)
    net(c,'osdev:weapons',1,{{name='WEAPON_BAT',ammo=0}});assert(c.snapshot().characters.second_person.weapons[1].name=='WEAPON_BAT')
    -- De vuelta al primero: aparece con sus armas.
    net(c,'osdev:requestCharacterSelect',1);net(c,'osdev:chooseCharacter',1,'oscar_vega')
    local back=ack(c,1);assert(#back.weapons==2 and back.weapons[2].name=='WEAPON_PISTOL')
    local read=c.core.weapons(1);assert(#read==2 and read[2].name=='WEAPON_PISTOL' and read[2].ammo==60 and read[1].components==nil)
    -- Vaciar el equipo borra la lista guardada.
    net(c,'osdev:weapons',1,{});assert(c.snapshot().characters.oscar_vega.weapons==nil)
end)
