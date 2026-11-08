local u = OSDevtools.Util
OSDevtools.State = {}
local domain = OSDevtools.State

function domain.account(value)
    if type(value)~='string' then return false end
    local kind,identifier=value:match('^([%w]+):(.+)$')
    if kind=='license' or kind=='license2' then return #identifier==40 and identifier:match('^[a-f0-9]+$')~=nil end
    return kind=='fivem' and #identifier<=20 and identifier:match('^[1-9]%d*$')~=nil
end
function domain.alias(value)
    return u.text(value, 40) and #value >= 3 and value:match('^[%w_%-]+$') ~= nil
end
function domain.id(value)
    return type(value) == 'string' and value:match('^oschar_%d%d%d%d%d%d%d%d%d%d$') ~= nil and tonumber(value:sub(8)) > 0
end
function domain.position(value, dated)
    if not u.object(value, { x=true,y=true,z=true,h=true,bucket=true,at=true,reason=true,time=true }) then return false end
    for _, axis in ipairs({'x','y','z'}) do if not u.finite(value[axis]) or math.abs(value[axis]) > 20000 then return false end end
    if math.abs(value.x) + math.abs(value.y) + math.abs(value.z) < 0.01 then return false end
    if value.z < -200 or value.z > 3000 or not u.finite(value.h) or value.h < 0 or value.h > 360
        or not u.integer(value.bucket, 0, 2147483647) then return false end
    return (value.time==nil or u.integer(value.time,0,253402300799))
        and (not dated or (u.integer(value.at,0,253402300799) and u.text(value.reason,32)))
end
function domain.number(value) return tonumber(('%.12g'):format(value)) end
-- Tipos admitidos por CREATE_VEHICLE_SERVER_SETTER (campo type de vehicles.meta).
domain.vehicleTypes={automobile=true,bike=true,boat=true,heli=true,plane=true,submarine=true,trailer=true}
-- Apariencia del ped: modelo, 12 componentes, accesorios y, en modelos freemode, cabeza.
-- Solo admite enteros/decimales acotados; no se interpreta ningun texto del cliente.
local function unit(value,minimum) return u.finite(value) and value>=(minimum or 0) and value<=1 end
local function head(value)
    if not u.object(value,{blend=true,features=true,overlays=true,hair=true,eyes=true}) then return false end
    local b=value.blend
    if b~=nil then
        if not u.object(b,{sf=true,ss=true,st=true,kf=true,ks=true,kt=true,sm=true,km=true,tm=true}) then return false end
        for _,key in ipairs({'sf','ss','st','kf','ks','kt'}) do if not u.integer(b[key],0,255) then return false end end
        if not unit(b.sm) or not unit(b.km) or not unit(b.tm) then return false end
    end
    if not u.array(value.features,20) or #value.features~=20 then return false end
    for _,feature in ipairs(value.features) do if not unit(feature,-1) then return false end end
    if not u.array(value.overlays,13) or #value.overlays~=13 then return false end
    for _,o in ipairs(value.overlays) do
        if not u.object(o,{v=true,o=true,ct=true,c=true,c2=true}) or not u.integer(o.v,0,255) or not unit(o.o)
            or not u.integer(o.ct,0,2) or not u.integer(o.c,0,63) or not u.integer(o.c2,0,63) then return false end
    end
    return u.object(value.hair,{c=true,h=true}) and u.integer(value.hair.c,0,63) and u.integer(value.hair.h,0,63)
        and u.integer(value.eyes,0,31)
end
function domain.appearance(value)
    if not u.object(value,{model=true,components=true,props=true,head=true})
        or not u.integer(value.model,-2147483648,4294967295) or value.model==0 then return false end
    if not u.array(value.components,12) or #value.components~=12 then return false end
    for _,c in ipairs(value.components) do
        if not u.object(c,{d=true,t=true,p=true}) or not u.integer(c.d,0,4095) or not u.integer(c.t,0,255) or not u.integer(c.p,0,3) then return false end
    end
    if not u.array(value.props,8) then return false end
    local seen={}
    for _,p in ipairs(value.props) do
        if not u.object(p,{i=true,d=true,t=true}) or not u.integer(p.i,0,12) or seen[p.i]
            or not u.integer(p.d,-1,4095) or not u.integer(p.t,-1,255) then return false end
        seen[p.i]=true
    end
    return value.head==nil or head(value.head)
end
-- Copia normalizada: los decimales se fijan con la misma precision que las posiciones.
function domain.normalizeAppearance(value)
    if not domain.appearance(value) then return nil end
    local copy=u.copy(value)
    if copy.head then
        local b=copy.head.blend
        if b then for _,key in ipairs({'sm','km','tm'}) do b[key]=domain.number(b[key]) end end
        for index,feature in ipairs(copy.head.features) do copy.head.features[index]=domain.number(feature) end
        for _,o in ipairs(copy.head.overlays) do o.o=domain.number(o.o) end
    end
    return copy
