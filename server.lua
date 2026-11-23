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
    bank=c and c.bank or nil, -- lo usa el adaptador os_devtools de o-link (Oxide HUD)
    character=alias,
    characterId=c and c.id or nil, -- mismo identificador que usa o-link en el servidor
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
-- Matricula aleatoria al estilo de EE. UU. (San Andreas / California): 1 cifra, 3 letras y 3 cifras (p. ej. 8KDR472),
-- sin I, O ni Q para no confundirlas con numeros. Nunca repite una existente.
local PLATE_LETTERS='ABCDEFGHJKLMNPRSTUVWXYZ'
local function randomPlate(d)
  local used={}
  for _,v in pairs(d.vehicles) do if v.plate then used[v.plate]=true end end
  local function letters() local t='';for _=1,3 do local i=math.random(1,#PLATE_LETTERS);t=t..PLATE_LETTERS:sub(i,i) end;return t end
  for _=1,200 do
    local plate=('%d%s%03d'):format(math.random(1,9),letters(),math.random(0,999))
    if not used[plate] then return plate end
  end
  return ('%d%s%03d'):format(math.random(1,9),letters(),math.random(0,999))
end
local function needAdmin(src,permission)
  permission=permission or 'osdev.admin'
  if not ready then out(src,'Registro no disponible; revisar almacenamiento.','error');return false end
  if admin(src,permission) then return true end
  OSDevtools.AuthDenied(src,permission)
  out(src,'Sin autorizacion efectiva '..permission..'. Consulta /ospermisos.','error');return false
end
-- Subpermiso de bienes segun la categoria (las facciones son negocios de tipo faccion).
local function assetPerm(category,id)
  if category=='properties' then return 'osdev.assets.properties' end
  if category=='vehicles' then return 'osdev.assets.vehicles' end
  local b=id and state.businesses[tostring(id)]
  return (b and b.type=='faccion') and 'osdev.assets.factions' or 'osdev.assets.businesses'
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
  local public=OSDevtools.PublicJobs[job]
  if public then local ok=false;for _,r in ipairs(public.ranks) do if r==rank then ok=true end end
    if not ok then return out(src,('Rangos de %s: %s'):format(public.label,table.concat(public.ranks,', '))) end end
  if action(src,'setjob',function(d) local c=d.characters[who];c.job=job;c.rank=rank;c.duty=false;return true end) then out(src,'Job actualizado: '..who..' -> '..job..'/'..rank,'success')
    for _,p in ipairs(GetPlayers()) do if characterFor(tonumber(p))==who and OSDevtools.PushDutyPoints then OSDevtools.PushDutyPoints(tonumber(p)) end end end
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
    if b.position and OSDevtools.BusinessTypes[b.type] and not OSDevtools.BusinessTypes[b.type].hidden then
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
  if not needAdmin(src,'osdev.assets.properties') then return end
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
  if not needAdmin(src,(args[1] or ''):lower()=='faccion' and 'osdev.assets.factions' or 'osdev.assets.businesses') then return end
  local types={};for key in pairs(OSDevtools.BusinessTypes) do types[#types+1]=key end;table.sort(types)
  local usage='Uso: /crearnegocio <tipo> <nombre> <precio> [job=<job>]. Tipos: '..table.concat(types,', ')..'. Ejemplo: /crearnegocio ltd LTD_Mirror 30000 job=ltd'
  local job
  if args[#args] and args[#args]:lower():match('^job=') then job=args[#args]:sub(5):lower();table.remove(args);if not validAlias(job) then return out(src,'Job no valido.') end end
  local kind=args[1] and args[1]:lower();local price=#args>=3 and money(args[#args]) or nil;local name=#args>=3 and businessName(args) or nil
  if not kind or not OSDevtools.BusinessTypes[kind] or price==nil or not name then return out(src,usage) end
  local pos=getCoords(src);if not pos then return out(src,'Debes ejecutar este comando dentro del juego, en un bucket permitido.') end
  local id
  if action(src,'create business '..kind,function(d)
    id=d.nextBusiness;d.nextBusiness=id+1
    if d.businesses[tostring(id)] then return false,'ERROR: El ID '..id..' ya existe.' end
    d.businesses[tostring(id)]={id=id,type=kind,name=name,price=price,position=pos,job=job}
    return true
  end) then out(src,('Negocio #%d "%s" (%s) creado en tus coordenadas por $%d%s. Sin propietario: /setnegocio %d <destinatario>.'):format(id,name,OSDevtools.BusinessTypes[kind].label,price,job and (', job '..job) or ' (sin job: /negociojob)',id),'success') end
end,false)
local giveKeyItem -- se define en el bloque de llaves (mas abajo)
local function assign(kind,src,args)
  local id=positive(args[1])
  if not needAdmin(src,assetPerm(kind,id)) then return end
  local who=resolve(args[2])
  if not id or not who then return out(src,'Uso: /set'..(kind=='vehicles' and 'vehiculo' or kind=='businesses' and 'negocio' or 'propiedad')..' <id> <idJugador|alias>') end
  if action(src,'assign '..kind,function(d)
    local obj=d[kind][tostring(id)];if not obj then return false,'No existe ese ID en esta categoria.' end
    obj.owner=who;obj.lockVersion=(obj.lockVersion or 1)+1;obj.lent=nil;return true
  end) then
    local given=giveKeyItem(kind,id,who)
    out(src,'Asignado '..kind..' #'..id..' a '..ownerLabel(who)..(given and ' (con su llave).' or ' (no se pudo entregar la llave: /llave).'),'success')
  end
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
  if not needAdmin(src,'osdev.assets.vehicles') then return end
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
      id=d.nextVehicle;d.nextVehicle=id+1;plate=randomPlate(d)
      d.vehicles[tostring(id)]={id=id,model=model,primary=primary,secondary=secondary,fixed=(mode=='fijo'),owner=who,plate=plate,position=point,vtype=vtype}
      return true
    end) then return end
    local entity,err=vehicles.spawn(id,state.vehicles[tostring(id)],point)
    -- La llave: al personaje dueno si se indica; si no, a quien lo crea (sin ella no arranca, tampoco aviones ni barcos).
    local keyFor=who or characterFor(src)
    local keyOk=keyFor and giveKeyItem('vehicles',id,keyFor)
    local keyText=keyOk and (' Llave entregada a %s.'):format(keyFor==who and who or 'ti') or ' No se pudo entregar la llave (usa /llave vehiculo '..id..' <jugador>).'
    if entity then out(src,('Vehiculo #%d (%s, %s) creado delante de ti. Matricula %s.%s'):format(id,model,mode,plate,keyText),'success')
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
  if src<=0 or not ready or #missingTypes==0 or not admin(src,'osdev.assets.vehicles') then return end
  local ids=missingTypes;missingTypes={}
  completeTypes(src,ids,function()
    local created,missing=vehicles.restore()
    for _,id in ipairs(missing) do missingTypes[#missingTypes+1]=id end
    print(('[os_devtools] Vehiculos fijos restaurados tras completar tipos: %d. Pendientes: %d.'):format(created,#missingTypes))
  end)
end)
RegisterCommand('recuperarvehiculo',function(src,args)
  if not needAdmin(src,'osdev.assets.vehicles') then return end
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
  if not needAdmin(src,'osdev.assets.vehicles') then return end
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
  if action(src,'ceder vehicle',function(d) local v=d.vehicles[found];v.owner=to;v.lent=nil;v.lockVersion=(v.lockVersion or 1)+1;return true end) then
    giveKeyItem('vehicles',found,to)
    out(src,'Vehiculo #'..found..' cedido a '..to,'success')
    for _,id in ipairs(GetPlayers()) do if characterFor(tonumber(id))==to then out(tonumber(id),'Has recibido el vehiculo #'..found,'success') end end
  end
end)
for command,event in pairs({setcolor='osdev:doSetColor',setlivery='osdev:doSetLivery',listliveries='osdev:doListLiveries'}) do
  RegisterCommand(command,function(src,args)
    if not needAdmin(src,'osdev.assets.vehicles') then return end
    if src==0 then return out(src,'Comando disponible solo dentro del juego.') end
    TriggerClientEvent(event,src,args)
  end,false)
end

-- Log en la web del panel (os_admin), si esta.
local function panelLog(src,act,target,detail)
  if GetResourceState('os_admin')=='started' then pcall(function() exports.os_admin:PanelLog(src,act,target or '',detail or '') end) end
end
-- /setcar <opcion> ...: gestion rapida de vehiculos para el staff. Sin vehiculo indicado se usa el tuyo (dentro).
--   reparar [id|matricula]                    lo repara donde este (lo hace quien lo tiene cargado; si nadie, se recrea)
--   livery <n> [native|mod48] [id|matricula]  cambia la livery; en vehiculos de os_devtools queda guardada
--   gas <0-100> [id|matricula]                pone la gasolina (LegacyFuel si esta)
--   negocio meter|sacar <idNegocio> [id|mat.] flota de un negocio: su dueno y su plantilla lo pueden usar sin llave
--   faccion meter|sacar <idFaccion> [id|mat.] igual, para facciones
-- Permisos: reparar y gas osadmin.vehicles; livery osdev.assets.vehicles; negocio/faccion ademas
-- osdev.assets.businesses / osdev.assets.factions.
local SETCAR_USAGE='Uso: /setcar reparar [id|matricula] | livery <n> [native|mod48] [id|matricula] | gas <0-100> [id|matricula] | negocio meter|sacar <id> [vehiculo] | faccion meter|sacar <id> [vehiculo]'
local function plateText(entity) return ((GetVehicleNumberPlateText(entity) or ''):gsub('^%s+',''):gsub('%s+$',''):upper()) end
local function recordByPlate(plate) for id,v in pairs(state.vehicles) do if (v.plate or ''):upper()==plate then return tonumber(id),v end end end
-- Vehiculo objetivo: ID del registro, matricula o el que conduces. Devuelve entidad (puede ser nil), id y registro.
local function setcarTarget(src,value)
  if value==nil then
    local ped=GetPlayerPed(src);local entity=ped and ped~=0 and GetVehiclePedIsIn(ped,false) or 0
    if entity==0 then return nil,'Entra en el vehiculo o indica su ID o matricula.' end
    local id,record=recordByPlate(plateText(entity));return entity,nil,id,record
  end
  local id=positive(value);local record=id and state.vehicles[tostring(id)]
  if id and record then return vehicles.find(id,record),nil,id,record end
  local plate=tostring(value):upper()
  if not plate:match('^[%w ]+$') or #plate>8 then return nil,'Vehiculo no encontrado: '..tostring(value) end
  for _,entity in ipairs(GetAllVehicles() or {}) do
    if DoesEntityExist(entity) and plateText(entity)==plate then local rid,rec=recordByPlate(plate);return entity,nil,rid,rec end
  end
  local rid,rec=recordByPlate(plate)
  if rid then return nil,nil,rid,rec end
  return nil,'Vehiculo no encontrado: '..tostring(value)
end
local function ownerOf(entity)
  local owner=entity and NetworkGetEntityOwner(entity)
  return owner and owner>0 and GetPlayerName(owner) and owner or nil
end
local function staffAce(src,ace) return src==0 or IsPlayerAceAllowed(src,ace) end
local setcar={}
function setcar.reparar(src,args)
  if not staffAce(src,'osadmin.vehicles.repair') then return out(src,'No tienes permiso.','error') end
  local entity,err,id,record=setcarTarget(src,args[2]);if err then return out(src,err,'error') end
  if not entity then return out(src,'El vehiculo #'..tostring(id)..' no esta en el mundo: sacalo con /recuperarvehiculo '..tostring(id)..'.','warning') end
  local owner=ownerOf(entity)
  if owner then
    TriggerClientEvent('osdev:setcarEffect',owner,NetworkGetNetworkIdFromEntity(entity),'repair')
  elseif id and record then
    -- Nadie lo tiene cargado: se recrea en el mismo sitio (sale nuevo).
    local p=GetEntityCoords(entity)
    local point={x=p.x,y=p.y,z=p.z,h=GetEntityHeading(entity),bucket=GetEntityRoutingBucket(entity)}
    vehicles.delete(id)
    local ok,why=vehicles.spawn(id,record,point)
    if not ok then return out(src,'No se pudo reparar: '..tostring(why),'error') end
  else return out(src,'Nadie tiene ese vehiculo cargado; acercate a el y repite.','warning') end
  out(src,'Vehiculo '..(id and ('#'..id) or plateText(entity))..' reparado.','success')
  panelLog(src,'setcar reparar',id and tostring(id) or plateText(entity))
end
function setcar.gas(src,args)
  if not staffAce(src,'osadmin.vehicles.fuel') then return out(src,'No tienes permiso.','error') end
  local amount=integer(args[2]);if not amount or amount<0 or amount>100 then return out(src,'Uso: /setcar gas <0-100> [id|matricula]') end
  local entity,err,id=setcarTarget(src,args[3]);if err then return out(src,err,'error') end
  local owner=ownerOf(entity)
  if not owner then return out(src,'Ese vehiculo no esta cargado por nadie; acercate a el y repite.','warning') end
  TriggerClientEvent('osdev:setcarEffect',owner,NetworkGetNetworkIdFromEntity(entity),'fuel',amount)
  out(src,('Gasolina al %d%%.'):format(amount),'success')
  panelLog(src,'setcar gas',id and tostring(id) or plateText(entity),tostring(amount))
end
function setcar.livery(src,args)
  if not needAdmin(src,'osdev.assets.vehicles') then return end
  local index=integer(args[2]);if not index or index<0 or index>255 then return out(src,'Uso: /setcar livery <n> [native|mod48] [id|matricula]') end
  local kind=(args[3]=='native' or args[3]=='mod48') and args[3] or nil
  local entity,err=setcarTarget(src,kind and args[4] or args[3]);if err then return out(src,err,'error') end
  if not entity then return out(src,'El vehiculo no esta en el mundo.','warning') end
  if src==0 then return out(src,'La livery se elige dentro del juego (hay que mirar que tipos admite el modelo).') end
  -- El tipo de livery solo lo sabe un cliente: lo comprueba quien da la orden y responde con osdev:setcarLivery.
  TriggerClientEvent('osdev:setcarLiveryCheck',src,NetworkGetNetworkIdFromEntity(entity),index,kind)
end
RegisterNetEvent('osdev:setcarLivery',function(netId,index,kind)
  local src=source
  index=math.tointeger(tonumber(index))
  if not admin(src,'osdev.assets.vehicles') or not index or index<0 or index>255 or (kind~='native' and kind~='mod48') then return end
  local entity=NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
  if not entity or entity==0 or not DoesEntityExist(entity) then return end
  local id,record=recordByPlate(plateText(entity))
  if id then
    if not action(src,'setcar livery '..id,function(d) local v=d.vehicles[tostring(id)];v.livery=index;v.liveryType=kind;return true end) then return end
    vehicles.refreshLook(id,state.vehicles[tostring(id)]) -- quien lo controla aplica el aspecto guardado
  end
  local owner=ownerOf(entity)
  if owner then TriggerClientEvent('osdev:setcarEffect',owner,netId,'livery',{index=index,kind=kind}) end
  out(src,('Livery %d (%s)%s.'):format(index,kind,id and ' guardada' or ''),'success')
  panelLog(src,'setcar livery',id and tostring(id) or plateText(entity),tostring(index))
end)
-- Flota de un negocio o faccion.
local function setcarFleet(src,args,faction)
  if not needAdmin(src,'osdev.assets.vehicles') or not needAdmin(src,faction and 'osdev.assets.factions' or 'osdev.assets.businesses') then return end
  local mode=(args[2] or ''):lower();local bid=positive(args[3])
  local word=faction and 'faccion' or 'negocio'
  if (mode~='meter' and mode~='sacar') or not bid then return out(src,('Uso: /setcar %s meter|sacar <id%s> [id|matricula del vehiculo]'):format(word,faction and 'Faccion' or 'Negocio')) end
  local b=state.businesses[tostring(bid)]
  if not b or (b.type=='faccion')~=faction then return out(src,('No existe %s #%d.'):format(faction and 'la faccion' or 'el negocio',bid),'error') end
  local _,err,id,record=setcarTarget(src,args[4]);if err then return out(src,err,'error') end
  if not id then return out(src,'Solo los vehiculos registrados (os_devtools) pueden ser de una flota.','warning') end
  if mode=='sacar' and record.fleet~=bid then return out(src,('El vehiculo #%d no es de %s #%d.'):format(id,word,bid),'warning') end
  if action(src,'setcar '..word..' '..mode..' '..id..' '..bid,function(d) d.vehicles[tostring(id)].fleet=mode=='meter' and bid or nil;return true end) then
    out(src,('Vehiculo #%d %s %s #%d (%s).'):format(id,mode=='meter' and 'anadido a' or 'retirado de',word,bid,b.name or ''),'success')
  end
end
function setcar.negocio(src,args) setcarFleet(src,args,false) end
function setcar.faccion(src,args) setcarFleet(src,args,true) end
RegisterCommand('setcar',function(src,args)
  local handler=setcar[(args[1] or ''):lower()]
  if not handler then return out(src,SETCAR_USAGE) end
  handler(src,args)
end,false)
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
-- Web del panel (via os_admin): bienes (altas, cambios, bajas) y auditoria de cambios, agrupados en 1 s.
local panelLast,panelChars,panelMarker,panelQueued=nil,nil,nil,false
local function panelSync()
  panelQueued=false
  if not ready or GetResourceState('os_admin')~='started' then return end
  local changes,current=OSDevtools.PanelSync.diff(state,panelLast or {},assetLabel)
  for _,p in ipairs(changes) do
    local ok,accepted=pcall(function() return exports.os_admin:PanelTrack('asset',p) end)
    if not ok or not accepted then return end -- web desactivada: se reintenta en el siguiente cambio
  end
  panelLast=current
  local people,known=OSDevtools.PanelSync.characters(state,panelChars or {})
  for _,p in ipairs(people) do
    local ok,accepted=pcall(function() return exports.os_admin:PanelTrack('character',p) end)
    if not ok or not accepted then return end
  end
  panelChars=known
  local entries;entries,panelMarker=OSDevtools.PanelSync.newAudit(state.audit or {},panelMarker)
  for _,e in ipairs(entries) do
    local op=tostring(e.operation or '')
    pcall(function() exports.os_admin:PanelLog(tostring(e.actor or 'sistema'),op:match('^(%S+)') or 'cambio',op:match('^%S+%s+(%S+)') or '',op) end)
  end
end
local function queuePanelSync() if not panelQueued then panelQueued=true;SetTimeout(1000,panelSync) end end
AddEventHandler('onResourceStart',function(name) if name=='os_admin' then panelLast=nil;panelChars=nil;SetTimeout(3000,queuePanelSync) end end)
core=OSDevtools.Core.new({
  storage=storage,now=os.time,clock=GetGameTimer,connected=function(src) return GetPlayerName(src)~=nil end,
  -- Sistema de heridos: con os_life arrancado, al morir no se reaparece solo (inconsciente, EMS u hospital).
  downed=function() return GetResourceState('os_life')=='started' end,
  identifiers=GetPlayerIdentifiers,
  world=function(src)
    local ped=GetPlayerPed(src)
    if not ped or ped==0 or not DoesEntityExist(ped) then return nil,nil end
    local point=GetEntityCoords(ped)
    if not point then return nil,nil end
    return {x=point.x,y=point.y,z=point.z,h=GetEntityHeading(ped),bucket=GetPlayerRoutingBucket(src)},GetEntityHealth(ped)
  end,
  schedule=SetTimeout,
  publish=function(snapshot,status) state=snapshot;ready=status;pushAllHud();if ready then pushBlips();queuePanelSync() end end,
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
  if not ready or not ({businesses=true,properties=true,vehicles=true})[category] then return nil end
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


-- Llaves ---------------------------------------------------------------------------------------------------------
-- Las llaves son objetos de os_inventory: "llave" (propiedades y negocios) y "llave-tarjeta" (vehiculos). Cada una abre
-- la version actual de la cerradura del bien (record.lockVersion). Para entrar hace falta llevarla, tambien al titular.
-- El titular recibe una al asignarse o crearse el bien; /darllave... crea copias para otros; /quitarllave... cambia la
-- cerradura (las copias dejan de servir) y el titular recibe una llave nueva.
local KEY_ITEM={properties='llave',businesses='llave',vehicles='llave_vehiculo'}
local KEY_KIND={properties='property',businesses='business',vehicles='vehicle'}
local KEY_CATEGORY={prop='properties',propiedad='properties',negocio='businesses',vehiculo='vehicles',h='vehicles'}
-- Vehiculos clasicos (config/classic_vehicles.lua): llave fisica; el resto, llave-tarjeta.
local function keyItem(category,r) if category=='vehicles' and OSDevtools.IsClassicVehicle(r.model) then return 'llave' end;return KEY_ITEM[category] end
local function keyLabel(category,id,r)
  if category=='vehicles' then return ('%s · %s %s'):format(OSDevtools.IsClassicVehicle(r.model) and 'Llave' or 'Llave-tarjeta',r.model or 'vehiculo',r.plate or '') end
  if category=='businesses' then return 'Llave · '..(r.name or ('Negocio #'..id)) end
  return 'Llave · Propiedad #'..id
end
function giveKeyItem(category,id,alias)
  local r=state[category][tostring(id)];local c=alias and state.characters[alias]
  if not r or not c then return false,'Bien o personaje no encontrado.' end
  if GetResourceState('os_inventory')~='started' then return false,'Inventario no disponible.' end
  local meta={kind=KEY_KIND[category],target=tostring(id),version=tostring(r.lockVersion or 1),label=keyLabel(category,id,r),plate=category=='vehicles' and r.plate or nil}
  local ok,res,err=pcall(function() return exports.os_inventory:AddItem(c.id,keyItem(category,r),1,meta) end)
  if not ok then return false,'Inventario no disponible.' end
  return res==true,err
end
local function holdsKey(src,category,id)
  local r=state[category] and state[category][tostring(id)]
  if not r then return false end
  -- Vehiculo de flota (/setcar negocio|faccion meter): el dueno y la plantilla del negocio o faccion lo usan sin llave.
  if category=='vehicles' and r.fleet then
    local b=state.businesses[tostring(r.fleet)];local alias=characterFor(src)
    if b and alias and (b.owner==alias or (b.staff and b.staff[alias])) then return true end
  end
  if GetResourceState('os_inventory')~='started' then return false end
  local ok,res=pcall(function() return exports.os_inventory:HasKey(src,KEY_KIND[category],tostring(id),tostring(r.lockVersion or 1)) end)
  return ok and res==true
end
local function notifyAliasKey(alias,text) for _,p in ipairs(GetPlayers()) do if characterFor(tonumber(p))==alias then out(tonumber(p),text,'success') end end end
-- Cambia la cerradura (version+1) y entrega una llave nueva al titular.
local function changeLock(src,category,id)
  local key=tostring(id)
  if not action(src,'cambiar cerradura '..category..' '..key,function(d) local r=d[category][key];r.lockVersion=(r.lockVersion or 1)+1;r.lent=nil;return true end) then return false end
  local r=state[category][key]
  if r.owner then giveKeyItem(category,id,r.owner) end
  return true
end
local function giveCopy(category,label)
  return function(src,args)
    local me=exists(src);if not me then return end
    local id=positive(args[1]);local who=args[2] and resolve(args[2])
    local record=id and state[category][tostring(id)]
    if not record or not who then return out(src,('Uso: /darllave%s <id> <idJugador|alias>'):format(label)) end
    if record.owner~=me then return out(src,'Solo el titular puede hacer copias de la llave.','error') end
    local ok,err=giveKeyItem(category,id,who)
    if not ok then return out(src,'No se pudo entregar la llave: '..tostring(err),'error') end
    out(src,('Copia de la llave de %s entregada a %s.'):format(assetLabel(category,id,record),who),'success')
    if who~=me then notifyAliasKey(who,('Has recibido una llave: %s.'):format(keyLabel(category,id,record))) end
  end
end
local function replaceLock(category,label)
  return function(src,args)
    local me=exists(src);if not me then return end
    local id=positive(args[1]);local record=id and state[category][tostring(id)]
    if not record then return out(src,('Uso: /quitarllave%s <id> (cambia la cerradura: las copias dejan de servir)'):format(label)) end
    if record.owner~=me then return out(src,'Solo el titular puede cambiar la cerradura.','error') end
    if changeLock(src,category,id) then out(src,'Cerradura cambiada: las llaves anteriores ya no sirven. Tienes una llave nueva.','success') end
  end
end
RegisterCommand('darllaveprop',giveCopy('properties','prop'),false)
RegisterCommand('darllaveh',giveCopy('vehicles','h'),false)
RegisterCommand('darllavenegocio',giveCopy('businesses','negocio'),false)
RegisterCommand('quitarllaveprop',replaceLock('properties','prop'),false)
RegisterCommand('quitarllaveh',replaceLock('vehicles','h'),false)
RegisterCommand('quitarllavenegocio',replaceLock('businesses','negocio'),false)
-- Admin: llave de cualquier bien para cualquier personaje (p. ej. si el titular la ha perdido).
RegisterCommand('llave',function(src,args)
  local category=KEY_CATEGORY[(args[1] or ''):lower()];local id=positive(args[2]);
  if not needAdmin(src,category and assetPerm(category,id) or 'osdev.assets') then return end
 local who=args[3] and resolve(args[3])
  if not category or not id or not who or not state[category][tostring(id)] then return out(src,'Uso: /llave <propiedad|negocio|vehiculo> <id> <idJugador|alias>') end
  local ok,err=giveKeyItem(category,id,who)
  out(src,ok and ('Llave de #%d entregada a %s.'):format(id,who) or ('No se pudo: '..tostring(err)),ok and 'success' or 'error')
end,false)

-- Job del negocio (admin): sin job no se puede contratar a nadie.
RegisterCommand('negociojob',function(src,args)
  local id=positive(args[1]);
  if not needAdmin(src,assetPerm('businesses',id)) then return end
 local job=args[2] and args[2]:lower()
  if not id or not state.businesses[tostring(id)] or not validAlias(job) then return out(src,'Uso: /negociojob <idNegocio> <job>') end
  if action(src,'negociojob '..id..' '..job,function(d) d.businesses[tostring(id)].job=job;return true end) then out(src,'Negocio #'..id..' con job '..job..'.','success') end
end,false)

local B=OSDevtools.CoreConfig.Business
local invites={} -- invitado (source) -> {business, rank, from, until}
local function ownedBy(alias)
  local list={}
  for id,r in pairs(state.businesses) do if r.owner==alias then list[#list+1]=id end end
  table.sort(list,function(a,b) return tonumber(a)<tonumber(b) end)
  return list
end
local function nearbyPlayers(src)
  local here=GetEntityCoords(GetPlayerPed(src));local list={}
  for _,player in ipairs(GetPlayers()) do
    local other=tonumber(player)
    if other~=src and GetPlayerRoutingBucket(other)==GetPlayerRoutingBucket(src) and #(GetEntityCoords(GetPlayerPed(other))-here)<=B.InviteDistance then
      local alias=characterFor(other)
      if alias then list[#list+1]={id=other,name=alias} end
    end
  end
  return list
end
local function businessView(src,alias)
  local list={}
  for _,id in ipairs(ownedBy(alias)) do
    local r=state.businesses[id];local staff={}
    for who,rank in pairs(r.staff or {}) do staff[#staff+1]={alias=who,rank=rank} end
    table.sort(staff,function(a,b) return a.alias<b.alias end)
    list[#list+1]={id=tonumber(id),name=r.name,label=assetLabel('businesses',id,r),job=r.job,ranks=r.ranks or {},staff=staff,salaries=r.salaries or {},dutyPoint=r.dutyPoint~=nil}
  end
  return {businesses=list,players=nearbyPlayers(src),minRanks=B.MinRanks,maxRanks=B.MaxRanks,payMinutes=B.PayMinutes,maxSalary=B.MaxSalary}
end
local function sendBusiness(src,message,kind)
  local alias=characterFor(src);if not alias then return end
  TriggerClientEvent('osdev:business:data',src,businessView(src,alias),message,kind)
end
local function ownBusiness(src,id)
  local alias=characterFor(src);local key=tostring(tonumber(id) or '')
  local r=alias and state.businesses[key]
  if not r or r.owner~=alias then return nil end
  return key,r,alias
end
local function rankIndex(r,name) for i,rank in ipairs(r.ranks or {}) do if rank==name then return i end end end

RegisterCommand('negocio',function(src)
  local alias=exists(src);if not alias then return end
  if #ownedBy(alias)==0 then return out(src,'No eres titular de ningun negocio.','warning') end
  if OSDevtools.JobView then OSDevtools.JobView[src]=nil end
  TriggerClientEvent('osdev:business:open',src)
  sendBusiness(src)
end,false)
RegisterNetEvent('osdev:business:refresh',function() if OSDevtools.JobView and OSDevtools.JobView[source] then return end;sendBusiness(source) end)

-- Rangos: anadir (al final = el mas alto), subir/bajar orden o borrar si nadie lo tiene.
RegisterNetEvent('osdev:business:rank',function(id,op,name,dir)
  local src=source;local key,r=ownBusiness(src,id)
  if not key then return end
  if type(name)~='string' then return end
  name=name:lower():gsub('^%s+',''):gsub('%s+$','')
  local ok,err=core.change(src,'negocio rango '..key,function(d)
    local b=d.businesses[key];b.ranks=b.ranks or {}
    local index=rankIndex(b,name)
    if op=='add' then
      if not validAlias(name) or #name>20 then return false,'Nombre de rango no valido (letras, numeros o _).' end
      if index then return false,'Ese rango ya existe.' end
      if #b.ranks>=B.MaxRanks then return false,'Maximo '..B.MaxRanks..' rangos.' end
      b.ranks[#b.ranks+1]=name
    elseif op=='remove' then
      if not index then return false,'Ese rango no existe.' end
      for _,rank in pairs(b.staff or {}) do if rank==name then return false,'Alguien tiene ese rango: cambialo antes.' end end
      table.remove(b.ranks,index)
      if b.salaries then b.salaries[name]=nil;if next(b.salaries)==nil then b.salaries=nil end end
    elseif op=='move' then
      local to=index and index+(dir=='up' and 1 or -1)
      if not index or to<1 or to>#b.ranks then return false,'No se puede mover.' end
      b.ranks[index],b.ranks[to]=b.ranks[to],b.ranks[index]
    else return false,'Operacion no valida.' end
    if #b.ranks==0 then b.ranks=nil end
    return true
  end)
  sendBusiness(src,ok and 'Rangos actualizados.' or err,ok and 'success' or 'error')
end)

-- Sueldo de un rango (0 = sin sueldo).
RegisterNetEvent('osdev:business:salary',function(id,rank,amount)
  local src=source;local key,r=ownBusiness(src,id)
  if not key or type(rank)~='string' then return end
  amount=math.tointeger(tonumber(amount))
  if not amount or amount<0 or amount>B.MaxSalary then return sendBusiness(src,('El sueldo va de $0 a $%d.'):format(B.MaxSalary),'error') end
  local ok,err=core.change(src,'negocio sueldo '..key..' '..rank..' '..amount,function(d)
    local b=d.businesses[key];if not rankIndex(b,rank) then return false,'Ese rango no existe.' end
    b.salaries=b.salaries or {};b.salaries[rank]=amount>0 and amount or nil
    if next(b.salaries)==nil then b.salaries=nil end
    return true
  end)
  local every=B.PayMinutes==60 and 'hora' or (B.PayMinutes..' min')
  sendBusiness(src,ok and ('Sueldo de %s: $%d por %s conectado.'):format(rank,amount,every) or err,ok and 'success' or 'error')
end)

-- Nominas: cada minuto se cuenta a quien esta DE SERVICIO (fichado en el punto de servicio) con el job de un negocio
-- en el que trabaja; al llegar a PayMinutes cobra el sueldo de su rango del banco del titular.
local worked={}
local function notifyAlias(alias,text,kind) for _,player in ipairs(GetPlayers()) do if characterFor(tonumber(player))==alias then out(tonumber(player),text,kind) end end end
CreateThread(function()
  while true do
    Wait(60000)
    for _,player in ipairs(GetPlayers()) do
      local src=tonumber(player);local alias=characterFor(src);local c=alias and state.characters[alias]
      local key,b
      if c and c.job and c.duty then for id,r in pairs(state.businesses) do if r.job==c.job and r.staff and r.staff[alias] then key,b=id,r;break end end end
      local public=c and c.duty and c.job and OSDevtools.PublicJobs[c.job]
      if public then
        worked[src]=(worked[src] or 0)+1
        if worked[src]>=B.PayMinutes then
          worked[src]=0
          local index=1;for i,r in ipairs(public.ranks) do if r==c.rank then index=i end end
          local amount=public.salaries[index] or 0
          if amount>0 and core.change(src,('nomina publica %s %s %d'):format(c.job,alias,amount),function(d) local ch=d.characters[alias];ch.bank=(tonumber(ch.bank) or 0)+amount;return true end) then
            out(src,('Nomina de %s: $%d (%s).'):format(public.label,amount,c.rank),'success')
          end
        end
      elseif not b then worked[src]=nil else
        worked[src]=(worked[src] or 0)+1
        if worked[src]>=B.PayMinutes then
          worked[src]=0
          local rank=b.staff[alias];local amount=b.salaries and b.salaries[rank] or 0
          if amount>0 and b.owner and b.owner~=alias then
            local owner=b.owner
            local ok,err=core.change(src,('nomina %s %s %d'):format(key,alias,amount),function(d)
              local from,to=d.characters[owner],d.characters[alias]
              if not from or not to then return false,'Personaje no encontrado.' end
              if (tonumber(from.bank) or 0)<amount then return false,'insufficient_funds' end
              from.bank=from.bank-amount;to.bank=(tonumber(to.bank) or 0)+amount;return true
            end)
            if ok then
              out(src,('Nomina de %s: $%d (%s).'):format(b.name,amount,rank),'success')
              notifyAlias(owner,('Pagada la nomina de %s: $%d.'):format(alias,amount),'info')
            else
              out(src,('%s no ha podido pagarte la nomina ($%d).'):format(b.name,amount),'warning')
              notifyAlias(owner,('No hay saldo en el banco para la nomina de %s ($%d).'):format(alias,amount),'warning')
            end
          end
        end
      end
    end
  end
end)
AddEventHandler('playerDropped',function() worked[source]=nil end)

-- Contratar: invitacion al jugador cercano, que acepta o rechaza.
RegisterNetEvent('osdev:business:invite',function(id,target,rank)
  local src=source;local key,r,alias=ownBusiness(src,id);target=tonumber(target)
  if not key or not target then return end
  local function fail(text) sendBusiness(src,text,'error') end
  if not r.job then return fail('Este negocio no tiene job: pide a un administrador /negociojob '..key..' <job>.') end
  if #(r.ranks or {})<B.MinRanks then return fail(('Crea al menos %d rangos antes de contratar.'):format(B.MinRanks)) end
  if not rankIndex(r,rank) then return fail('Elige un rango del negocio.') end
  local near=false;for _,p in ipairs(nearbyPlayers(src)) do if p.id==target then near=true end end
  if not near then return fail('Ese jugador no esta cerca.') end
  local who=characterFor(target)
  if not who or who==alias then return fail('Jugador no valido.') end
  if r.staff and r.staff[who] then return fail('Ya trabaja aqui.') end
  local count=0;for _ in pairs(r.staff or {}) do count=count+1 end
  if count>=B.MaxStaff then return fail('Plantilla completa.') end
  if invites[target] and invites[target].untilAt>os.time() then return fail('Ese jugador ya tiene una invitacion pendiente.') end
  invites[target]={business=key,rank=rank,from=src,untilAt=os.time()+B.InviteSeconds}
  TriggerClientEvent('osdev:business:invited',target,{business=r.name,rank=rank,from=alias,seconds=B.InviteSeconds})
  sendBusiness(src,'Invitacion enviada a '..who..'.','success')
end)
RegisterNetEvent('osdev:business:answer',function(accept)
  local src=source;local invite=invites[src];invites[src]=nil
  if not invite and OSDevtools.JobInvites and OSDevtools.JobInvites[src] then return end -- es una oferta de trabajo publico
  if not invite or invite.untilAt<os.time() then return out(src,'La invitacion ha caducado.','warning') end
  local r=state.businesses[invite.business];local who=characterFor(src)
  if not r or not who or not rankIndex(r,invite.rank) or not r.job then return out(src,'La invitacion ya no es valida.','error') end
  if not accept then
    if GetPlayerName(invite.from) then sendBusiness(invite.from,who..' ha rechazado la oferta.','warning') end
    return out(src,'Has rechazado la oferta.','info')
  end
  if action(src,'contratado '..invite.business..' '..who,function(d)
    local b=d.businesses[invite.business];b.staff=b.staff or {};b.staff[who]=invite.rank
    local c=d.characters[who];c.job=r.job;c.rank=invite.rank;c.duty=false;return true end) then
    out(src,('Ahora trabajas en %s como %s.'):format(r.name,invite.rank),'success')
    if OSDevtools.PushDutyPoints then OSDevtools.PushDutyPoints(src) end
    if GetPlayerName(invite.from) then sendBusiness(invite.from,who..' ha aceptado. Bienvenido a la plantilla.','success') end
  end
end)
AddEventHandler('playerDropped',function() invites[source]=nil end)

-- Plantilla: cambiar rango o despedir. Despedir quita el job si era el de este negocio.
RegisterNetEvent('osdev:business:staff',function(id,who,op,rank)
  local src=source;local key,r=ownBusiness(src,id)
  if not key or type(who)~='string' or not (r.staff and r.staff[who]) then return end
  local ok,err=core.change(src,'negocio plantilla '..key..' '..who,function(d)
    local b=d.businesses[key];local c=d.characters[who]
    if op=='rank' then
      if not rankIndex(b,rank) then return false,'Rango no valido.' end
      b.staff[who]=rank;if c and c.job==b.job then c.rank=rank end
    elseif op=='fire' then
      b.staff[who]=nil;if next(b.staff)==nil then b.staff=nil end
      if c and c.job==b.job then c.job=nil;c.rank=nil;c.duty=false end
    else return false,'Operacion no valida.' end
    return true
  end)
  sendBusiness(src,ok and 'Plantilla actualizada.' or err,ok and 'success' or 'error')
end)

-- Ficha completa del personaje activo para /stats (os_hud). Solo para recursos de IdentityReaders.
local function statsReader()
  local caller=GetInvokingResource()
  return caller==nil or caller==RESOURCE or OSDevtools.CoreConfig.IdentityReaders[caller]==true
end
-- Matricula de un vehiculo del registro por su ID (os_admin: /ircoche y /traerveh).
exports('GetVehiclePlate',function(id)
  local v=math.tointeger(tonumber(id)) and state.vehicles[tostring(math.tointeger(tonumber(id)))]
  return v and v.plate or nil
end)
exports('GetCharacterStats',function(src)
  if not statsReader() then return nil,'resource_not_authorized' end
  local alias=characterFor(src);local c=alias and state.characters[alias]
  if not c then return nil,'no_character' end
  -- Punto (x, y, z) redondeado para el GPS del menu de inicio; sin bucket ni rumbo.
  local function spot(p) return type(p)=='table' and tonumber(p.x) and {x=math.floor(p.x*10+0.5)/10,y=math.floor(p.y*10+0.5)/10,z=math.floor((tonumber(p.z) or 0)*10+0.5)/10} or nil end
  local function entry(category,id,record,extra)
    local item={id=tonumber(id),label=assetLabel(category,id,record),owner=record.owner,plate=record.plate,type=record.type,
      price=tonumber(record.price),position=spot(record.position)}
    if category=='vehicles' then
      item.model,item.vtype,item.fixed=record.model,record.vtype,record.fixed==true
      -- En la calle: posicion real de su entidad (si esta generada).
      local entity=vehicles and vehicles.find(tonumber(id),record)
      if entity and DoesEntityExist(entity) then item.out=true;item.position=spot(GetEntityCoords(entity)) end
    elseif category=='businesses' then
      local count=0;for _ in pairs(record.staff or {}) do count=count+1 end
      item.staffCount,item.job,item.dutyPoint=count,record.job,spot(record.dutyPoint)
    end
    for k,v in pairs(extra or {}) do item[k]=v end
    return item
  end
  local result={characterId=c.id,alias=alias,job=c.job,rank=c.rank,duty=c.duty==true,cash=c.cash or 0,bank=c.bank or 0,
    vehicles={},vehiclesLent={},businesses={},businessesStaff={},properties={},propertiesLent={}}
  for _,pair in ipairs({{'vehicles','vehicles'},{'properties','properties'}}) do
    for id,record in pairs(state[pair[1]]) do
      if record.owner==alias then result[pair[2]][#result[pair[2]]+1]=entry(pair[1],id,record) end
    end
  end
  -- Bienes de otros de los que lleva una llave valida.
  if GetResourceState('os_inventory')=='started' then
    local ok,keys=pcall(function() return exports.os_inventory:ListKeys(src) end)
    local seen={}
    for _,k in ipairs(ok and type(keys)=='table' and keys or {}) do
      local category=(k.kind=='vehicle' and 'vehicles') or (k.kind=='property' and 'properties') or nil
      local record=category and state[category][tostring(k.target)]
      if record and record.owner~=alias and tostring(record.lockVersion or 1)==k.version and not seen[category..k.target] then
        seen[category..k.target]=true
        local list=category=='vehicles' and result.vehiclesLent or result.propertiesLent
        list[#list+1]=entry(category,k.target,record)
      end
    end
  end
  for id,record in pairs(state.businesses) do
    if record.owner==alias then result.businesses[#result.businesses+1]=entry('businesses',id,record)
    elseif record.staff and record.staff[alias] then result.businessesStaff[#result.businessesStaff+1]=entry('businesses',id,record,{rank=record.staff[alias],salary=record.salaries and record.salaries[record.staff[alias]] or 0}) end
  end
  for _,key in ipairs({'vehicles','vehiclesLent','businesses','businessesStaff','properties','propertiesLent'}) do
    table.sort(result[key],function(a,b) return a.id<b.id end)
  end
  -- Trabajo publico: nombre, escala de rangos, sueldo y puntos de servicio (menu de inicio de os_hud).
  local job=c.job and OSDevtools.PublicJobs and OSDevtools.PublicJobs[c.job]
  if job then
    local index=1;for i,r in ipairs(job.ranks) do if r==c.rank then index=i end end
    local points={};for _,p in ipairs(OSDevtools.JobPoints and OSDevtools.JobPoints(c.job) or job.duty or {}) do points[#points+1]={label=p.label or job.label,x=p.x,y=p.y,z=p.z} end
    result.jobInfo={label=job.label,ranks=job.ranks,rankIndex=index,salary=job.salaries and job.salaries[index] or 0,boss=index>=(job.boss or 99),points=points,
      payMinutes=OSDevtools.CoreConfig.Business and OSDevtools.CoreConfig.Business.PayMinutes or nil}
  end
  -- Trabajos publicos que existen (para quien no tiene ninguno).
  result.publicJobs={}
  for name,j in pairs(OSDevtools.PublicJobs or {}) do
    local min,max;for _,v in ipairs(j.salaries or {}) do min=math.min(min or v,v);max=math.max(max or v,v) end
    local first=(OSDevtools.JobPoints and OSDevtools.JobPoints(name) or j.duty or {})[1]
    result.publicJobs[#result.publicJobs+1]={name=name,label=j.label,min=min or 0,max=max or 0,point=first and {label=first.label or j.label,x=first.x,y=first.y,z=first.z} or nil}
  end
  table.sort(result.publicJobs,function(a,b) return a.label<b.label end)
  return result
end)
exports('HasAssetAccess',function(src,category,id)
  if not statsReader() then return false end
  local alias=characterFor(src);local record=alias and state[category] and state[category][tostring(id)]
  if not record then return false end
  return holdsKey(src,category,id)
end)


-- Chat: el autor de los mensajes es el personaje activo ("Oscar Vega"), no el nombre de la cuenta de FiveM.
-- Se usa el hook oficial del chat de sistema; sin personaje se deja el nombre que ponga el chat.
local function characterName(alias)
  return (alias:gsub('_',' '):gsub('(%a)([%w]*)',function(first,rest) return first:upper()..rest end))
end
exports('GetCharacterName',function(src) local alias=characterFor(src);return alias and characterName(alias) or nil end)
CreateThread(function()
  local deadline=GetGameTimer()+30000
  while GetResourceState('chat')~='started' and GetGameTimer()<deadline do Wait(500) end
  local ok=pcall(function()
    exports.chat:registerMessageHook(function(source,message,hook)
      if type(source)~='number' or source<1 or type(message)~='table' or type(message.args)~='table' or #message.args<2 then return end
      local alias=characterFor(source)
      if alias then hook.updateMessage({args={characterName(alias),message.args[#message.args]}}) end
    end)
  end)
  if not ok then print('[os_devtools] No se pudo enganchar al chat: los mensajes saldran con el nombre de FiveM.') end
end)


-- Puntos de servicio ---------------------------------------------------------------------------------------------
-- Cada titular pone el punto de servicio de su negocio (/negocio > "Poner punto de servicio aqui"). Alli, con E, la
-- plantilla (y el titular) entra o sale de servicio. Al desconectarse se sale de servicio.
local onDuty={} -- source -> alias (para sacarle de servicio al salir)
local function dutyPointsFor(src)
  local alias=characterFor(src);local c=alias and state.characters[alias];local list={}
  if not c then return list end
  local job=c.job and OSDevtools.PublicJobs[c.job]
  if job then
    for i,p in ipairs(OSDevtools.JobPoints(c.job)) do list[#list+1]={id=('job:%s:%d'):format(c.job,i),name=(p.label or job.label),x=p.x,y=p.y,z=p.z,onDuty=c.duty==true} end
  end
  for id,r in pairs(state.businesses) do
    if r.dutyPoint and r.job and (r.owner==alias or (r.staff and r.staff[alias])) then
      list[#list+1]={id=tonumber(id),name=r.name,x=r.dutyPoint.x,y=r.dutyPoint.y,z=r.dutyPoint.z,onDuty=c.duty==true and c.job==r.job}
    end
  end
  return list
end
local function pushDutyPoints(src) TriggerClientEvent('osdev:dutyPoints',src,dutyPointsFor(src)) end
OSDevtools.PushDutyPoints=pushDutyPoints
RegisterNetEvent('osdev:dutyPointsRequest',function() pushDutyPoints(source) end)
RegisterNetEvent('osdev:business:dutyPoint',function(id)
  local src=source;local key=ownBusiness(src,id)
  if not key then return end
  local pos=getCoords(src);if not pos then return sendBusiness(src,'No se pudo leer tu posicion.','error') end
  local ok,err=core.change(src,'negocio punto servicio '..key,function(d) d.businesses[key].dutyPoint={x=pos.x,y=pos.y,z=pos.z};return true end)
  sendBusiness(src,ok and 'Punto de servicio puesto aqui. Tu plantilla ficha con E en este sitio.' or err,ok and 'success' or 'error')
  if ok then for _,p in ipairs(GetPlayers()) do pushDutyPoints(tonumber(p)) end end
end)
RegisterNetEvent('osdev:business:duty',function(id)
  local src=source;local key=tostring(tonumber(id) or '');local r=state.businesses[key]
  local alias=characterFor(src);local c=alias and state.characters[alias]
  if not r or not c or not r.dutyPoint or not r.job then return end
  if not (r.owner==alias or (r.staff and r.staff[alias])) then return out(src,'No trabajas en este negocio.','error') end
  local pos=getCoords(src);local p=r.dutyPoint
  if not pos or (pos.x-p.x)^2+(pos.y-p.y)^2+(pos.z-p.z)^2>9 then return out(src,'Acercate al punto de servicio.','warning') end
  local entering=not (c.duty and c.job==r.job)
  local ok=action(src,'servicio '..key..' '..alias..' '..tostring(entering),function(d)
    local ch=d.characters[alias]
    if entering then
      -- El titular que no esta en plantilla entra con el rango mas alto.
      local rank=r.staff and r.staff[alias] or (r.ranks and r.ranks[#r.ranks]) or 'titular'
      ch.job=r.job;ch.rank=rank;ch.duty=true
    else ch.duty=false end
    return true
  end)
  if not ok then return end
  if entering then onDuty[src]=alias else onDuty[src]=nil end
  out(src,entering and ('De servicio en %s.'):format(r.name) or ('Fuera de servicio en %s.'):format(r.name),entering and 'success' or 'info')
  pushDutyPoints(src);pushHud(src)
end)
AddEventHandler('playerDropped',function()
  local alias=onDuty[source];onDuty[source]=nil
  if alias and state.characters[alias] and state.characters[alias].duty then
    core.change(0,'fuera de servicio al salir '..alias,function(d) d.characters[alias].duty=false;return true end)
  end
end)


-- Concesionarios (config/dealerships.lua + data/dealerships.json) -------------------------------------------------------
-- Valores de serie en config; lo que cambian los administradores en /concesionarios (precios, modelos, puntos) se guarda
-- en data/dealerships.json por concesionario y manda sobre el config.
local dealerOverrides=(function() local raw=LoadResourceFile(RESOURCE,'data/dealerships.json');local ok,data=pcall(json.decode,raw or '{}');return ok and type(data)=='table' and data or {} end)()
local dealer
-- Concesionarios para el menu de inicio (os_hud): nombre, mostrador, numero de modelos y rango de precios.
exports('GetDealerList',function()
  if not statsReader() then return nil end
  local list={}
  for id in pairs(OSDevtools.Dealerships or {}) do
    local d=dealer(id)
    if d then
      local min,max,cheap=nil,nil,{}
      for _,e in ipairs(d.catalog or {}) do min=math.min(min or e.price,e.price);max=math.max(max or e.price,e.price);cheap[#cheap+1]={label=e.label,price=e.price} end
      table.sort(cheap,function(a,b) return a.price<b.price end)
      list[#list+1]={id=id,label=d.label,order=d.order,count=#(d.catalog or {}),min=min or 0,max=max or 0,top={cheap[1],cheap[2],cheap[3]},
        point={x=d.counter.x,y=d.counter.y,z=d.counter.z}}
    end
  end
  table.sort(list,function(a,b) return a.order<b.order end)
  return list
end)
function dealer(id)
  local base=OSDevtools.Dealerships[id];if not base then return nil end
  local o=dealerOverrides[id] or {}
  return {id=id,label=base.label,blip=base.blip,distance=base.distance,order=base.order or 99,colors=base.colors,
    counter=o.counter or base.counter,delivery=o.delivery or base.delivery,catalog=o.catalog or base.catalog,
    preview=o.preview or base.preview or o.delivery or base.delivery}
end
local function dealerList()
  local list={};for id in pairs(OSDevtools.Dealerships) do list[#list+1]=dealer(id) end
  table.sort(list,function(a,b) return a.order<b.order end)
  return list
end
local function publicDealers()
  local list={};for _,d in ipairs(dealerList()) do list[#list+1]={id=d.id,label=d.label,blip=d.blip,distance=d.distance,counter=d.counter} end
  return list
end
local function pushDealers(target) TriggerClientEvent('osdev:dealers',target or -1,publicDealers()) end
RegisterNetEvent('osdev:dealersRequest',function() pushDealers(source) end)
local dealerBusy={}
local function nearDealer(src,d)
  local pos=getCoords(src);local c=d.counter
  return pos and (pos.x-c.x)^2+(pos.y-c.y)^2+(pos.z-c.z)^2<=(d.distance+1.5)^2
end
RegisterNetEvent('osdev:dealer:open',function(id)
  local src=source;local d=type(id)=='string' and dealer(id)
  if not d or not exists(src) then return end
  if not nearDealer(src,d) then return out(src,'Acercate al mostrador.','warning') end
  TriggerClientEvent('osdev:dealer',src,{id=id,label=d.label,catalog=d.catalog,colors=d.colors,preview=d.preview})
end)
RegisterNetEvent('osdev:dealer:buy',function(id,model,color,account)
  local src=source;local d=type(id)=='string' and dealer(id)
  local alias=exists(src);if not d or not alias then return end
  local function result(ok,text) TriggerClientEvent('osdev:dealerResult',src,ok,text) end
  if dealerBusy[src] then return result(false,'Ya hay una compra en curso.') end
  if not nearDealer(src,d) then return result(false,'Acercate al mostrador.') end
  local entry;for _,e in ipairs(d.catalog) do if e.model==model then entry=e end end
  if not entry then return result(false,'Ese vehiculo no esta a la venta aqui.') end
  if account~='cash' and account~='bank' then return result(false,'Elige efectivo o tarjeta.') end
  local colorOk=false;color=math.tointeger(tonumber(color));for _,c in ipairs(d.colors) do if c==color then colorOk=true end end
  if not colorOk then color=d.colors[1] end
  if account=='bank' and GetResourceState('os_inventory')=='started' then
    local ok,has=pcall(function() return exports.os_inventory:PlayerHasItem(src,'bank_card') end)
    if not ok or has~=true then return result(false,'Para pagar con tarjeta necesitas tu tarjeta bancaria.') end
  end
  if not vehicles.onesync() then return result(false,'El servidor no puede crear vehiculos ahora mismo.') end
  dealerBusy[src]=true
  vehicles.inspect(src,{entry.model},function(types)
    dealerBusy[src]=nil
    local vtype=types and types[entry.model]
    if not vtype then return result(false,'Ese modelo no esta disponible.') end
    local point=d.delivery;local vid,plate
    local ok,err=core.change(src,('concesionario %s %s %s %d'):format(id,alias,entry.model,entry.price),function(data)
      local c=data.characters[alias]
      if (tonumber(c[account]) or 0)<entry.price then return false,account=='cash' and 'No llevas suficiente efectivo.' or 'No tienes saldo suficiente en el banco.' end
      c[account]=c[account]-entry.price
      vid=data.nextVehicle;data.nextVehicle=vid+1;plate=randomPlate(data)
      data.vehicles[tostring(vid)]={id=vid,model=entry.model,primary=color,secondary=color,fixed=true,owner=alias,plate=plate,
        position={x=point.x,y=point.y,z=point.z,h=point.h or 0,bucket=0},vtype=vtype}
      return true
    end)
    if not ok then return result(false,err or 'No se pudo completar la compra.') end
    giveKeyItem('vehicles',vid,alias)
    local entity=vehicles.spawn(vid,state.vehicles[tostring(vid)],state.vehicles[tostring(vid)].position)
    result(true,('Comprado %s por $%d. Matricula %s: lo tienes en la entrega con su llave.'):format(entry.label,entry.price,plate))
    if not entity then out(src,'El vehiculo esta registrado pero no ha aparecido: /recuperarvehiculo '..vid..' (admin).','warning') end
    pushHud(src)
  end)
end)
AddEventHandler('playerDropped',function() dealerBusy[source]=nil end)

-- Administracion: /concesionarios abre el panel (precios, modelos y puntos de cada concesionario).
local function saveDealer(id,d)
  local o=dealerOverrides[id] or {}
  dealerOverrides[id]={counter=d.counter,delivery=d.delivery,catalog=d.catalog,preview=d.previewSet or o.preview}
  SaveResourceFile(RESOURCE,'data/dealerships.json',json.encode(dealerOverrides),-1)
  pushDealers()
end
local function adminDealers(src,message,kind) TriggerClientEvent('osdev:dealerAdmin',src,{dealers=dealerList()},message,kind) end
RegisterCommand('concesionarios',function(src)
  if not needAdmin(src,'osdev.assets.dealers') then return end
  adminDealers(src)
end,false)
RegisterNetEvent('osdev:dealer:admin',function(op,id,a,b,c)
  local src=source
  if not admin(src,'osdev.assets.dealers') then return end
  local d=type(id)=='string' and dealer(id);if not d then return end
  local catalog={};for _,e in ipairs(d.catalog) do catalog[#catalog+1]={model=e.model,label=e.label,price=e.price} end
  d.catalog=catalog
  local function find(model) for i,e in ipairs(catalog) do if e.model==model then return i,e end end end
  if op=='price' then
    local i,e=find(a);local price=math.tointeger(tonumber(b))
    if not e or not price or price<0 or price>100000000 then return adminDealers(src,'Precio no valido.','error') end
    e.price=price
  elseif op=='add' then
    local model=type(a)=='string' and a:lower() or '';local label=type(b)=='string' and b:gsub('[%c<>]',''):sub(1,48) or '';local price=math.tointeger(tonumber(c))
    if not model:match('^[%w_]+$') or #model>32 or label=='' or not price or price<0 then return adminDealers(src,'Modelo, nombre o precio no validos.','error') end
    if find(model) then return adminDealers(src,'Ese modelo ya esta en el catalogo.','warning') end
    catalog[#catalog+1]={model=model,label=label,price=price}
  elseif op=='remove' then
    local i=find(a);if not i then return end
    table.remove(catalog,i)
  elseif op=='counter' or op=='delivery' or op=='preview' then
    local pos=getCoords(src);if not pos then return end
    if op=='counter' then d.counter={x=pos.x,y=pos.y,z=pos.z}
    elseif op=='delivery' then d.delivery={x=pos.x,y=pos.y,z=pos.z,h=pos.h or 0}
    else d.previewSet={x=pos.x,y=pos.y,z=pos.z,h=pos.h or 0} end
  else return end
  saveDealer(id,d)
  adminDealers(src,'Guardado.','success')
end)


-- Sistema de heridos (os_life): reanimar en el sitio o despertar en el hospital. Solo os_life.
exports('ReviveCharacter',function(src)
  if GetInvokingResource()~='os_life' then return false,'resource_not_authorized' end
  return core.revive(src)
end)
exports('RespawnAtHospital',function(src)
  if GetInvokingResource()~='os_life' then return false,'resource_not_authorized' end
  local alias=core.ensure(src);local c=alias and state.characters[alias]
  if not c or c.life~='dead' then return false,'not_dead' end
  return core.requestSpawn(src,'death')
end)


-- Trabajos publicos (config/jobs.lua) -------------------------------------------------------------------------------
-- Policia, sheriff, FIB, bomberos y EMS no son negocios: rangos fijos, sueldo del ayuntamiento por hora de servicio y
-- puntos de servicio en sus sedes. Los mandos (rango >= boss) gestionan la plantilla con /trabajo.
-- Archivos sueltos de data/ (puntos de trabajo, armarios, conjuntos). Antes de escribir se guarda una copia
-- (.bak) del ultimo contenido valido y despues se relee para confirmar. Si el archivo esta danado al arrancar se
-- usa la copia; si tampoco sirve, ese archivo NO se vuelve a escribir (no se pisan los datos) hasta revisarlo.
local sideBlocked={}
local function sideDecode(raw) if raw==nil then return nil end;local ok,data=pcall(json.decode,raw);return ok and type(data)=='table' and data or false end
local function sideLoad(file)
  local path='data/'..file
  local data=sideDecode(LoadResourceFile(RESOURCE,path))
  if data then return data end
  if data==nil then -- no existe: se empieza vacio
    local backup=sideDecode(LoadResourceFile(RESOURCE,path..'.bak'))
    return backup or {}
  end
  local backup=sideDecode(LoadResourceFile(RESOURCE,path..'.bak'))
  if backup then print(('^3[os_devtools] %s estaba danado: se usa la copia %s.bak.^7'):format(path,path));return backup end
  sideBlocked[file]=true
  print(('^1[os_devtools] %s esta danado y no hay copia valida: no se guardaran cambios en el hasta revisarlo.^7'):format(path))
  return {}
end
local function sideSave(file,data)
  local path='data/'..file
  if sideBlocked[file] then print(('^1[os_devtools] %s bloqueado (archivo danado): cambio no guardado.^7'):format(path));return false end
  local encoded=json.encode(data)
  local previous=LoadResourceFile(RESOURCE,path)
  if previous and sideDecode(previous) then SaveResourceFile(RESOURCE,path..'.bak',previous,-1) end
  SaveResourceFile(RESOURCE,path,encoded,-1)
  if LoadResourceFile(RESOURCE,path)~=encoded then print(('^1[os_devtools] No se pudo confirmar la escritura de %s.^7'):format(path));return false end
  return true
end
local extraPoints=sideLoad('job_points.json')
function OSDevtools.JobPoints(job)
  local list={}
  for _,p in ipairs((OSDevtools.PublicJobs[job] or {}).duty or {}) do list[#list+1]=p end
  for _,p in ipairs(extraPoints[job] or {}) do list[#list+1]=p end
  return list
end
OSDevtools.JobView,OSDevtools.JobInvites={},{}
local function rankIndexOf(job,rank) for i,r in ipairs(job.ranks) do if r==rank then return i end end end
local function jobOf(src)
  local alias=characterFor(src);local c=alias and state.characters[alias];local job=c and c.job and OSDevtools.PublicJobs[c.job]
  return alias,c,job
end
local function isBoss(c,job) return job and (rankIndexOf(job,c.rank) or 0)>=job.boss end
local function jobView(src)
  local alias,c,job=jobOf(src)
  local staff={}
  for who,ch in pairs(state.characters) do if ch.job==c.job then staff[#staff+1]={alias=who,rank=ch.rank} end end
  table.sort(staff,function(a,b) return (rankIndexOf(job,a.rank) or 0)>(rankIndexOf(job,b.rank) or 0) or ((rankIndexOf(job,a.rank) or 0)==(rankIndexOf(job,b.rank) or 0) and a.alias<b.alias) end)
  local salaries={};for i,r in ipairs(job.ranks) do salaries[r]=job.salaries[i] end
  local players={}
  for _,p in ipairs(nearbyPlayers(src)) do players[#players+1]=p end
  return {mode='job',businesses={{id='job:'..c.job,name=job.label,job=c.job,ranks=job.ranks,staff=staff,salaries=salaries,public=true,boss=isBoss(c,job),myRank=c.rank}},
    players=players,minRanks=0,maxRanks=#job.ranks,payMinutes=B.PayMinutes}
end
local function sendJob(src,message,kind) TriggerClientEvent('osdev:business:data',src,jobView(src),message,kind) end
RegisterCommand('trabajo',function(src)
  local alias,c,job=jobOf(src);if not alias then return end
  if not job then return out(src,'No tienes un trabajo publico (policia, sheriff, FIB, bomberos o EMS).','warning') end
  OSDevtools.JobView[src]=true
  TriggerClientEvent('osdev:business:open',src)
  sendJob(src)
end,false)
RegisterNetEvent('osdev:business:refresh',function() local src=source;if OSDevtools.JobView[src] then local _,_,job=jobOf(src);if job then sendJob(src) end end end)
RegisterNetEvent('osdev:business:invite',function(id,target,rank)
  local src=source;if type(id)~='string' or not id:match('^job:') then return end
  local alias,c,job=jobOf(src);target=tonumber(target)
  if not job or id~='job:'..c.job then return end
  if not isBoss(c,job) then return sendJob(src,'Solo los mandos pueden contratar.','error') end
  local index=rankIndexOf(job,rank)
  if not index or index>=rankIndexOf(job,c.rank) then return sendJob(src,'Solo puedes contratar en rangos por debajo del tuyo.','error') end
  local near=false;for _,p in ipairs(nearbyPlayers(src)) do if p.id==target then near=true end end
  if not near then return sendJob(src,'Ese jugador no esta cerca.','error') end
  local who=characterFor(target);if not who then return sendJob(src,'Jugador no valido.','error') end
  if state.characters[who].job==c.job then return sendJob(src,'Ya trabaja aqui.','warning') end
  OSDevtools.JobInvites[target]={job=c.job,rank=rank,from=src,untilAt=os.time()+B.InviteSeconds}
  TriggerClientEvent('osdev:business:invited',target,{business=job.label,rank=rank,from=alias,seconds=B.InviteSeconds})
  sendJob(src,'Oferta enviada a '..who..'.','success')
end)
RegisterNetEvent('osdev:business:answer',function(accept)
  local src=source;local invite=OSDevtools.JobInvites[src];OSDevtools.JobInvites[src]=nil
  if not invite then return end
  if invite.untilAt<os.time() then return out(src,'La oferta ha caducado.','warning') end
  local who=characterFor(src);local job=OSDevtools.PublicJobs[invite.job]
  if not accept then if GetPlayerName(invite.from) then sendJob(invite.from,who..' ha rechazado la oferta.','warning') end;return out(src,'Has rechazado la oferta.','info') end
  if action(src,'contratado '..invite.job..' '..who,function(d) local ch=d.characters[who];ch.job=invite.job;ch.rank=invite.rank;ch.duty=false;return true end) then
    out(src,('Ahora trabajas en %s como %s. Ficha en tu sede para entrar de servicio.'):format(job.label,invite.rank),'success')
    if OSDevtools.PushDutyPoints then OSDevtools.PushDutyPoints(src) end
    if GetPlayerName(invite.from) then sendJob(invite.from,who..' se ha incorporado.','success') end
  end
end)
RegisterNetEvent('osdev:business:staff',function(id,who,op,rank)
  local src=source;if type(id)~='string' or not id:match('^job:') or type(who)~='string' then return end
  local alias,c,job=jobOf(src)
  if not job or id~='job:'..c.job then return end
  local target=state.characters[who]
  if not isBoss(c,job) or not target or target.job~=c.job or who==alias then return sendJob(src,'No puedes cambiar a esa persona.','error') end
  if (rankIndexOf(job,target.rank) or 0)>=rankIndexOf(job,c.rank) then return sendJob(src,'Solo puedes gestionar rangos por debajo del tuyo.','error') end
  local ok,err=core.change(src,'trabajo plantilla '..c.job..' '..who,function(d)
    local t=d.characters[who]
    if op=='rank' then local i=rankIndexOf(job,rank);if not i or i>=rankIndexOf(job,c.rank) then return false,'Rango no valido.' end;t.rank=rank
    elseif op=='fire' then t.job='unemployed';t.rank='-';t.duty=false
    else return false,'Operacion no valida.' end
    return true
  end)
  sendJob(src,ok and 'Plantilla actualizada.' or err,ok and 'success' or 'error')
end)
RegisterNetEvent('osdev:business:duty',function(id)
  local src=source;if type(id)~='string' then return end
  local jobName,index=id:match('^job:([%w_]+):(%d+)$');if not jobName then return end
  local alias,c,job=jobOf(src)
  if not job or c.job~=jobName then return out(src,'Este no es tu trabajo.','error') end
  local p=OSDevtools.JobPoints(jobName)[tonumber(index)];local pos=getCoords(src)
  if not p or not pos or (pos.x-p.x)^2+(pos.y-p.y)^2+(pos.z-p.z)^2>9 then return out(src,'Acercate al punto de servicio.','warning') end
  local entering=not c.duty
  if action(src,'servicio publico '..jobName..' '..alias..' '..tostring(entering),function(d) d.characters[alias].duty=entering;return true end) then
    out(src,entering and ('De servicio en %s.'):format(job.label) or ('Fuera de servicio en %s.'):format(job.label),entering and 'success' or 'info')
    if OSDevtools.PushDutyPoints then OSDevtools.PushDutyPoints(src) end
    pushHud(src)
  end
end)
-- Admin: otro punto de servicio para un trabajo publico en tu posicion (data/job_points.json).
RegisterCommand('puntotrabajo',function(src,args)
  if not needAdmin(src,'osdev.jobs') then return end
  local jobName=args[1] and args[1]:lower();local job=jobName and OSDevtools.PublicJobs[jobName]
  if not job then local names={};for n in pairs(OSDevtools.PublicJobs) do names[#names+1]=n end;table.sort(names);return out(src,'Uso: /puntotrabajo <'..table.concat(names,'|')..'> [nombre]') end
  local pos=getCoords(src);if not pos then return end
  extraPoints[jobName]=extraPoints[jobName] or {}
  local label=table.concat(args,' ',2);if label=='' then label=job.label end
  extraPoints[jobName][#extraPoints[jobName]+1]={x=pos.x,y=pos.y,z=pos.z,label=label:sub(1,40)}
  sideSave('job_points.json',extraPoints)
  out(src,'Punto de servicio de '..job.label..' anadido aqui.','success')
  for _,p in ipairs(GetPlayers()) do if OSDevtools.PushDutyPoints then OSDevtools.PushDutyPoints(tonumber(p)) end end
end,false)
AddEventHandler('playerDropped',function() OSDevtools.JobView[source]=nil;OSDevtools.JobInvites[source]=nil end)

-- Armarios y conjuntos de ropa ---------------------------------------------------------------------------------
-- Armarios: puntos dentro de propiedades (/armario <idPropiedad> donde estas; /armario borrar quita el cercano). Junto
-- a uno, E abre el armario si llevas la llave de esa propiedad (o tienes osdev.assets.properties). En el armario se
-- cambia la ropa (disenador en modo ropa) y se guardan conjuntos por personaje (hasta MAX_OUTFITS).
local MAX_OUTFITS, MAX_WARDROBES, WARDROBE_REACH = 10, 200, 3.0
local wardrobes, outfits = sideLoad('wardrobes.json'), sideLoad('outfits.json') -- id -> punto; alias -> lista
local function saveWardrobes() return sideSave('wardrobes.json',wardrobes) end
local function saveOutfits() return sideSave('outfits.json',outfits) end
-- Guardar / borrar conjuntos escribe a disco: como mucho uno por segundo y jugador.
local outfitAt={}
local function outfitThrottled(src) local now=GetGameTimer();if outfitAt[src] and now-outfitAt[src]<1000 then return true end;outfitAt[src]=now;return false end
AddEventHandler('playerDropped',function() outfitAt[source]=nil end)
local function wardrobeList()
  local list={};for id,w in pairs(wardrobes) do list[#list+1]={id=id,x=w.x,y=w.y,z=w.z,bucket=w.bucket} end
  table.sort(list,function(a,b) return a.id<b.id end);return list
end
local function pushWardrobes(target) TriggerClientEvent('osdev:wardrobes',target or -1,wardrobeList()) end
RegisterNetEvent('osdev:wardrobes:request',function() pushWardrobes(source) end)

RegisterCommand('armario',function(src,args)
  if src==0 then return out(src,'Usalo desde el juego: el armario se pone donde estas.') end
  if not needAdmin(src,'osdev.assets.properties') then return end
  local pos=getCoords(src);if not pos then return out(src,'Posicion no disponible (bucket no permitido).','error') end
  if args[1]=='borrar' then
    local best,dist
    for id,w in pairs(wardrobes) do
      local d=math.sqrt((w.x-pos.x)^2+(w.y-pos.y)^2+(w.z-pos.z)^2)
      if w.bucket==pos.bucket and d<=WARDROBE_REACH and (not dist or d<dist) then best,dist=id,d end
    end
    if not best then return out(src,'No hay ningun armario a menos de 3 m.','warning') end
    local property=wardrobes[best].property;wardrobes[best]=nil;saveWardrobes();pushWardrobes()
    return out(src,('Armario de la propiedad #%s borrado.'):format(tostring(property)),'success')
  end
  local id=positive(args[1])
  if not id or not state.properties[tostring(id)] then return out(src,'Uso: /armario <idPropiedad> (donde estas) | /armario borrar (el mas cercano)') end
  local count=0;for _ in pairs(wardrobes) do count=count+1 end
  if count>=MAX_WARDROBES then return out(src,'Demasiados armarios.','error') end
  local key;local n=count+1;repeat key='w'..n;n=n+1 until not wardrobes[key]
  wardrobes[key]={property=id,x=math.floor(pos.x*100+0.5)/100,y=math.floor(pos.y*100+0.5)/100,z=math.floor(pos.z*100+0.5)/100,bucket=pos.bucket}
  saveWardrobes();pushWardrobes()
  out(src,('Armario anadido a la propiedad #%d aqui. Quien tenga su llave lo abre con E.'):format(id),'success')
end,false)

-- Conjunto: { name, sex, clothes = { clave = { d, t } }, props = { clave = { d, t } } } (claves del disenador).
local OUTFIT_CLOTHES={top=true,undershirt=true,arms=true,legs=true,shoes=true,mask=true,bag=true,accessory=true}
local OUTFIT_PROPS={hat=true,glasses=true,watch=true,bracelet=true}
local function cleanPart(input,keys,minimum)
  local result={}
  for key in pairs(keys) do
    local v=type(input)=='table' and input[key]
    local d=type(v)=='table' and math.tointeger(tonumber(v.d)) or nil
    local t=type(v)=='table' and math.tointeger(tonumber(v.t)) or nil
    if d and t and d>=minimum and d<=4095 and t>=0 and t<=255 then result[key]={d=d,t=t} end
  end
  return result
end
local function outfitsOf(alias) local list=outfits[alias];return type(list)=='table' and list or {} end
local function sendOutfits(src,alias) TriggerClientEvent('osdev:outfits:list',src,outfitsOf(alias)) end
RegisterNetEvent('osdev:wardrobe:use',function(id)
  local src=source;local alias=characterFor(src)
  local w=type(id)=='string' and wardrobes[id]
  if not alias or not w then return end
  local pos=getCoords(src)
  if not pos or pos.bucket~=w.bucket or math.sqrt((w.x-pos.x)^2+(w.y-pos.y)^2+(w.z-pos.z)^2)>WARDROBE_REACH then return out(src,'Acercate al armario.','warning') end
  if not holdsKey(src,'properties',w.property) and not admin(src,'osdev.assets.properties') then return out(src,'Necesitas la llave de esta propiedad para usar su armario.','error') end
  TriggerClientEvent('osdev:wardrobe:open',src,outfitsOf(alias))
end)
RegisterNetEvent('osdev:outfits:save',function(data)
  local src=source;local alias=characterFor(src);if not alias or type(data)~='table' then return end
  if outfitThrottled(src) then return out(src,'Espera un momento antes de guardar otro conjunto.','warning') end
  local name=type(data.name)=='string' and data.name:gsub('[%c<>]',''):gsub('^%s+',''):gsub('%s+$',''):sub(1,32) or ''
  if name=='' then return out(src,'Pon un nombre al conjunto.','warning') end
  local list=outfitsOf(alias)
  local outfit={name=name,sex=data.sex=='female' and 'female' or 'male',clothes=cleanPart(data.clothes,OUTFIT_CLOTHES,0),props=cleanPart(data.props,OUTFIT_PROPS,-1)}
  local replaced=false
  for i,o in ipairs(list) do if o.name==name then list[i]=outfit;replaced=true end end
  if not replaced then
    if #list>=MAX_OUTFITS then return out(src,('Ya tienes %d conjuntos: borra alguno.'):format(MAX_OUTFITS),'warning') end
    list[#list+1]=outfit
  end
  outfits[alias]=list
  if not saveOutfits() then return out(src,'No se pudo guardar el conjunto. Avisa a un administrador.','error') end
  sendOutfits(src,alias)
  out(src,(replaced and 'Conjunto "%s" actualizado.' or 'Conjunto "%s" guardado.'):format(name),'success')
end)
RegisterNetEvent('osdev:outfits:delete',function(index)
  local src=source;local alias=characterFor(src);index=math.tointeger(tonumber(index))
  if not alias or outfitThrottled(src) then return end
  local list=outfitsOf(alias)
  if not index or not list[index] then return end
  local name=list[index].name;table.remove(list,index);outfits[alias]=list
  if not saveOutfits() then return out(src,'No se pudo borrar el conjunto. Avisa a un administrador.','error') end
  sendOutfits(src,alias)
  out(src,('Conjunto "%s" borrado.'):format(name),'info')
end)
