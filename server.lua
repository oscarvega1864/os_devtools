local RESOURCE = GetCurrentResourceName()
-- Los comandos de este archivo se guardan tambien por nombre para que el panel de os_admin los
-- ejecute con la misma validacion y recoja sus respuestas (ver runCommand).
local nativeRegisterCommand=RegisterCommand
local commandHandlers={}
local function RegisterCommand(name,handler,restricted)
  commandHandlers[name]=handler
  return nativeRegisterCommand(name,handler,restricted)
end
local capture=nil -- {src, lines}: respuestas recogidas para el panel en vez de enviarlas
local core
local state={characters={},bindings={},vehicles={},businesses={},properties={},audit={}}
local ready=false
local vehicles       -- OSDevtools.Vehicles: entidades creadas por el servidor (ver server/vehicles.lua)
local missingTypes={} -- vehiculos fijos antiguos sin tipo: se completan al entrar un administrador
local lastHudRequest = {}
local function pushHud(src)
  if src == 0 or not GetPlayerName(src) then return end
  local alias=core and core.lookup(src)
  local c=alias and state.characters[alias]
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
  if lastHudRequest[src] and now>=lastHudRequest[src] and now-lastHudRequest[src]<1500 then return end
  lastHudRequest[src]=now
  pushHud(src)
end)
AddEventHandler('playerDropped',function() lastHudRequest[source]=nil end)


