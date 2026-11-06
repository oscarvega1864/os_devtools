local RESOURCE = GetCurrentResourceName()
local DATA_FILE = 'data/state.json'
local db = { players = {}, properties = {}, businesses = {}, vehicles = {}, counters = {business=0, vehicle=0}, audit={} }
local active = {} -- numeric vehicle id -> entity handle, runtime only
local sessions = {} -- source -> character id, runtime only
local pendingSpawn = {}

local function save()
    local encoded = json.encode(db)
    if not encoded or not SaveResourceFile(RESOURCE, DATA_FILE, encoded, -1) then
        print('[os_devtools] ERROR: no se pudo guardar '..DATA_FILE)
        return false
    end
    return true
end

local function initialize()
    local content = LoadResourceFile(RESOURCE, DATA_FILE)
    if content and #content > 0 then
        local ok, decoded = pcall(json.decode, content)
        if ok and type(decoded) == 'table' then db = decoded else print('[os_devtools] ERROR: JSON invalido; NO se sobrescribira.'); return false end
    end
    db.players = db.players or {}; db.properties = db.properties or {}; db.businesses = db.businesses or {}; db.vehicles = db.vehicles or {}
    db.counters = db.counters or {}; db.counters.business = db.counters.business or 0; db.counters.vehicle = db.counters.vehicle or 0
    db.audit = db.audit or {}
    return true
end
local validDb = initialize()
local function notify(src, message)
    if src == 0 then print('[os_devtools] '..message) else TriggerClientEvent('osdev:msg', src, message) end
end
local function admin(src)
    return src == 0 or IsPlayerAceAllowed(src, 'osdev.admin')
end
local function guard(src)
    if not validDb then notify(src,'Datos no disponibles; revisa data/state.json.'); return false end
    if not admin(src) then notify(src,'Sin permisos ACE osdev.admin.'); return false end
    return true