end
function domain.normalizePosition(value,reason)
    if not u.object(value) then return nil end
    local point={x=value.x,y=value.y,z=value.z,h=value.h,bucket=value.bucket,
        at=value.at or value.time or 0,time=value.time,reason=value.reason or reason or 'legacy'}
    if not domain.position(point,true) then return nil end
    for _,axis in ipairs({'x','y','z','h'}) do point[axis]=domain.number(point[axis]) end
    return point
end
local function base(data)
    if not u.object(data) or (data.version ~= 1 and data.version ~= 2)
        or not u.integer(data.nextVehicle,1,2147483647) or not u.integer(data.nextBusiness,1,2147483647)
        or not u.object(data.characters) or not u.object(data.bindings) or not u.object(data.vehicles)
        or not u.object(data.businesses) or not u.object(data.properties) or not u.array(data.audit,300) then return nil,'Estructura de datos incompatible.' end
    local count = 0
    for alias, c in pairs(data.characters) do
        count = count + 1
        if count > 1000 or not domain.alias(alias) or not u.object(c)
            or not u.integer(c.cash,0,2147483647) or not u.integer(c.bank,0,2147483647)
            or not u.text(c.job,40) or not u.text(c.rank,40) or type(c.duty) ~= 'boolean' then return nil,'Personaje invalido.' end
    end
    for account, alias in pairs(data.bindings) do
        if not domain.account(account) or type(alias) ~= 'string' or not data.characters[alias] then return nil,'Vinculo de cuenta invalido.' end
    end
    for _, category in ipairs({'vehicles','businesses','properties'}) do
        local highest = 0
        for id, record in pairs(data[category]) do
            local number = tonumber(id)
            if not u.integer(number,1,2147483646) or tostring(number) ~= id or not u.object(record) or record.id ~= number
                or (record.owner ~= nil and (type(record.owner) ~= 'string' or not data.characters[record.owner])) then return nil,'ID o titularidad de bien invalido.' end
            highest = math.max(highest,number)
            if record.position and not domain.position(record.position,false) then return nil,'Posicion de bien invalida.' end
            if category == 'vehicles' then
                if not u.text(record.model,50) or not u.integer(record.primary,0,159) or not u.integer(record.secondary,0,159)
                    or type(record.fixed) ~= 'boolean' or not u.text(record.plate,16)
                    or (record.livery ~= nil and not u.integer(record.livery,0,255))
                    or (record.vtype ~= nil and not domain.vehicleTypes[record.vtype]) then return nil,'Vehiculo invalido.' end
            elseif category == 'properties' then
                -- Sintaxis actual: solo numero y precio. Tipo/nombre de propiedades antiguas se conservan.
                if not u.integer(record.price,0,2147483647) or (record.type ~= nil and not u.text(record.type,40))
                    or (record.name ~= nil and not u.text(record.name,40)) then return nil,'Propiedad invalida.' end
            elseif not u.text(record.type,40) or not u.text(record.name,40) or not u.integer(record.price,0,2147483647) then return nil,'Bien invalido.' end
        end
        if category == 'vehicles' and data.nextVehicle <= highest then return nil,'Contador de vehiculos obsoleto.' end
        if category == 'businesses' and data.nextBusiness <= highest then return nil,'Contador de negocios obsoleto.' end
    end
    for _, entry in ipairs(data.audit) do
        if not u.object(entry) or not u.integer(entry.time,0,253402300799) or not u.text(entry.actor,80) or not u.text(entry.operation,256) then return nil,'Auditoria invalida.' end
    end
    return true
end
function domain.snapshot(data)
    local ok, err = base(data)
    if not ok then return nil, err end
    if data.version ~= 2 or not u.integer(data.revision,0,9007199254740000) or not u.integer(data.nextCharacter,1,2147483647) then return nil,'Version de identidad incompatible.' end
    local ids, aliases = {}, {}
    local count = 0
    for alias,c in pairs(data.characters) do
        count=count+1
        if not domain.id(c.id) or ids[c.id] or aliases[alias:lower()]
            or tonumber(c.id:sub(8)) >= data.nextCharacter
            or (c.account ~= nil and not domain.account(c.account)) then return nil,'Identidad de personaje invalida o duplicada.' end
        ids[c.id],aliases[alias:lower()]=true,true
        for _,field in ipairs({'lastPosition','lastValidPosition','lastLogoutPosition','lastDeathPosition','spawn','customSpawn'}) do
            if c[field] and not domain.position(c[field],true) then return nil,'Posicion de personaje invalida.' end
        end
        if c.life ~= nil and c.life ~= 'alive' and c.life ~= 'dead' then return nil,'Estado vital invalido.' end
        if c.appearance ~= nil and not domain.appearance(c.appearance) then return nil,'Apariencia de personaje invalida.' end
        if type(c.spawnOverridePending)~='nil' and type(c.spawnOverridePending)~='boolean' then return nil,'Indicador de spawn invalido.' end
        if not u.integer(c.nextDeath,1,2147483647) or not u.array(c.deaths,OSDevtools.CoreConfig.MaxDeaths) then return nil,'Historial de muertes invalido.' end
        local previous=0
        for _,event in ipairs(c.deaths or {}) do
            if not u.object(event,{id=true,characterId=true,position=true,cause=true}) or not u.integer(event.id,previous+1,c.nextDeath-1)
                or event.characterId ~= c.id or not domain.position(event.position,true) or event.cause ~= 'unknown' then return nil,'Evento de muerte invalido.' end
            previous=event.id
        end
    end
    if data.nextCharacter < count+1 then return nil,'Contador de personajes inconsistente.' end
    if data.settings ~= nil then
        if not u.object(data.settings,{npcPolice=true,ambientNpcs=true}) then return nil,'Ajustes del mundo invalidos.' end
        for _,value in pairs(data.settings) do if type(value) ~= 'boolean' then return nil,'Ajustes del mundo invalidos.' end end
    end
    for account,alias in pairs(data.bindings) do if data.characters[alias].account ~= account then return nil,'Personaje activo de otra cuenta.' end end
    return true