-- Mensaje corto: notificacion (os_notify) o chat. Tipo: info | success | warning | error;
-- sin tipo, una linea de uso se marca como aviso.
local function out(src, msg, kind)
  if capture and capture.src==src then capture.lines[#capture.lines+1]={msg,kind or (msg:find('^Uso') and 'warning') or 'info'};return end
  if src == 0 then return print('[os_devtools] '..msg) end
  TriggerClientEvent('osdev:msg',src,msg,kind or (msg:find('^Uso') and 'warning') or 'info')
end
-- Listados y consultas largas: siempre al chat, donde se pueden leer y desplazar.
local function list(src, msg)
  if capture and capture.src==src then capture.lines[#capture.lines+1]={msg,'list'};return end
  if src == 0 then return print('[os_devtools] '..msg) end
  TriggerClientEvent('osdev:list',src,msg)
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
local function admin(src,permission)
  return OSDevtools.AuthHub.can(src,permission or 'osdev.admin')
end
local function validAlias(s)
  return type(s)=='string' and #s>=3 and #s<=40 and s:match('^[%w_%-]+$') ~= nil
end
local function clone(t) return OSDevtools.Util.copy(t) end
local function action(src,label,fn)
  local ok,err=core.change(src,label,fn)
  if not ok then out(src,err or 'Operacion no confirmada.','error') end
  return ok
end
local function characterFor(src) return core and core.ensure(src) end
local function resolve(value) return core.resolve(value) end
local function ownerLabel(alias)
  local character=alias and state.characters[alias]
  return character and (alias..' ['..character.id..']') or 'sin propietario'
end
local function getCoords(src) return core and core.position(src) end
-- Punto a 4 m delante de una posicion (vector frontal de GTA: -sin(h), cos(h)).
local function ahead(pos,distance)
  local r=math.rad(pos.h or 0);local d=distance or 4
  return {x=OSDevtools.State.number(pos.x-math.sin(r)*d),y=OSDevtools.State.number(pos.y+math.cos(r)*d),z=pos.z,h=pos.h,bucket=pos.bucket}
end
-- Etiqueta visible de un bien. Las propiedades nuevas no tienen nombre: "Propiedad #200".
local function assetLabel(category,id,record)
  if category=='properties' then return 'Propiedad #'..id..(record.name and (' ('..record.name..')') or '') end
  if category=='businesses' then
    local kind=OSDevtools.BusinessTypes[record.type]
    return record.name..' ['..(kind and kind.label or record.type)..']'
  end
  return record.model or record.name or record.type or '?'
end
local function needAdmin(src,permission)
  permission=permission or 'osdev.admin'
  if not ready then out(src,'Registro no disponible; revisar almacenamiento.','error');return false end
  if admin(src,permission) then return true end
  OSDevtools.AuthDenied(src,permission)
  out(src,'Sin autorizacion efectiva '..permission..'. Consulta /ospermisos.','error');return false
end
local function exists(src)
  local alias=characterFor(src)
  if not alias or not state.characters[alias] then out(src,'No se pudo resolver tu identidad. Comprueba tu license y la persistencia del recurso.','error'); return nil end
  return alias
end
local function showCharacter(src,alias)
  local c=state.characters[alias]
  if not c then return end
  list(src, ('Personaje %s | Dinero en mano: $%d | Banco: $%d | Job: %s (%s) | Servicio: %s'):format(alias,c.cash or 0,c.bank or 0,c.job or 'ninguno',c.rank or '-',c.duty and 'SI' or 'NO'))
end

-- /setpj eliminado: identidad automatica por license y migracion conservadora.
RegisterCommand('setuser',function(src)
  if not needAdmin(src) then return end
  out(src,'Identidad automatica activa. /setpj fue retirado; no se cambian los propietarios existentes.')
end,false)
RegisterCommand('dinero',function(src)
  if src==0 then return out(src,'Entra en juego para consultar tu saldo.') end
  local alias=exists(src); if alias then showCharacter(src,alias) end
end,false)
RegisterCommand('misbienes',function(src)
  local alias=exists(src); if not alias then return end
  showCharacter(src,alias)
  for _,category in ipairs({{'Vehiculos','vehicles'},{'Negocios','businesses'},{'Propiedades','properties'}}) do
    local found={}
    for id,v in pairs(state[category[2]]) do
      if v.owner==alias then found[#found+1] = ('#%s %s%s'):format(id,assetLabel(category[2],id,v),v.fixed==false and ' (temporal)' or '') end
    end
    table.sort(found)
    list(src,category[1]..': '..(#found>0 and table.concat(found,', ') or 'ninguno'))
  end
end,false)
RegisterCommand('mispropiedades',function(src)
  if src~=0 then
    local alias=exists(src); if not alias then return end
    local own={vehicles={},businesses={},properties={}}
    for category,records in pairs(own) do
      for id,record in pairs(state[category]) do if record.owner==alias then records[id]=clone(record) end end
    end
    local c=state.characters[alias]
    TriggerClientEvent('osdev:own',src,own.vehicles,own.businesses,own.properties,alias,{cash=c.cash,bank=c.bank,job=c.job,rank=c.rank,duty=c.duty})
  end
end,false)
RegisterCommand('verpropiedades',function(src,args)
  if not needAdmin(src,'osdev.inspect') then return end
  local alias=resolve(args[1]); if not alias then return out(src,'Uso: /verpropiedades <idJugador|alias>') end
  showCharacter(src,alias)
  for _,cat in ipairs({{'Vehiculos','vehicles'},{'Negocios','businesses'},{'Propiedades','properties'}}) do
    local results={}
    for id,v in pairs(state[cat[2]]) do if v.owner==alias then results[#results+1]=id..':'..assetLabel(cat[2],id,v) end end
    list(src,cat[1]..': '..(#results>0 and table.concat(results,', ') or 'ninguno'))
  end
end,false)

RegisterCommand('setmoney',function(src,args)
  if not needAdmin(src,'osdev.economy') then return end
  local who=resolve(args[1]); local amount=money(args[2]); local account=args[3] or 'cash'
  if not who or amount==nil or (account~='cash' and account~='bank') then return out(src,'Uso: /setmoney <idJugador|alias> <cantidad> [cash|bank]') end
  if action(src,'setmoney '..who..' '..account..' '..amount,function(d) d.characters[who][account]=amount; return true end) then out(src,'Saldo '..account..' de '..who..': $'..amount,'success') end
end,false)
RegisterCommand('givemoney',function(src,args)
  if not needAdmin(src,'osdev.economy') then return end
  local who=resolve(args[1]); local amount=positive(args[2]); local account=args[3] or 'cash'
  if not who or not amount or (account~='cash' and account~='bank') then return out(src,'Uso: /givemoney <idJugador|alias> <cantidad> [cash|bank]') end
  if action(src,'givemoney '..who..' '..account..' '..amount,function(d)
    if d.characters[who][account]+amount>2147483647 then return false,'Saldo fuera de rango.' end
    d.characters[who][account]=d.characters[who][account]+amount;return true
  end) then out(src,'Añadidos $'..amount..' a '..who,'success') end
end,false)
RegisterCommand('removemoney',function(src,args)
  if not needAdmin(src,'osdev.economy') then return end
  local who=resolve(args[1]); local amount=positive(args[2]); local account=args[3] or 'cash'
  if not who or not amount or (account~='cash' and account~='bank') then return out(src,'Uso: /removemoney <idJugador|alias> <cantidad> [cash|bank]') end
  if action(src,'removemoney '..who..' '..account..' '..amount,function(d)
    if d.characters[who][account]<amount then return false,'Fondos insuficientes.' end
    d.characters[who][account]=d.characters[who][account]-amount;return true
  end) then out(src,'Retirados $'..amount..' a '..who,'success') end
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
  local to,resolveError=core.resolve(target)
  if not to then return out(src,resolveError or 'Destinatario no disponible. Usa idJugador, alias:ALIAS o char:ID.','error') end
  if from==to then return out(src,'No puedes pagarte a ti mismo. Para pruebas usa /setmoney o /givemoney.','error') end
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
    out(src,('Pago completado: has enviado $%d a %s.'):format(amount,to),'success')
    for _,playerId in ipairs(GetPlayers()) do
      local n=tonumber(playerId)
      if n~=src and characterFor(n)==to then
        out(n,('Has recibido $%d en efectivo de %s.'):format(amount,from),'success')
      end
    end
  end
end,false)

RegisterCommand('ospermisos',function(src)
  if src==0 then return out(src,'Consola autorizada. Sincronizacion: osautorizar <id> <perfil> <minutos> CONFIRMAR. Jugador: /ospermisos.') end
  if not OSDevtools.AuthDiagnosticAllowed(src) then return end
  local principal=OSDevtools.AuthIdentity.resolve(src)
  local tx=OSDevtools.AuthHub.status(src)
  local ace=IsPlayerAceAllowed(src,'osdev.admin');local general=IsPlayerAceAllowed(src,'command')
  list(src,('Sesion %d | identidad %s | ACE osdev.admin=%s | ACE general command=%s'):format(src,OSDevtools.AuthIdentity.mask(principal),tostring(ace==true or ace==1),tostring(general==true or general==1)))
  list(src,('txAdmin compatible=%s | autenticado=%s | perfil temporal=%s | almacenamiento=%s | personaje=%s'):format(tostring(tx.txCompatible),tostring(tx.authenticated),tx.profile or 'ninguno',tostring(ready),tostring(characterFor(src) or 'no disponible')))
  local scopes={}
  for _,scope in ipairs({'osdev.admin','osdev.economy','osdev.jobs','osdev.assets','osdev.inspect','osdev.identity','ossecurity.admin','osinventory.admin'}) do
    local allowed,provider=OSDevtools.AuthHub.can(src,scope)
    scopes[#scopes+1]=scope..'='..tostring(allowed)..' ('..provider..')'
  end
  list(src,table.concat(scopes,' | '))
end,false)
RegisterCommand('oscomandos',function(src)
  local lines={
    'PERSONAJE: /dinero, /misbienes, /mispropiedades, /hud, /pagar <id|alias> <cantidad>, /ceder <id|alias> (en tu coche)',
    'ADMIN: /setuser, /setjob, /setduty, /setmoney, /givemoney, /removemoney, /verpropiedades; /ospermisos',
    'ACTIVOS: /crearpropiedad <numero> <precio>, /crearnegocio <tipo> <nombre> <precio>, /crearvehiculo, /setpropiedad, /setnegocio, /setvehiculo',
    'VEHICULOS: /recuperarvehiculo, /setcolor, /setlivery, /listliveries, /listvehiculos, /infovehiculo',
    'CONSULTA: /listnegocios, /infonegocio, /listpropiedades, /infopropiedad'
  }
  for _,line in ipairs(lines) do list(src,line) end
  list(src,'PERSONAJES: /personaje [alias|char:id]; ADMIN: /crearpersonaje, /seleccionarpersonaje, /vincularpersonaje. /setpj retirado.')
  list(src,'POSICION: /guardarpos, /ultimaubicacion; ADMIN: /setspawn <destinatario>, /tpusuario <id>.')
  list(src,'APARIENCIA: se guarda sola al cambiar; /guardarropa la guarda al momento.')
  list(src,'MUNDO: /policianpc [on|off] y /npcs [on|off] (admin) activan o desactivan policia NPC y peatones/trafico.')
end,false)

RegisterCommand('setjob',function(src,args)
  if not needAdmin(src,'osdev.jobs') then return end
  local who=resolve(args[1]);local job=args[2];local rank=args[3] or 'empleado'
  if not who or not validAlias(job) or not validAlias(rank) then return out(src,'Uso: /setjob <idJugador|alias> <job> <rango>') end
  if action(src,'setjob',function(d) local c=d.characters[who];c.job=job;c.rank=rank;c.duty=false;return true end) then out(src,'Job actualizado: '..who..' -> '..job..'/'..rank,'success') end
end,false)
RegisterCommand('setduty',function(src,args)
  if not needAdmin(src,'osdev.jobs') then return end
  local who=resolve(args[1]); local val=args[2]
  if not who or (val~='on' and val~='off') then return out(src,'Uso: /setduty <idJugador|alias> on|off') end
  if action(src,'setduty',function(d) d.characters[who].duty=(val=='on');return true end) then out(src,'Duty de '..who..': '..val,'success') end
end,false)

-- Nombre de negocio: varias palabras, 3-40 bytes, sin codigos de formato de GTA (~) ni etiquetas.
local function businessName(args)
  local name=table.concat(args,' ',2,#args-1):gsub('^%s+',''):gsub('%s+$','')
  if #name<3 or #name>40 or name:find('[%c~<>\\]') then return nil end
  return name
end
-- Blips: se envian a cada jugador solo cuando cambian los negocios visibles.
local blipSignature=nil
local function businessBlips()
  local list={}
  for id,b in pairs(state.businesses) do
    if b.position and OSDevtools.BusinessTypes[b.type] then
      list[#list+1]={id=tonumber(id),type=b.type,name=b.name,x=b.position.x,y=b.position.y,z=b.position.z}
    end
  end
  table.sort(list,function(a,b) return a.id<b.id end)
  return list
end
-- Propiedades: "numero: propietario" si tiene titular, "numero: $precio" si esta a la venta.
local function thousands(value) return tostring(math.floor(value)):reverse():gsub('(%d%d%d)','%1.'):reverse():gsub('^%.','') end
local function propertyBlips()
  local list={}
  for id,p in pairs(state.properties) do
    if p.position and tonumber(id) then
      local owned=p.owner~=nil and state.characters[p.owner]~=nil
      list[#list+1]={id=tonumber(id),type=owned and 'owned' or 'sale',
        name=('%d: %s'):format(tonumber(id),owned and p.owner or ('$'..thousands(p.price or 0))),
        x=p.position.x,y=p.position.y,z=p.position.z}
    end
  end
  table.sort(list,function(a,b) return a.id<b.id end)
  return list
end
local function signatureOf(...)
  local parts={}
  for _,list in ipairs({...}) do
    for _,b in ipairs(list) do parts[#parts+1]=table.concat({b.id,b.type,b.name,b.x,b.y,b.z},'|') end
    parts[#parts+1]='#'
  end
  return table.concat(parts,';')
end
local function pushBlips(target)
  local list,properties=businessBlips(),propertyBlips()
  if target then return TriggerClientEvent('osdev:businessBlips',target,list,properties) end
  local signature=signatureOf(list,properties)
  if signature==blipSignature then return end
  blipSignature=signature
  for _,id in ipairs(GetPlayers()) do TriggerClientEvent('osdev:businessBlips',tonumber(id),list,properties) end
end
local lastBlipRequest={}
RegisterNetEvent('osdev:requestBusinessBlips',function()
  local src=source
  if src<=0 or not ready then return end
  local now=GetGameTimer()
  if lastBlipRequest[src] and now>=lastBlipRequest[src] and now-lastBlipRequest[src]<5000 then return end
  lastBlipRequest[src]=now
  pushBlips(src)
end)
AddEventHandler('playerDropped',function() lastBlipRequest[source]=nil end)

-- Ajustes del mundo persistentes (policia NPC, peatones y trafico), aplicados por cada cliente.
local WORLD_DEFAULTS={npcPolice='NpcPoliceDefault',ambientNpcs='AmbientNpcsDefault'}
local function worldSetting(key)
  local value=state.settings and state.settings[key]
  if value==nil then return OSDevtools.CoreConfig[WORLD_DEFAULTS[key]]~=false end
  return value
end
local function npcPolice() return worldSetting('npcPolice') end
local function pushWorld(target)
  local settings={npcPolice=worldSetting('npcPolice'),ambientNpcs=worldSetting('ambientNpcs')}
  if target then return TriggerClientEvent('osdev:worldSettings',target,settings) end
  for _,id in ipairs(GetPlayers()) do TriggerClientEvent('osdev:worldSettings',tonumber(id),settings) end
end
local lastWorldRequest={}
RegisterNetEvent('osdev:requestWorldSettings',function()
  local src=source
  if src<=0 or not ready then return end
  local now=GetGameTimer()
  if lastWorldRequest[src] and now>=lastWorldRequest[src] and now-lastWorldRequest[src]<5000 then return end
  lastWorldRequest[src]=now
  pushWorld(src)
end)
AddEventHandler('playerDropped',function() lastWorldRequest[source]=nil end)
RegisterCommand('policianpc',function(src,args)
  local mode=args[1] and args[1]:lower()
  if not mode then return out(src,'Policia NPC: '..(npcPolice() and 'ACTIVADA (GTA normal)' or 'DESACTIVADA (sin estrellas ni persecuciones)')..'. Uso: /policianpc on|off') end
  if not needAdmin(src,'osdev.admin') then return end
  if mode~='on' and mode~='off' then return out(src,'Uso: /policianpc on|off') end
  local enabled=mode=='on'
  if action(src,'npc police '..mode,function(d) d.settings=d.settings or {};d.settings.npcPolice=enabled;return true end) then
    pushWorld()
    out(src,enabled and 'Policia NPC ACTIVADA: estrellas y persecuciones normales de GTA.' or 'Policia NPC DESACTIVADA: sin estrellas, persecuciones ni envios policiales.')
  end
end,false)
RegisterCommand('npcs',function(src,args)
  local mode=args[1] and args[1]:lower()
  if not mode then return out(src,'Peatones y trafico: '..(worldSetting('ambientNpcs') and 'ACTIVADOS (GTA normal)' or 'DESACTIVADOS (ciudad vacia)')..'. Uso: /npcs on|off') end
  if not needAdmin(src,'osdev.admin') then return end
  if mode~='on' and mode~='off' then return out(src,'Uso: /npcs on|off') end
  local enabled=mode=='on'
  if action(src,'ambient npcs '..mode,function(d) d.settings=d.settings or {};d.settings.ambientNpcs=enabled;return true end) then
    pushWorld()
    out(src,enabled and 'Peatones y trafico ACTIVADOS: poblacion normal de GTA.' or 'Peatones y trafico DESACTIVADOS: no aparecen nuevos; los actuales desaparecen al alejarte.')
  end
end,false)

-- /crearpropiedad <numero> <precio>: ID elegido por el administrador, sin nombre, tipo ni titular.
RegisterCommand('crearpropiedad',function(src,args)
  if not needAdmin(src,'osdev.assets') then return end
  local id=positive(args[1]);local price=money(args[2])
  if #args~=2 or not id or id>2147483646 or price==nil then return out(src,'Uso: /crearpropiedad <numero> <precio>. Ejemplo: /crearpropiedad 200 50000') end
  if state.properties[tostring(id)] then return out(src,'La propiedad ID '..id..' ya existe.','error') end
  local pos=getCoords(src);if not pos then return out(src,'Debes ejecutar este comando dentro del juego, en un bucket permitido.') end
  if action(src,'create property '..id,function(d)
    if d.properties[tostring(id)] then return false,'La propiedad ID '..id..' ya existe.' end
    d.properties[tostring(id)]={id=id,price=price,position=pos}
    return true
  end) then out(src,('Propiedad #%d creada en tus coordenadas por $%d. Sin propietario: /setpropiedad %d <destinatario>.'):format(id,price,id),'success') end
end,false)
-- /crearnegocio <tipo> <nombre> <precio>: ID automatico, sin titular, blip segun la categoria.
RegisterCommand('crearnegocio',function(src,args)
  if not needAdmin(src,'osdev.assets') then return end
  local types={};for key in pairs(OSDevtools.BusinessTypes) do types[#types+1]=key end;table.sort(types)
  local usage='Uso: /crearnegocio <tipo> <nombre> <precio>. Tipos: '..table.concat(types,', ')..'. Ejemplo: /crearnegocio ltd LTD_Mirror 30000'
  local kind=args[1] and args[1]:lower();local price=#args>=3 and money(args[#args]) or nil;local name=#args>=3 and businessName(args) or nil
  if not kind or not OSDevtools.BusinessTypes[kind] or price==nil or not name then return out(src,usage) end
  local pos=getCoords(src);if not pos then return out(src,'Debes ejecutar este comando dentro del juego, en un bucket permitido.') end
  local id
  if action(src,'create business '..kind,function(d)
    id=d.nextBusiness;d.nextBusiness=id+1
    if d.businesses[tostring(id)] then return false,'ERROR: El ID '..id..' ya existe.' end
    d.businesses[tostring(id)]={id=id,type=kind,name=name,price=price,position=pos}
    return true
  end) then out(src,('Negocio #%d "%s" (%s) creado en tus coordenadas por $%d. Sin propietario: /setnegocio %d <destinatario>.'):format(id,name,OSDevtools.BusinessTypes[kind].label,price,id),'success') end
end,false)
local function assign(kind,src,args)
  if not needAdmin(src,'osdev.assets') then return end
  local id=positive(args[1]); local who=resolve(args[2])
  if not id or not who then return out(src,'Uso: /set'..(kind=='vehicles' and 'vehiculo' or kind=='businesses' and 'negocio' or 'propiedad')..' <id> <idJugador|alias>') end
  if action(src,'assign '..kind,function(d)
    local obj=d[kind][tostring(id)];if not obj then return false,'No existe ese ID en esta categoria.' end
    obj.owner=who;return true
  end) then out(src,'Asignado '..kind..' #'..id..' a '..ownerLabel(who),'success') end
end
RegisterCommand('setpropiedad',function(src,args) assign('properties',src,args) end,false)
RegisterCommand('setnegocio',function(src,args) assign('businesses',src,args) end,false)
RegisterCommand('setvehiculo',function(src,args) assign('vehicles',src,args) end,false)
local function listCategory(category,src,args)
  if not needAdmin(src,'osdev.inspect') then return end
  local id=positive(args[1]);local d=state[category]
  if id then
    local obj=d[tostring(id)]
    return list(src,obj and json.encode(obj) or 'ID inexistente.')
  end
  local ids={};for k in pairs(d) do ids[#ids+1]=tonumber(k) end; table.sort(ids)
  if #ids==0 then return list(src,'No hay registros.') end
  for _,k in ipairs(ids) do
    local obj=d[tostring(k)];list(src,('#%d %s | %s'):format(k,assetLabel(category,k,obj),ownerLabel(obj.owner)))
  end
end
for command,cat in pairs({listvehiculos='vehicles',listnegocios='businesses',listpropiedades='properties',infovehiculo='vehicles',infonegocio='businesses',infopropiedad='properties'}) do
  RegisterCommand(command,function(src,args) listCategory(cat,src,command:sub(1,4)=='info' and args or {}) end,false)
end

RegisterCommand('crearvehiculo',function(src,args)
  if not needAdmin(src,'osdev.assets') then return end
  local model=args[1]
  local primary=integer(args[2]);local secondary=integer(args[3])
  if not model or not model:match('^[%w_]+$') or #model>50 or primary==nil or primary>159 then
    return out(src,'Uso: /crearvehiculo <modelo> <colorPrimario0-159> [colorSecundario0-159] [temporal|fijo] [personaje]')
  end
  local ix=3
  if secondary and secondary<=159 then ix=4 else secondary=primary end
  local mode=args[ix] or 'temporal';local who=args[ix+1] and resolve(args[ix+1]) or nil
  if (mode~='temporal' and mode~='fijo') or (args[ix+1] and not who) then return out(src,'Modo temporal|fijo y personaje valido (si se proporciona).') end
  local pos=getCoords(src);if not pos then return out(src,'Ejecuta desde el juego, en un bucket permitido.') end
  if not vehicles.onesync() then return out(src,'OneSync desactivado: el servidor no puede crear vehiculos.') end
  local point=ahead(pos)
  vehicles.inspect(src,{model},function(types)
    local vtype=types and types[model]
    if not vtype then return out(src,'Modelo de vehiculo invalido o no disponible en tu cliente: '..model..'. No se registra nada.','error') end
    local id,plate
    if not action(src,'create vehicle',function(d)
      id=d.nextVehicle;d.nextVehicle=id+1;plate=('OS%06d'):format(id)
      d.vehicles[tostring(id)]={id=id,model=model,primary=primary,secondary=secondary,fixed=(mode=='fijo'),owner=who,plate=plate,position=point,vtype=vtype}
      return true
    end) then return end
    local entity,err=vehicles.spawn(id,state.vehicles[tostring(id)],point)
    if entity then out(src,('Vehiculo #%d (%s, %s) creado delante de ti. Matricula %s.'):format(id,model,mode,plate),'success')
    else out(src,('Vehiculo #%d registrado, pero %s Reintenta con /recuperarvehiculo %d.'):format(id,err,id),'error') end
  end)
end,false)
-- Completa el tipo de modelo de vehiculos registrados preguntando a un administrador conectado.
local function completeTypes(src,ids,done)
  local models,seen={},{}
  for _,id in ipairs(ids) do
    local record=state.vehicles[tostring(id)]
    if record and not seen[record.model] then seen[record.model]=true;models[#models+1]=record.model end
  end
  if #models==0 then return done(false) end
  vehicles.inspect(src,models,function(types)
    if not types then return done(false) end
    local updates={}
    for _,id in ipairs(ids) do
      local record=state.vehicles[tostring(id)];local kind=record and types[record.model]
      if kind and record.vtype~=kind then updates[tostring(id)]=kind end
    end
    if not next(updates) then return done(false) end
    local ok=core.change(src,'vehicle types',function(d)
      for key,kind in pairs(updates) do if d.vehicles[key] then d.vehicles[key].vtype=kind end end
      return true
    end)
    done(ok)
  end)
end
RegisterNetEvent('osdev:vehicleModelTypes',function(nonce,result) vehicles.inspected(source,nonce,result) end)
-- Al entrar un administrador se completan los tipos pendientes y se restauran esos vehiculos.
RegisterNetEvent('osdev:vehiclesReady',function()
  local src=source
  if src<=0 or not ready or #missingTypes==0 or not admin(src,'osdev.assets') then return end
  local ids=missingTypes;missingTypes={}
  completeTypes(src,ids,function()
    local created,missing=vehicles.restore()
    for _,id in ipairs(missing) do missingTypes[#missingTypes+1]=id end
    print(('[os_devtools] Vehiculos fijos restaurados tras completar tipos: %d. Pendientes: %d.'):format(created,#missingTypes))
  end)
end)
RegisterCommand('recuperarvehiculo',function(src,args)
  if not needAdmin(src,'osdev.assets') then return end
  local id=positive(args[1]);local v=id and state.vehicles[tostring(id)]
  if not v then return out(src,'Uso: /recuperarvehiculo <idExistente>') end
  if vehicles.find(id,v) then return out(src,'El vehiculo #'..id..' ya existe en el mundo; no se duplica.','warning') end
  local pos=getCoords(src);if not pos then return out(src,'Ejecuta desde el juego, en un bucket permitido.') end
  local function here()
    local record=state.vehicles[tostring(id)];local point=ahead(pos)
    local entity,err=vehicles.spawn(id,record,point)
    if not entity then return out(src,err,'error') end
    if record.fixed then core.change(src,'vehicle recovered '..id,function(d) d.vehicles[tostring(id)].position=point;return true end) end
    out(src,'Vehiculo #'..id..' recuperado delante de ti.','success')
  end
  if v.vtype then return here() end
  completeTypes(src,{id},function(ok)
    if ok or state.vehicles[tostring(id)].vtype then here() else out(src,'No se pudo determinar el tipo del modelo '..v.model..'.','error') end
  end)
end,false)
RegisterNetEvent('osdev:vehicleAppearance',function(plate,primary,secondary,livery,liveryType)
  local src=source
  if not needAdmin(src,'osdev.assets') then return end
  local veh=GetVehiclePedIsIn(GetPlayerPed(src),false)
  if veh==0 or not DoesEntityExist(veh) or GetPedInVehicleSeat(veh,-1)~=GetPlayerPed(src) or GetVehicleNumberPlateText(veh):gsub('%s+$','')~=plate then return end
  local found
  for id,v in pairs(state.vehicles) do if v.plate==plate then found=id;break end end
  if not found then return out(src,'Este vehiculo no lo gestiona os_devtools (p. ej. creado con vMenu): color/livery no guardados. Usa /crearvehiculo para uno persistente.','warning') end
  if primary~=nil and (not integer(primary) or primary>159 or not integer(secondary) or secondary>159) then return end
  if livery~=nil and (not integer(livery) or livery>255 or (liveryType~='native' and liveryType~='mod48')) then return end
  if action(src,'vehicle appearance',function(d)
    local v=d.vehicles[found]
    if primary~=nil then v.primary=primary;v.secondary=secondary end
    if livery~=nil then v.livery=livery;v.liveryType=liveryType end
    return true
  end) then
    vehicles.refreshLook(tonumber(found),state.vehicles[found])
    out(src,'Aspecto guardado para vehiculo #'..found,'success')
  end
end)

RegisterNetEvent('osdev:cederVehicle',function(target,plate)
  local src=source
  local from=exists(src);if not from then return end
  local to=resolve(target)
  if not to or from==to then return out(src,'Destino invalido. Uso: /ceder <idJugador|alias>') end
  local veh=GetVehiclePedIsIn(GetPlayerPed(src),false)
  if veh==0 or not DoesEntityExist(veh) or GetPedInVehicleSeat(veh,-1)~=GetPlayerPed(src) or GetVehicleNumberPlateText(veh):gsub('%s+$','')~=plate then return out(src,'Debes conducir el vehiculo indicado.') end
  local found
  for id,v in pairs(state.vehicles) do if v.plate==plate then found=id;break end end
  if not found then return out(src,'Este vehiculo no esta registrado en os_devtools.','error') end
  if state.vehicles[found].owner~=from then return out(src,'No eres el propietario de este vehiculo.','error') end
  if action(src,'ceder vehicle',function(d) d.vehicles[found].owner=to;return true end) then
    out(src,'Vehiculo #'..found..' cedido a '..to,'success')
    for _,id in ipairs(GetPlayers()) do if characterFor(tonumber(id))==to then out(tonumber(id),'Has recibido el vehiculo #'..found,'success') end end
  end
end)
for command,event in pairs({setcolor='osdev:doSetColor',setlivery='osdev:doSetLivery',listliveries='osdev:doListLiveries'}) do
  RegisterCommand(command,function(src,args)
    if not needAdmin(src,'osdev.assets') then return end
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
  if name~=RESOURCE or not vehicles then return end
  if ready then vehicles.savePositions('resource_stop') end
  vehicles.stop()
end)
AddEventHandler('txAdmin:events:serverShuttingDown',function() if ready and vehicles then vehicles.savePositions('server_shutdown') end end)
CreateThread(function()
  while true do
    Wait(30000)
    if ready and vehicles then vehicles.savePositions('periodic') end
  end
end)
local storage,storageError=OSDevtools.openStorage(RESOURCE)
core=OSDevtools.Core.new({
  storage=storage,now=os.time,clock=GetGameTimer,connected=function(src) return GetPlayerName(src)~=nil end,
  identifiers=GetPlayerIdentifiers,
  world=function(src)
    local ped=GetPlayerPed(src)
    if not ped or ped==0 or not DoesEntityExist(ped) then return nil,nil end
    local point=GetEntityCoords(ped)
    if not point then return nil,nil end
    return {x=point.x,y=point.y,z=point.z,h=GetEntityHeading(ped),bucket=GetPlayerRoutingBucket(src)},GetEntityHealth(ped)
  end,
  schedule=SetTimeout,
  publish=function(snapshot,status) state=snapshot;ready=status;pushAllHud();if ready then pushBlips() end end,
  changed=function(src,dto)
    TriggerEvent('osdev:characterChanged',src,dto)
    if GetPlayerName(src) then TriggerClientEvent('osdev:characterChanged',src,dto) end
  end,
  spawn=function(src,context)
    SetPlayerRoutingBucket(src,context.position.bucket)
    TriggerClientEvent('osdev:spawnCharacter',src,context)
  end,
  spawnAccepted=function(src,token) TriggerClientEvent('osdev:spawnAccepted',src,token) end,
  -- Marca de sesion en el state bag del jugador: sobrevive a un reinicio de os_devtools, asi
  -- quien ya esta jugando no vuelve a ver el selector de entrada.
  markSpawned=function(src) local ok,p=pcall(Player,src);if ok and p and p.state then p.state:set('osdevSpawned',true,true) end end,
  wasSpawned=function(src) local ok,p=pcall(Player,src);return ok and p and p.state and p.state.osdevSpawned==true or false end
})
OSDevtools.Runtime=core
vehicles=OSDevtools.Vehicles.new({state=function() return state end,change=core.change,now=GetGameTimer})
OSDevtools.VehicleRuntime=vehicles
local loaded,loadError=core.start()
if not loaded then print('[os_devtools] Registro bloqueado: '..tostring(storageError or loadError)) end
OSDevtools.bindCore({core=core,reply=out,list=list,guard=needAdmin})
-- Panel y consola de os_admin (opcional). runCommand ejecuta un comando existente de este recurso
-- y devuelve sus respuestas; las asincronas (p. ej. crear vehiculo) llegan despues como aviso normal.
local function runCommand(src,name,args)
  local handler=commandHandlers[name]
  if not handler then return {ok=false,message='Comando no disponible: '..name} end
  local previous=capture;capture={src=src,lines={}}
  local ok,err=pcall(handler,src,args)
  local lines=capture.lines;capture=previous
  if not ok then print('[os_devtools] Fallo en '..name..' desde el panel: '..tostring(err));return {ok=false,message='El comando fallo; revisar la consola.'} end
  local failed,texts=false,{}
  for _,line in ipairs(lines) do texts[#texts+1]=line[1];if line[2]=='error' or line[2]=='warning' then failed=true end end
  if #texts==0 then return {ok=true,message='Solicitud enviada; el resultado llegara como aviso.'} end
  if #texts==1 then return {ok=not failed,message=texts[1]} end
  local rows={};for index=2,#texts do rows[#rows+1]={texts[index]} end
  return {ok=not failed,message=texts[1],columns={'Detalle'},rows=rows}
end
local adminOptions={core=core,run=runCommand,can=function(src,permission) return ready and (src==0 or admin(src,permission)) end}
OSDevtools.AdminRuntime=adminOptions
OSDevtools.AdminSections.publish(adminOptions)
AddEventHandler('os_admin:ready',function() OSDevtools.AdminSections.publish(adminOptions) end)
if loaded then
  for _,id in ipairs(GetPlayers()) do local alias,err=core.ensure(tonumber(id));if not alias then out(tonumber(id),err) end end
  print('[os_devtools] 0.1.3 listo. Datos conservados; /setpj permanece retirado.')
  if vehicles.onesync() then
    local created,missing=vehicles.restore()
    missingTypes=missing
    print(('[os_devtools] Vehiculos fijos restaurados: %d. Sin tipo conocido (se completan al entrar un administrador): %d.'):format(created,#missing))
  else print('[os_devtools] OneSync desactivado: los vehiculos fijos no se restauran.') end
end
exports('GetBalance',function(alias,account)
  local c=state.characters[alias]
  if not ready or not c or (account~='cash' and account~='bank') then return nil end
  return c[account]
end)
-- Lista de propiedades o negocios (copias), p. ej. para que os_security cierre sus puertas con llave.
exports('ListAssets',function(category)
  if not ready or not ({businesses=true,properties=true})[category] then return nil end
  local result={}
  for _,asset in pairs(state[category] or {}) do result[#result+1]=clone(asset) end
  table.sort(result,function(a,b) return a.id<b.id end)
  return result
end)
exports('GetAsset',function(category,id)
  if not ready or not ({vehicles=true,businesses=true,properties=true})[category] then return nil end
  local d=state[category]
  return d and clone(d[tostring(id)]) or nil
end)
