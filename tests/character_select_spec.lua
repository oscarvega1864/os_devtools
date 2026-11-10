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

test('Self-service creation validates names, duplicates, the per-account limit and cooldown',function()
    local c=fixture();net(c,'osdev:requestCharacterSelect',1)
    for _,args in ipairs({{'A','Lopez'},{'Ana','L'},{'An4','Lopez'},{'Ana_x','Lopez'},{'Oscar','Vega'},{string.rep('a',17),'Lopez'}}) do
        local writes=c.writes;net(c,'osdev:createOwnCharacter',1,args[1],args[2])
        assert(last(c,'osdev:characterSelectResult',1).ok==false and c.writes==writes,args[1])
    end
    net(c,'osdev:createOwnCharacter',1,'Ana','Lopez')
    local d=c.snapshot();assert(d.characters.ana_lopez and d.characters.ana_lopez.account==A and d.bindings[A]=='oscar_vega')
    local payload=last(c,'osdev:characterSelect',1);assert(#payload.characters==2 and payload.message:find('ana_lopez',1,true))
    source=1;c.clock=c.clock+1500;c.net['osdev:createOwnCharacter']('Eva','Diaz')
    assert(not c.snapshot().characters.eva_diaz and last(c,'osdev:characterSelectResult',1).ok==false)
    local max=OSDevtools.CoreConfig.CharacterSelect.MaxCharacters
    for i=3,max do c.clock=c.clock+10000;source=1;c.net['osdev:createOwnCharacter']('Extra','P'..string.rep('x',i)) end
    local owned=0;for _,ch in pairs(c.snapshot().characters) do if ch.account==A then owned=owned+1 end end;assert(owned==max)
    c.clock=c.clock+10000;source=1;c.net['osdev:createOwnCharacter']('Over','Limit')
    assert(not c.snapshot().characters.over_limit and last(c,'osdev:characterSelectResult',1).ok==false)
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