end
function domain.successor(before,after)
    if after.revision ~= before.revision+1 or after.nextCharacter < before.nextCharacter
        or after.nextVehicle < before.nextVehicle or after.nextBusiness < before.nextBusiness then return nil,'Revision o contador no consecutivo.' end
    for alias,c in pairs(before.characters) do
        if not after.characters[alias] or after.characters[alias].id ~= c.id then return nil,'No se puede borrar o renumerar un personaje.' end
    end
    for _,category in ipairs({'vehicles','businesses','properties'}) do
        for id,record in pairs(before[category]) do if not after[category][id] or after[category][id].id~=record.id then return nil,'No se pueden borrar o renumerar bienes.' end end
    end
    return true
end
function domain.migrate(raw)
    local ok,err=base(raw); if not ok then return nil,err end
    if raw.version == 2 then
        local valid,reason=domain.snapshot(raw);return valid and u.copy(raw) or nil,reason
    end
    local data=u.copy(raw);data.version=2;data.revision=0;data.nextCharacter=1
    local aliases={};for alias in pairs(data.characters) do aliases[#aliases+1]=alias end;table.sort(aliases)
    for _,alias in ipairs(aliases) do
        local c=data.characters[alias]
        if c.id~=nil then return nil,'ID de personaje heredado no reconocido; requiere migracion explicita.' end
        if c.deaths~=nil or c.nextDeath~=nil then return nil,'Historial heredado no reconocido; no se sobrescribe.' end
        c.id=('oschar_%010d'):format(data.nextCharacter);data.nextCharacter=data.nextCharacter+1
        c.life=c.life or 'alive';c.deaths={};c.nextDeath=1
        for _,field in ipairs({'lastPosition','lastLogoutPosition','lastDeathPosition','spawn','customSpawn'}) do
            if c[field] then
                local point=domain.normalizePosition(c[field],field=='lastDeathPosition' and 'legacy_death' or 'legacy')
                if not point then return nil,'Posicion heredada invalida; no se elimina ni sobrescribe.' end
                c[field]=point
            end
        end
        if c.lastPosition then c.lastValidPosition=u.copy(c.lastPosition) end
        if c.lastDeathPosition then
            c.deaths[1]={id=1,characterId=c.id,position=u.copy(c.lastDeathPosition),cause='unknown'};c.nextDeath=2
        end
        for account,binding in pairs(data.bindings) do
            if binding==alias then
                if c.account and c.account~=account then return nil,'Personaje heredado vinculado a varias cuentas; revision manual requerida.' end
                c.account=account
            end
        end
    end
    for _,category in ipairs({'vehicles','businesses','properties'}) do
        for _,record in pairs(data[category]) do if record.position then
            for _,axis in ipairs({'x','y','z','h'}) do record.position[axis]=domain.number(record.position[axis]) end
        end end
    end
    local valid,reason=domain.snapshot(data);return valid and data or nil,reason
end
function domain.resolve(data,value,connection)
    if type(value)~='string' then return nil,'Destinatario requerido.' end
    if value:match('^%d+$') then
        local id=tonumber(value)
        if not u.integer(id,1,2147483647) then return nil,'ID de conexion invalido.' end
        local alias,err=connection(id)
        if not alias then return nil,err or 'Jugador desconectado o sin personaje activo.' end
        return alias
    end
    if value:sub(1,5)=='char:' then
        for alias,c in pairs(data.characters) do if c.id==value:sub(6) then return alias end end
        return nil,'ID persistente de personaje inexistente.'
    end
    local alias=value:sub(1,6)=='alias:' and value:sub(7) or value
    if domain.alias(alias) and data.characters[alias] then return alias end
    return nil,'Alias de personaje inexistente.'
end
