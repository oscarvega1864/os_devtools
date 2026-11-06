local RESOURCE = GetCurrentResourceName()
local FILE = 'data.json'
local state = { version=1, nextVehicle=1, nextBusiness=1, characters={}, bindings={}, vehicles={}, businesses={}, properties={}, audit={} }
local sessions = {}  -- vehicle entity netId by record number; transient
local requestNonce = 0
local pending = {}
local lastHudRequest = {}
local function pushHud(src)
  if src == 0 or not GetPlayerName(src) then return end
  local key
  for _,identifier in ipairs(GetPlayerIdentifiers(src)) do
    if identifier:sub(1,8)=='license:' then key=identifier;break end
  end
  local alias=key and state.bindings[key] or nil
  local c=alias and state.characters[alias] or nil
  TriggerClientEvent('osdev:hudData',src,{
    playerId=src,
    cash=c and c.cash or nil,
    character=alias,
  })
end
local function pushAllHud()
  for _,id in ipairs(GetPlayers()) do pushHud(tonumber(id)) end
end
RegisterNetEvent('osdev:requestHud',function()
  local src=source
  if src<=0 then return end
  local now=GetGameTimer()
  if lastHudRequest[src] and now-lastHudRequest[src]<1500 then return end
  lastHudRequest[src]=now
  pushHud(src)
end)
AddEventHandler('playerDropped',function() lastHudRequest[source]=nil end)


local function out(src, msg)
  if src == 0 then print('[os_devtools] '..msg)
  else TriggerClientEvent('osdev:msg',src,msg) end
end
local function integer(x)
  local n=tonumber(x)
  if not n or n ~= math.floor(n) or n < 0 or n > 2147483647 then return nil end
  return n
end
local function positive(x)
  local n=integer(x)
  return n and n>0 and n or nil
end
local function money(x)
  if type(x)~='string' then return nil end
  return integer(x:gsub('%$$',''))
end
local function admin(src)
  return src==0 or IsPlayerAceAllowed(src,'osdev.admin')
end
local function keyFor(src)
  for _,id in ipairs(GetPlayerIdentifiers(src)) do
    if id:sub(1,8)=='license:' then return id end
  end
  return nil
end
local function validAlias(s)
  return type(s)=='string' and #s>=3 and #s<=40 and s:match('^[%w_%-]+$') ~= nil
end
local function clone(t)
  return json.decode(json.encode(t))