end
local function audit(src, kind, details)
    db.audit[#db.audit+1] = { t=os.time(), actor=(src==0 and 'console' or tostring(src)), kind=kind, details=details }
    if #db.audit > 300 then table.remove(db.audit, 1) end
end
local function positiveId(v)
    local n = tonumber(v)
    if not n or n < 1 or n % 1 ~= 0 or n > 2147483647 then return nil end
    return math.floor(n)
end
local function amount(v)
    if type(v) ~= 'string' then return nil end
    local cleaned = v:gsub('%$', '')
    if not cleaned:match('^%d+$') then return nil end
    local n = tonumber(cleaned)
    if not n or n > 1000000000 then return nil end
    return n
end
local function playerKey(alias)
    if type(alias) ~= 'string' or not alias:match('^[%w_%-]+$') or #alias > 48 or #alias < 2 then return nil end
    return alias:lower()
end
local function person(alias)
    local key = playerKey(alias)
    return key and db.players[key], key
end
local function ensureIdentity(src)
    local key = sessions[src]
    if key and db.players[key] then return key end
    if src == 0 then return nil end
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:sub(1,8) == 'license:' then
            for id,p in pairs(db.players) do if p.license == identifier then sessions[src]=id; return id end end
            return nil
        end
    end
    return nil
end
local function coords(src)
    if src == 0 then return nil end
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return {x=c.x,y=c.y,z=c.z,heading=GetEntityHeading(ped),bucket=GetPlayerRoutingBucket(src)}
end
local function reg(command, handler, isPublic)
    RegisterCommand(command, function(src,args)
        if not isPublic and not guard(src) then return end
        local ok,err = pcall(handler,src,args)
        if not ok then print('[os_devtools] '..command..': '..tostring(err)); notify(src,'Error interno. Revisa consola.') end
    end, false)
end
local function ownList(src, key)
    if not key then notify(src,'No tienes personaje de prueba. Usa /setpj <alias> <idJugador> (admin).'); return end
    local p = db.players[key]
    notify(src,'BIENES de '..key..' | efectivo $'..p.cash..' | banco $'..p.bank..' | trabajo '..p.job..'/'..p.grade..' | servicio '..tostring(p.duty))
    local found = 0
    for _,item in pairs(db.vehicles) do if item.owner == key then found=found+1; notify(src,'VEH # '..item.id..' - '..item.model..' ['..item.plate..'] ('..item.mode..')') end end
    for _,item in pairs(db.businesses) do if item.owner == key then found=found+1; notify(src,'NEG # '..item.id..' - '..item.type..' '..item.name) end end
    for _,item in pairs(db.properties) do if item.owner == key then found=found+1; notify(src,'PROP # '..item.id..' - '..item.type..' '..item.name) end end
    if found==0 then notify(src,'No hay bienes asignados.') end
end

reg('crearpj', function(src,a)
    local key=playerKey(a[1]); if not key then return notify(src,'Uso: /crearpj <alias>') end
    if db.players[key] then return notify(src,'Ya existe el personaje '..key) end
    db.players[key]={name=a[1], cash=0,bank=0,job='unemployed',grade='0',duty=false,license=nil,created=os.time()}
    audit(src,'crearpj',key); save(); notify(src,'Personaje creado: '..key..'. Usa /setpj '..key..' <idJugador>.')
end)
reg('setpj',function(src,a)
    local p,key=person(a[1]); local target=tonumber(a[2]) or src
    if not p or not target or target<=0 or not GetPlayerName(target) then return notify(src,'Uso: /setpj <aliasExistente> <idJugadorConectado>') end
    local license
    for _,v in ipairs(GetPlayerIdentifiers(target)) do if v:sub(1,8)=='license:' then license=v; break end end
    if not license then return notify(src,'Jugador sin licencia FiveM. No vinculado.') end
    for id,other in pairs(db.players) do if id~=key and other.license==license then other.license=nil end end
    p.license=license; sessions[target]=key
    audit(src,'setpj',key..' -> jugador '..target); save(); notify(src,'Jugador '..target..' vinculado a '..key); notify(target,'Personaje de pruebas activo: '..key)
end)
reg('setuser',function(src,a)
    notify(src,'/setuser no modifica licencias ni permisos ACE. Usa /crearpj y /setpj; permisos en server.cfg.')
end)
reg('setjob',function(src,a)
    local p,key=person(a[1]); if not p or not a[2] or not a[3] then return notify(src,'Uso: /setjob <personaje> <job> <rango>') end
    p.job=a[2]; p.grade=a[3]; p.duty=false; audit(src,'setjob',key..' '..a[2]..' '..a[3]); save(); notify(src,'Job actualizado: '..key)
end)
reg('setduty',function(src,a)
    local p,key=person(a[1]); if not p or (a[2]~='on' and a[2]~='off') then return notify(src,'Uso: /setduty <personaje> on|off') end
    p.duty=a[2]=='on'; audit(src,'setduty',key..' '..a[2]); save(); notify(src,'Servicio '..a[2]..' para '..key)
end)
local function accountCmd(name,mode)
    reg(name,function(src,a)
        local p,key=person(a[1]); local n=amount(a[2]); local acct=a[3] or 'bank'
        if not p or not n or (acct~='bank' and acct~='cash') then return notify(src,'Uso: /'..name..' <personaje> <cantidad> [cash|bank]') end
        if mode=='set' then p[acct]=n elseif mode=='add' then p[acct]=p[acct]+n else
            if p[acct]<n then return notify(src,'Fondos insuficientes; operacion cancelada.') end
            p[acct]=p[acct]-n
        end
        audit(src,name,key..' '..n..' '..acct); save(); notify(src,key..' '..acct..' = $'..p[acct])
    end)
end
accountCmd('setmoney','set'); accountCmd('givemoney','add'); accountCmd('removemoney','remove')
reg('verdinero',function(src,a)
    local key=a[1] and playerKey(a[1]) or ensureIdentity(src); local p=key and db.players[key]
    if not p then return notify(src,'Personaje no encontrado.') end
    notify(src,key..' efectivo: $'..p.cash..' | banco: $'..p.bank)
end,true)

reg('crearpropiedad',function(src,a)
    local id=positiveId(a[1]); local c=coords(src)
    if not id or not a[2] or not a[3] or not amount(a[4]) or not c then return notify(src,'Uso en juego: /crearpropiedad <id> <tipo> <nombre> <precio>') end
    if db.properties[tostring(id)] then return notify(src,'ERROR: ya existe la propiedad ID '..id) end
    db.properties[tostring(id)]={id=id,type=a[2],name=a[3],price=amount(a[4]),owner=nil,location=c,created=os.time(),accesses={}}
    audit(src,'crearpropiedad',tostring(id)); save(); notify(src,'Propiedad # '..id..' creada en tu posicion.')
end)
reg('crearnegocio',function(src,a)
    local c=coords(src)
    if not a[1] or not a[2] or not amount(a[4] or a[3]) or not c then return notify(src,'Uso: /crearnegocio <tipo> <nombre> <personaje|ninguno> <precio>') end
    local owner=nil
    if a[3]~='ninguno' then if not person(a[3]) then return notify(src,'Propietario no existe. Usa /crearpj.') end; owner=playerKey(a[3]) end
    local id=db.counters.business+1; db.counters.business=id
    db.businesses[tostring(id)]={id=id,type=a[1],name=a[2],price=amount(a[4] or a[3]),owner=owner,location=c,created=os.time(),accesses={}}
    audit(src,'crearnegocio',tostring(id)); save(); notify(src,'Negocio # '..id..' creado.')
end)
local function assignment(cmd,collection)
    reg(cmd,function(src,a)
        local id=positiveId(a[1]); local p,key=person(a[2]); local item=id and db[collection][tostring(id)]
        if not item or not p then return notify(src,'Uso: /'..cmd..' <idExistente> <personajeExistente>') end
        item.owner=key; audit(src,cmd,tostring(id)..' '..key); save(); notify(src,collection..' # '..id..' asignado a '..key)
    end)
end
assignment('setpropiedad','properties');assignment('setnegocio','businesses');assignment('setvehiculo','vehicles')
local function listing(name,collection)
    reg(name,function(src,a)
        local count=0
        for _,v in pairs(db[collection]) do
            count=count+1
            if count<=40 then notify(src,'#'..v.id..' '..(v.name or v.model)..' | propietario: '..(v.owner or 'sin asignar')) end
        end
        notify(src,'Total '..collection..': '..count..(count>40 and ' (solo primeros 40)' or ''))
    end)
end
listing('listpropiedades','properties');listing('listnegocios','businesses');listing('listvehiculos','vehicles')
local function info(name,collection)
    reg(name,function(src,a)
        local id=positiveId(a[1]); local v=id and db[collection][tostring(id)]
        if not v then return notify(src,'No existe ese ID. Uso: /'..name..' <id>') end
        notify(src, json.encode(v))
    end)
end
info('infopropiedad','properties');info('infonegocio','businesses');info('infovehiculo','vehicles')
reg('mispropiedades',function(src,a) ownList(src,ensureIdentity(src)) end,true)
reg('misbienes',function(src,a) ownList(src,ensureIdentity(src)) end,true)
reg('verpropiedades',function(src,a) local p,key=person(a[1]); if not p then return notify(src,'Uso: /verpropiedades <personaje>') end; ownList(src,key) end)
reg('anadiracceso',function(src,a)
    local kind=a[1]; local id=positiveId(a[2]);local key=(kind=='negocio' and 'businesses' or kind=='propiedad' and 'properties' or nil)
    local item=key and id and db[key][tostring(id)];local c=coords(src)
    if not item or not a[3] or not c then return notify(src,'Uso: /anadiracceso negocio|propiedad <id> <nombre>') end
    item.accesses[a[3]]=c; audit(src,'anadiracceso',kind..' '..id..' '..a[3]);save();notify(src,'Acceso '..a[3]..' guardado.')
end)

local function nearestOwnedVehicle(src)
    local ped=GetPlayerPed(src)
    if ped==0 then return nil end
    local c=GetEntityCoords(ped)
    for id,ent in pairs(active) do
        if DoesEntityExist(ent) then
            local d=GetEntityCoords(ent)
            if #(c-d)<12.0 then return id,ent end
        end
    end
    return nil
end
local function spawnVehicle(src,record)
    local c=coords(src)
    if not c then return notify(src,'Solo puedes generar vehiculos dentro del juego.') end
    if active[record.id] and DoesEntityExist(active[record.id]) then return notify(src,'El vehiculo ya esta generado. ID '..record.id) end
    local hash=GetHashKey(record.model)
    local v=CreateVehicle(hash,c.x+3.0,c.y+1.0,c.z,c.heading,true,true)
    if not v or v==0 then return notify(src,'Fallo al crear vehiculo. Verifica modelo y OneSync.') end
    local deadline=GetGameTimer()+8000
    while not DoesEntityExist(v) and GetGameTimer()<deadline do Wait(50) end
    if not DoesEntityExist(v) then return notify(src,'No se pudo sincronizar el vehiculo.') end
    active[record.id]=v
    local net=NetworkGetNetworkIdFromEntity(v)
    record.lastSpawn=c
    if record.mode=='fijo' then save() end
    TriggerClientEvent('osdev:styleVehicle',src,net,record.primary,record.secondary,record.liveryKind,record.liveryIndex,record.plate)
    notify(src,'Vehiculo # '..record.id..' generado. Matricula '..record.plate)
end
reg('crearvehiculo',function(src,a)
    if not coords(src) then return notify(src,'Ejecuta dentro del juego.') end
    local model=a[1] and a[1]:lower(); local primary=tonumber(a[2]);local secondary,mode,owner
    if not model or not model:match('^[%w_]+$') or #model>35 or not primary or primary%1~=0 or primary<0 or primary>159 then return notify(src,'Uso: /crearvehiculo <modelo> <color0-159> [secundario0-159] [temporal|fijo] [personaje]') end
    local i=3;local possible=tonumber(a[i]);if possible then secondary=possible;i=i+1 else secondary=primary end
    if secondary%1~=0 or secondary<0 or secondary>159 then return notify(src,'Color secundario fuera del rango 0-159.') end
    mode=a[i] or 'temporal';if mode~='temporal' and mode~='fijo' then return notify(src,'Modo incorrecto: temporal|fijo.') end
    if a[i+1] then if not person(a[i+1]) then return notify(src,'Personaje no existe.') end;owner=playerKey(a[i+1]) end
    local id=db.counters.vehicle+1;db.counters.vehicle=id
    local record={id=id,model=model,primary=primary,secondary=secondary,mode=mode,owner=owner,plate=('OS%06d'):format(id%1000000),liveryKind=nil,liveryIndex=nil,created=os.time()}
    db.vehicles[tostring(id)]=record
    audit(src,'crearvehiculo',tostring(id));save()
    TriggerClientEvent('osdev:checkModelAndSpawn',src,id,model)
end)
RegisterNetEvent('osdev:spawnChecked',function(id,ok)
    local src=source;if not guard(src) then return end
    id=positiveId(id);local record=id and db.vehicles[tostring(id)]
    if not record then return end
    if not ok then notify(src,'Modelo '..record.model..' no compatible. Vehiculo # '..id..' registrado, sin generar.');return end
    spawnVehicle(src,record)
end)
reg('recuperarvehiculo',function(src,a)
    local id=positiveId(a[1]); local record=id and db.vehicles[tostring(id)]
    if not record then return notify(src,'Uso: /recuperarvehiculo <id>') end
    TriggerClientEvent('osdev:checkModelAndSpawn',src,id,record.model)
end)
reg('borrarvehiculo',function(src,a)
    local id=positiveId(a[1]); local v=id and db.vehicles[tostring(id)]
    if not v or a[2]~='CONFIRMAR' then return notify(src,'Uso: /borrarvehiculo <id> CONFIRMAR') end
    if active[id] and DoesEntityExist(active[id]) then DeleteEntity(active[id]) end
    active[id]=nil;db.vehicles[tostring(id)]=nil;audit(src,'borrarvehiculo',tostring(id));save();notify(src,'Vehiculo # '..id..' eliminado.')
end)
RegisterNetEvent('osdev:changeStyle',function(kind,net,val1,val2)
    local src=source;if not guard(src) then return end
    local veh=NetworkGetEntityFromNetworkId(tonumber(net) or 0)
    local ped=GetPlayerPed(src)
    if veh==0 or ped==0 or #(GetEntityCoords(ped)-GetEntityCoords(veh))>10.0 then return notify(src,'Vehiculo fuera de alcance.') end
    local id,rec
    for i,e in pairs(active) do if e==veh then id=i;rec=db.vehicles[tostring(i)];break end end
    if not rec then return notify(src,'Solo vehiculos creados por os_devtools.') end
    if kind=='color' then
        local x,y=tonumber(val1),tonumber(val2)
        if not x or not y or x%1~=0 or y%1~=0 or x<0 or x>159 or y<0 or y>159 then return notify(src,'Colores invalidos.') end
        rec.primary=x;rec.secondary=y
    elseif kind=='livery' then
        local k,n=tostring(val1),tonumber(val2)
        if (k~='native' and k~='mod') or not n or n%1~=0 or n<0 or n>100 then return notify(src,'Livery invalida.') end
        rec.liveryKind=k;rec.liveryIndex=n
    else return end
    audit(src,'style',id..' '..kind);if rec.mode=='fijo' then save() end
    TriggerClientEvent('osdev:styleVehicle',src,NetworkGetNetworkIdFromEntity(veh),rec.primary,rec.secondary,rec.liveryKind,rec.liveryIndex,rec.plate)
    notify(src,'Aspecto guardado para vehiculo # '..id)
end)
reg('setcolor',function(src,a)
    local p=tonumber(a[1]);local s=tonumber(a[2] or a[1]);
    if not p or not s or p%1~=0 or s%1~=0 or p<0 or p>159 or s<0 or s>159 then return notify(src,'Uso: /setcolor <primario0-159> [secundario0-159]') end
    TriggerClientEvent('osdev:styleFromSeat',src,'color',p,s)
end)
reg('setlivery',function(src,a)
    local n=tonumber(a[1]);local k=a[2] or 'auto'
    if not n or n%1~=0 or n<0 or n>100 or (k~='auto' and k~='native' and k~='mod') then return notify(src,'Uso: /setlivery <indiceDesde0> [auto|native|mod]') end
    TriggerClientEvent('osdev:styleFromSeat',src,'livery',k,n)
end)
reg('listliveries',function(src,a) TriggerClientEvent('osdev:listLiveries',src) end)
reg('coloresvehiculo',function(src,a) notify(src,'Paleta GTA V: indices 0-159. Usa /setcolor <primario> [secundario].') end)

-- Exports para el entorno de pruebas; no son API de produccion.
exports('GetCharacter',function(alias) local p=person(alias); return p end)
exports('GetBusiness',function(id) return db.businesses[tostring(id)] end)
exports('GetProperty',function(id) return db.properties[tostring(id)] end)
exports('GetDevVehicle',function(id) return db.vehicles[tostring(id)] end)
exports('GetBalance',function(alias,account) local p=person(alias);return p and p[account or 'bank'] end)
exports('TryCharge',function(alias,value,account)
    local p,key=person(alias); local n=tonumber(value);account=account or 'bank'
    if not p or (account~='bank' and account~='cash') or not n or n<0 or n%1~=0 then return false,'invalid' end
    if p[account]<n then return false,'insufficient_funds' end
    p[account]=p[account]-n; audit(0,'api_charge',key..' '..n);if not save() then p[account]=p[account]+n;return false,'save_failed' end
    return true,p[account]
end)
AddEventHandler('playerDropped',function() sessions[source]=nil end)
AddEventHandler('onResourceStop',function(name)
    if name~=RESOURCE then return end
    for id,ent in pairs(active) do local r=db.vehicles[tostring(id)];if r and r.mode=='temporal' and DoesEntityExist(ent) then DeleteEntity(ent) end end
end)
print('[os_devtools] listo. RECURSO SOLO DE PRUEBAS. No usar en servidor publico.')