end
local function store(candidate)
  local serial=json.encode(candidate)
  if not serial or not SaveResourceFile(RESOURCE,FILE,serial,#serial) then return false end
  state=candidate
  pushAllHud()
  return true
end
local function action(src,label,fn)
  local candidate=clone(state)
  local ok, err=fn(candidate)
  if not ok then out(src,err or 'Operacion denegada.'); return false end
  candidate.audit[#candidate.audit+1]={time=os.time(),actor=src==0 and 'console' or (keyFor(src) or tostring(src)),operation=label}
  if #candidate.audit>300 then table.remove(candidate.audit,1) end
  if not store(candidate) then out(src,'ERROR: No se pudo guardar. No se ha aplicado el cambio.'); return false end
  return true
end
local function characterFor(src)
  local key=keyFor(src)
  return key and state.bindings[key] or nil
end
local function resolve(s)
  if not s then return nil end
  local id=integer(s)
  if id and id>0 and GetPlayerName(id) then return characterFor(id) end
  return validAlias(s) and state.characters[s] and s or nil
end
local function ownerLabel(alias) return alias or 'sin propietario' end
local function getCoords(src)
  if src==0 then return nil end
  local ped=GetPlayerPed(src)
  if not ped or ped==0 then return nil end
  local c=GetEntityCoords(ped)
  if not c then return nil end
  return {x=c.x,y=c.y,z=c.z,h=GetEntityHeading(ped),bucket=GetPlayerRoutingBucket(src)}
end
local function needAdmin(src)
  if admin(src) then return true end
  out(src,'Sin permisos ACE osdev.admin.'); return false
end
local function exists(src)
  local alias=characterFor(src)
  if not alias or not state.characters[alias] then out(src,'No tienes personaje activo. Admin: /setpj <idJugador> <alias>'); return nil end
  return alias
end
local function showCharacter(src,alias)
  local c=state.characters[alias]
  if not c then return end
  out(src, ('Personaje %s | Dinero en mano: $%d | Banco: $%d | Job: %s (%s) | Servicio: %s'):format(alias,c.cash or 0,c.bank or 0,c.job or 'ninguno',c.rank or '-',c.duty and 'SI' or 'NO'))
end

RegisterCommand('setpj',function(src,args)
  if not needAdmin(src) then return end
  local target=integer(args[1]); local alias=args[2]
  if not target or not GetPlayerName(target) or not validAlias(alias) then return out(src,'Uso: /setpj <idJugadorConectado> <alias>') end
  local key=keyFor(target)
  if not key then return out(src,'Jugador sin identificador license; no se modifica nada.') end
  if action(src,'setpj '..alias,function(d)
    if not d.characters[alias] then d.characters[alias]={cash=0,bank=0,job='unemployed',rank='-',duty=false} end
    d.bindings[key]=alias
    return true
  end) then out(src,'Personaje '..alias..' vinculado al jugador '..target) end
end,false)
RegisterCommand('setuser',function(src,args)
  if not needAdmin(src) then return end
  out(src,'/setuser reservado. Usa /setpj <idJugador> <alias>; los permisos administrativos se gestionan por ACE.')
end,false)
RegisterCommand('dinero',function(src)
  if src==0 then return out(src,'Entra en juego para consultar tu saldo.') end
  local alias=exists(src); if alias then showCharacter(src,alias) end
end,false)
RegisterCommand('misbienes',function(src)
  local alias=exists(src); if not alias then return end
  showCharacter(src,alias)
  for _,category in ipairs({{'Vehiculos',state.vehicles},{'Negocios',state.businesses},{'Propiedades',state.properties}}) do
    local found={}
    for id,v in pairs(category[2]) do
      if v.owner==alias then found[#found+1] = ('#%s %s%s'):format(id,v.name or v.model or v.type or '',v.fixed==false and ' (temporal)' or '') end
    end
    table.sort(found)
    out(src,category[1]..': '..(#found>0 and table.concat(found,', ') or 'ninguno'))
  end
end,false)
RegisterCommand('mispropiedades',function(src)
  if src~=0 then
    local alias=exists(src); if not alias then return end
    TriggerClientEvent('osdev:own',src,state.vehicles,state.businesses,state.properties,alias,state.characters[alias])
  end
end,false)
RegisterCommand('verpropiedades',function(src,args)
  if not needAdmin(src) then return end
  local alias=resolve(args[1]); if not alias then return out(src,'Uso: /verpropiedades <idJugador|alias>') end
  showCharacter(src,alias)
  for _,cat in ipairs({{'Vehiculos',state.vehicles},{'Negocios',state.businesses},{'Propiedades',state.properties}}) do
    local results={}
    for id,v in pairs(cat[2]) do if v.owner==alias then results[#results+1]=id..':'..(v.name or v.model or v.type or '?') end end
    out(src,cat[1]..': '..(#results>0 and table.concat(results,', ') or 'ninguno'))
  end
end,false)

RegisterCommand('setmoney',function(src,args)
  if not needAdmin(src) then return end
  local who=resolve(args[1]); local amount=money(args[2]); local account=args[3] or 'cash'
  if not who or amount==nil or (account~='cash' and account~='bank') then return out(src,'Uso: /setmoney <idJugador|alias> <cantidad> [cash|bank]') end
  if action(src,'setmoney',function(d) d.characters[who][account]=amount; return true end) then out(src,'Saldo '..account..' de '..who..': $'..amount) end
end,false)
RegisterCommand('givemoney',function(src,args)
  if not needAdmin(src) then return end
  local who=resolve(args[1]); local amount=positive(args[2]); local account=args[3] or 'cash'
  if not who or not amount or (account~='cash' and account~='bank') then return out(src,'Uso: /givemoney <idJugador|alias> <cantidad> [cash|bank]') end
  if action(src,'givemoney',function(d)
    if d.characters[who][account]+amount>2147483647 then return false,'Saldo fuera de rango.' end
    d.characters[who][account]=d.characters[who][account]+amount;return true
  end) then out(src,'Añadidos $'..amount..' a '..who) end
end,false)
RegisterCommand('removemoney',function(src,args)
  if not needAdmin(src) then return end
  local who=resolve(args[1]); local amount=positive(args[2]); local account=args[3] or 'cash'
  if not who or not amount or (account~='cash' and account~='bank') then return out(src,'Uso: /removemoney <idJugador|alias> <cantidad> [cash|bank]') end
  if action(src,'removemoney',function(d)
    if d.characters[who][account]<amount then return false,'Fondos insuficientes.' end
    d.characters[who][account]=d.characters[who][account]-amount;return true
  end) then out(src,'Retirados $'..amount..' a '..who) end
end,false)
-- Transferencias de efectivo entre personajes. No depende del job ni de ACE.
-- El destino puede ser un jugador conectado (server ID) o un alias registrado,
-- incluso si ese personaje esta desconectado. Los pagos a uno mismo se rechazan.
RegisterCommand('pagar',function(src,args)
  if src==0 then return out(src,'/pagar debe ejecutarse dentro del juego.') end
  local from=exists(src); if not from then return end
  local target=args[1]
  local amount=positive(args[2])
  if not target or not amount then
    return out(src,'Uso: /pagar <idJugador|personaje> <cantidad>. Ejemplo: /pagar 2 100')
  end
  local id=positive(target)
  local to
  if id then
    if not GetPlayerName(id) then
      return out(src,('El jugador con ID %d no esta conectado. Usa un alias de personaje registrado para pagarle desconectado.'):format(id))
    end
    to=characterFor(id)
    if not to or not state.characters[to] then
      return out(src,('El jugador ID %d todavia no tiene personaje. Un admin debe ejecutar /setpj %d <alias>.'):format(id,id))
    end
  else
    if not validAlias(target) or not state.characters[target] then
      return out(src,'No existe el personaje '..tostring(target)..'. Registralo antes con /setpj <idJugador> <alias>.')
    end
    to=target
  end
  if from==to then return out(src,'No puedes pagarte a ti mismo. Para pruebas usa /setmoney o /givemoney.') end
  if action(src,('pagar %s -> %s $%d'):format(from,to,amount),function(d)
    local sender=d.characters[from]
    local receiver=d.characters[to]
    if not sender or not receiver then return false,'Uno de los personajes ya no existe.' end
    if (sender.cash or 0)<amount then return false,('Dinero en mano insuficiente: tienes $%d y quieres pagar $%d.'):format(sender.cash or 0,amount) end
    if (receiver.cash or 0)+amount>2147483647 then return false,'Saldo del destinatario fuera de rango.' end
    sender.cash=sender.cash-amount
    receiver.cash=(receiver.cash or 0)+amount
    return true
  end) then
    out(src,('Pago completado: has enviado $%d a %s.'):format(amount,to))
    for _,playerId in ipairs(GetPlayers()) do
      local n=tonumber(playerId)
      if n~=src and characterFor(n)==to then
        out(n,('Has recibido $%d en efectivo de %s.'):format(amount,from))
      end
    end
  end
end,false)

RegisterCommand('oscomandos',function(src)
  local lines={
    'PERSONAJE: /dinero, /misbienes, /mispropiedades, /hud, /pagar <id|alias> <cantidad>, /ceder <id|alias> (en tu coche)',
    'ADMIN: /setpj, /setuser, /setjob, /setduty, /setmoney, /givemoney, /removemoney, /verpropiedades',
    'ACTIVOS: /crearpropiedad, /crearnegocio, /crearvehiculo, /setpropiedad, /setnegocio, /setvehiculo',
    'VEHICULOS: /recuperarvehiculo, /setcolor, /setlivery, /listliveries, /listvehiculos, /infovehiculo',
    'CONSULTA: /listnegocios, /infonegocio, /listpropiedades, /infopropiedad'
  }
  for _,line in ipairs(lines) do out(src,line) end
end,false)

RegisterCommand('setjob',function(src,args)
  if not needAdmin(src) then return end
  local who=resolve(args[1]);local job=args[2];local rank=args[3] or 'empleado'
  if not who or not validAlias(job) or not validAlias(rank) then return out(src,'Uso: /setjob <idJugador|alias> <job> <rango>') end
  if action(src,'setjob',function(d) local c=d.characters[who];c.job=job;c.rank=rank;c.duty=false;return true end) then out(src,'Job actualizado: '..who..' -> '..job..'/'..rank) end
end,false)
RegisterCommand('setduty',function(src,args)
  if not needAdmin(src) then return end
  local who=resolve(args[1]); local val=args[2]
  if not who or (val~='on' and val~='off') then return out(src,'Uso: /setduty <idJugador|alias> on|off') end
  if action(src,'setduty',function(d) d.characters[who].duty=(val=='on');return true end) then out(src,'Duty de '..who..': '..val) end
end,false)

local function createAsset(kind,src,args)
  if not needAdmin(src) then return end
  local pos=getCoords(src);if not pos then return out(src,'Debes ejecutar este comando dentro del juego.') end
  local id,typ,name,price,owner
  if kind=='properties' then
    id=positive(args[1]);typ=args[2];name=args[3];price=money(args[4]);owner=nil
    if not id or not validAlias(typ) or not validAlias(name) or price==nil then return out(src,'Uso: /crearpropiedad <id> <tipo> <nombre> <precio>') end
  else
    typ=args[1];name=args[2];owner=resolve(args[3]);price=money(args[4])
    if not validAlias(typ) or not validAlias(name) or not owner or price==nil then return out(src,'Uso: /crearnegocio <tipo> <nombre> <propietario> <precio>') end
  end
  if action(src,'create '..kind,function(d)
    if kind=='businesses' then id=d.nextBusiness;d.nextBusiness=id+1 end
    if d[kind][tostring(id)] then return false,'ERROR: El ID '..id..' ya existe.' end
    d[kind][tostring(id)]={id=id,type=typ,name=name,owner=owner,price=price,position=pos}
    return true
  end) then out(src,('Creado %s #%d %s en tus coordenadas.'):format(kind,id,name)) end
end
RegisterCommand('crearpropiedad',function(src,args) createAsset('properties',src,args) end,false)
RegisterCommand('crearnegocio',function(src,args) createAsset('businesses',src,args) end,false)
local function assign(kind,src,args)
  if not needAdmin(src) then return end
  local id=positive(args[1]); local who=resolve(args[2])
  if not id or not who then return out(src,'Uso: /set'..(kind=='vehicles' and 'vehiculo' or kind=='businesses' and 'negocio' or 'propiedad')..' <id> <idJugador|alias>') end
  if action(src,'assign '..kind,function(d)
    local obj=d[kind][tostring(id)];if not obj then return false,'No existe ese ID en esta categoria.' end
    obj.owner=who;return true
  end) then out(src,'Asignado '..kind..' #'..id..' a '..who) end
end
RegisterCommand('setpropiedad',function(src,args) assign('properties',src,args) end,false)
RegisterCommand('setnegocio',function(src,args) assign('businesses',src,args) end,false)
RegisterCommand('setvehiculo',function(src,args) assign('vehicles',src,args) end,false)
local function listCategory(category,src,args)
  if not needAdmin(src) then return end
  local id=positive(args[1]);local d=state[category]
  if id then
    local obj=d[tostring(id)]
    return out(src,obj and json.encode(obj) or 'ID inexistente.')
  end
  local ids={};for k in pairs(d) do ids[#ids+1]=tonumber(k) end; table.sort(ids)
  if #ids==0 then return out(src,'No hay registros.') end
  for _,k in ipairs(ids) do
    local obj=d[tostring(k)];out(src,('#%d %s | %s'):format(k,obj.name or obj.model or obj.type or '?',ownerLabel(obj.owner)))
  end
end
for command,cat in pairs({listvehiculos='vehicles',listnegocios='businesses',listpropiedades='properties',infovehiculo='vehicles',infonegocio='businesses',infopropiedad='properties'}) do
  RegisterCommand(command,function(src,args) listCategory(cat,src,command:sub(1,4)=='info' and args or {}) end,false)
end

RegisterCommand('crearvehiculo',function(src,args)
  if not needAdmin(src) then return end
  local model=args[1]
  local primary=integer(args[2]);local secondary=integer(args[3])
  if not model or not model:match('^[%w_]+$') or #model>50 or primary==nil or primary>159 then
    return out(src,'Uso: /crearvehiculo <modelo> <colorPrimario0-159> [colorSecundario0-159] [temporal|fijo] [personaje]')
  end
  local ix=3
  if secondary and secondary<=159 then ix=4 else secondary=primary end
  local mode=args[ix] or 'temporal';local who=args[ix+1] and resolve(args[ix+1]) or nil
  if (mode~='temporal' and mode~='fijo') or (args[ix+1] and not who) then return out(src,'Modo temporal|fijo y personaje valido (si se proporciona).') end
  local pos=getCoords(src);if not pos then return out(src,'Ejecuta desde el juego.') end
  local id=state.nextVehicle
  local plate=('OS%06d'):format(id)
  if not action(src,'create vehicle',function(d)
    local newId=d.nextVehicle
    d.nextVehicle=newId+1
    id=newId
    plate=('OS%06d'):format(id)
    d.vehicles[tostring(id)]={id=id,model=model,primary=primary,secondary=secondary,fixed=(mode=='fijo'),owner=who,plate=plate,position=pos,livery=nil,liveryType=nil}
    return true
  end) then return end
  requestNonce=requestNonce+1
  local nonce=tostring(requestNonce)..':'..tostring(os.time())
  pending[nonce]={id=id,source=src,expires=GetGameTimer()+15000}
  TriggerClientEvent('osdev:spawnVehicle',src,{nonce=nonce,id=id,model=model,primary=primary,secondary=secondary,plate=plate,position=pos})
  out(src,('Vehiculo #%d registrado (%s). Generando...'):format(id,mode))
end,false)
RegisterNetEvent('osdev:spawned',function(nonce,netId,err)
  local src=source
  local p=pending[nonce]
  if not p or p.source~=src then return end
  pending[nonce]=nil
  local id=p.id
  local v=state.vehicles[tostring(id)]
  if not v then return end
  local entity=netId and NetworkGetEntityFromNetworkId(netId) or 0
  if entity and entity~=0 and DoesEntityExist(entity) then
    sessions[id]=netId
    out(src,'Vehiculo #'..id..' creado. Matricula '..v.plate)
  else
    out(src,'No se pudo generar el vehiculo ('..tostring(err or 'sin entidad de red')..'). Registro conservado para reintentar con /recuperarvehiculo '..id)
  end
end)
RegisterCommand('recuperarvehiculo',function(src,args)
  if not needAdmin(src) then return end
  local id=positive(args[1]);local v=id and state.vehicles[tostring(id)]
  if not v then return out(src,'Uso: /recuperarvehiculo <idExistente>') end
  local net=sessions[id];local ent=net and NetworkGetEntityFromNetworkId(net) or 0
  if ent~=0 and DoesEntityExist(ent) then return out(src,'Ya hay una entidad activa para el vehiculo #'..id) end
  requestNonce=requestNonce+1
  local nonce=tostring(requestNonce)..':'..tostring(os.time())
  pending[nonce]={id=id,source=src,expires=GetGameTimer()+15000}
  TriggerClientEvent('osdev:spawnVehicle',src,{nonce=nonce,id=id,model=v.model,primary=v.primary,secondary=v.secondary,plate=v.plate,position=getCoords(src) or v.position,livery=v.livery,liveryType=v.liveryType})
end,false)
RegisterNetEvent('osdev:vehicleAppearance',function(plate,primary,secondary,livery,liveryType)
  local src=source
  if not admin(src) then return end
  local veh=GetVehiclePedIsIn(GetPlayerPed(src),false)
  if veh==0 or not DoesEntityExist(veh) or GetVehicleNumberPlateText(veh):gsub('%s+$','')~=plate then return end
  local found
  for id,v in pairs(state.vehicles) do if v.plate==plate then found=id;break end end
  if not found then return out(src,'Vehiculo no registrado: cambios no persistidos.') end
  if primary~=nil and (not integer(primary) or primary>159 or not integer(secondary) or secondary>159) then return end
  if livery~=nil and (not integer(livery) or livery>255 or (liveryType~='native' and liveryType~='mod48')) then return end
  if action(src,'vehicle appearance',function(d)
    local v=d.vehicles[found]
    if primary~=nil then v.primary=primary;v.secondary=secondary end
    if livery~=nil then v.livery=livery;v.liveryType=liveryType end
    return true
  end) then out(src,'Aspecto guardado para vehiculo #'..found) end
end)

RegisterNetEvent('osdev:cederVehicle',function(target,plate)
  local src=source
  local from=exists(src);if not from then return end
  local to=resolve(target)
  if not to or from==to then return out(src,'Destino invalido. Uso: /ceder <idJugador|alias>') end
  local veh=GetVehiclePedIsIn(GetPlayerPed(src),false)
  if veh==0 or not DoesEntityExist(veh) or GetVehicleNumberPlateText(veh):gsub('%s+$','')~=plate then return out(src,'Debes estar dentro del vehiculo indicado.') end
  local found
  for id,v in pairs(state.vehicles) do if v.plate==plate then found=id;break end end
  if not found then return out(src,'Este vehiculo no esta registrado en os_devtools.') end
  if state.vehicles[found].owner~=from then return out(src,'No eres el propietario de este vehiculo.') end
  if action(src,'ceder vehicle',function(d) d.vehicles[found].owner=to;return true end) then
    out(src,'Vehiculo #'..found..' cedido a '..to)
    for _,id in ipairs(GetPlayers()) do if characterFor(tonumber(id))==to then out(tonumber(id),'Has recibido el vehiculo #'..found) end end
  end
end)
for command,event in pairs({setcolor='osdev:doSetColor',setlivery='osdev:doSetLivery',listliveries='osdev:doListLiveries'}) do
  RegisterCommand(command,function(src,args)
    if not needAdmin(src) then return end
    if src==0 then return out(src,'Comando disponible solo dentro del juego.') end
    TriggerClientEvent(event,src,args)
  end,false)
end
RegisterCommand('ceder',function(src,args)
  if src==0 then return end
  if not exists(src) then return end
  if not resolve(args[1]) then return out(src,'Uso: /ceder <idJugador|alias>, estando en el vehiculo propio.') end
  TriggerClientEvent('osdev:requestCeder',src,args[1])
end,false)
AddEventHandler('onResourceStop',function(name)
  if name~=RESOURCE then return end
  for id,v in pairs(state.vehicles) do
    if not v.fixed then
      local net=sessions[tonumber(id)];local ent=net and NetworkGetEntityFromNetworkId(net) or 0
      if ent~=0 and DoesEntityExist(ent) then DeleteEntity(ent) end
    end
  end
end)
CreateThread(function()
  local raw=LoadResourceFile(RESOURCE,FILE)
  if raw and #raw>0 then
    local ok,decoded=pcall(json.decode,raw)
    if ok and type(decoded)=='table' and decoded.version==1 and type(decoded.characters)=='table' and type(decoded.vehicles)=='table' then
      state=decoded
      state.audit=state.audit or {};state.properties=state.properties or {};state.businesses=state.businesses or {};state.bindings=state.bindings or {}
    else print('[os_devtools] ERROR archivo data.json invalido: no se reemplaza.');return end
  else
    if not store(state) then print('[os_devtools] ERROR no se pudo crear data.json') end
  end
  -- Vehicles temporales are session-only, but avoid deletion of records until a successful save.
  local candidate=clone(state)
  for k,v in pairs(candidate.vehicles) do if not v.fixed then candidate.vehicles[k]=nil end end
  if not store(candidate) then print('[os_devtools] ERROR no se pudo limpiar temporales') end
  print('[os_devtools] Listo (USO EXCLUSIVO DEV).')
  pushAllHud()
end)
exports('GetBalance',function(alias,account)
  local c=state.characters[alias]
  if not c or (account~='cash' and account~='bank') then return nil end
  return c[account]
end)
exports('GetAsset',function(category,id)
  local d=state[category]
  return d and clone(d[tostring(id)]) or nil
end)
