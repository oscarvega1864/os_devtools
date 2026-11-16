-- Mensajes cortos: notificacion compacta si os_notify esta iniciado; si no, chat (sin dependencia).
local function chat(text) TriggerEvent('chat:addMessage',{color={90,205,135},args={'OS DEV',text}}) end
function OSDevtools.Notify(text,kind)
  if GetResourceState('os_notify')=='started' then exports.os_notify:Notify(text,kind or 'info') else chat(text) end
end
local function msg(text,kind) OSDevtools.Notify(text,kind or (text:find('^Uso') and 'warning') or 'info') end
RegisterNetEvent('osdev:msg',function(text,kind) if source==65535 and type(text)=='string' then msg(text,kind) end end)
-- Listados y consultas: siempre al chat, donde se pueden leer y desplazar.
RegisterNetEvent('osdev:list',function(text) if source==65535 and type(text)=='string' then chat(text) end end)
RegisterNetEvent('osdev:own',function(vehicles,businesses,properties,alias,character)
  chat(('Mis bienes · %s | Dinero en mano: $%d | Banco: $%d'):format(alias,character.cash or 0,character.bank or 0))
  for _,category in ipairs({{'Vehiculos',vehicles},{'Negocios',businesses},{'Propiedades',properties}}) do
    local rows={}
    for id,item in pairs(category[2]) do
      if item.owner==alias then rows[#rows+1]=('#%s %s'):format(id,item.name or item.model or item.type or '') end
    end
    table.sort(rows)
    chat(category[1]..': '..(#rows>0 and table.concat(rows,', ') or 'ninguno'))
  end
end)
local function applyLivery(vehicle,index,kind)
  SetVehicleModKit(vehicle,0)
  if kind=='native' then SetVehicleLivery(vehicle,index)
  elseif kind=='mod48' then SetVehicleMod(vehicle,48,index,false) end
end
-- El servidor crea los vehiculos (CREATE_VEHICLE_SERVER_SETTER) y necesita el tipo del modelo,
-- que solo el cliente puede consultar. Trenes no admitidos; remolques se tratan como automovil.
local function modelType(name)
  if type(name)~='string' or not name:match('^[%w_]+$') then return false end
  local model=GetHashKey(name)
  if not IsModelInCdimage(model) or not IsModelAVehicle(model) or IsThisModelATrain(model) then return false end
  if IsThisModelAHeli(model) then return 'heli' end
  if IsThisModelAPlane(model) then return 'plane' end
  if IsThisModelABoat(model) or IsThisModelAJetski(model) then return 'boat' end
  if IsThisModelABike(model) or IsThisModelABicycle(model) then return 'bike' end
  if GetVehicleClassFromName(model)==14 then return 'submarine' end -- clase 14 que no es barco
  return 'automobile'
end
RegisterNetEvent('osdev:inspectVehicleModels',function(nonce,models)
  if source~=65535 or type(models)~='table' then return end
  local result={}
  for _,name in ipairs(models) do if type(name)=='string' then result[name]=modelType(name) end end
  TriggerServerEvent('osdev:vehicleModelTypes',nonce,result)
end)
-- Aspecto de los vehiculos de Devtools: lo aplica solo quien controla la entidad, que lo sincroniza.
AddStateBagChangeHandler('osdev',nil,function(bagName,_,value)
  if type(value)~='table' then return end
  CreateThread(function()
    local vehicle,deadline=0,GetGameTimer()+5000
    while GetGameTimer()<deadline do
      vehicle=GetEntityFromStateBagName(bagName)
      if vehicle~=0 and DoesEntityExist(vehicle) then break end
      Wait(100)
    end
    if vehicle==0 or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) or NetworkGetEntityOwner(vehicle)~=PlayerId() then return end
    if type(value.plate)=='string' then SetVehicleNumberPlateText(vehicle,value.plate) end
    if tonumber(value.primary) and tonumber(value.secondary) then SetVehicleColours(vehicle,value.primary,value.secondary) end
    if tonumber(value.livery) then applyLivery(vehicle,value.livery,value.liveryType) end
  end)
end)
CreateThread(function()
  while not NetworkIsSessionStarted() do Wait(500) end
  TriggerServerEvent('osdev:vehiclesReady')
end)
local function currentVehicle()
  local ped=PlayerPedId()
  local veh=GetVehiclePedIsIn(ped,false)
  if veh==0 or not DoesEntityExist(veh) then msg('Debes estar dentro de un vehiculo.');return nil end
  if GetPedInVehicleSeat(veh,-1)~=ped then msg('Debes estar conduciendo el vehiculo.');return nil end
  return veh
end
RegisterNetEvent('osdev:doSetColor',function(args)
  local veh=currentVehicle();if not veh then return end
  local a=tonumber(args[1]);local b=tonumber(args[2] or args[1])
  if not a or a%1~=0 or a<0 or a>159 or not b or b%1~=0 or b<0 or b>159 then return msg('Uso: /setcolor <primario 0-159> [secundario 0-159]') end
  SetVehicleColours(veh,a,b)
  TriggerServerEvent('osdev:vehicleAppearance',GetVehicleNumberPlateText(veh):gsub('%s+$',''),a,b,nil,nil)
end)
RegisterNetEvent('osdev:doListLiveries',function()
  local veh=currentVehicle();if not veh then return end
  SetVehicleModKit(veh,0)
  local a=GetVehicleLiveryCount(veh)
  local b=GetNumVehicleMods(veh,48)
  msg(('Liveries: sistema nativo=%d | mod48=%d. Indices disponibles: 0 a cantidad-1.'):format(math.max(a,0),math.max(b,0)))
end)
-- /setcar: efectos que solo puede aplicar quien controla el vehiculo (el servidor elige a ese jugador).
local function controlOf(vehicle)
  local deadline=GetGameTimer()+1500
  while not NetworkHasControlOfEntity(vehicle) and GetGameTimer()<deadline do NetworkRequestControlOfEntity(vehicle);Wait(0) end
  return NetworkHasControlOfEntity(vehicle)
end
RegisterNetEvent('osdev:setcarEffect',function(netId,op,value)
  if source~=65535 or type(op)~='string' then return end
  local vehicle=NetworkDoesNetworkIdExist(netId or 0) and NetworkGetEntityFromNetworkId(netId) or 0
  if vehicle==0 or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then return end
  CreateThread(function()
    if not controlOf(vehicle) then return end
    if op=='repair' then
      SetVehicleFixed(vehicle);SetVehicleDeformationFixed(vehicle)
      SetVehicleEngineHealth(vehicle,1000.0);SetVehicleBodyHealth(vehicle,1000.0);SetVehiclePetrolTankHealth(vehicle,1000.0)
      SetVehicleDirtLevel(vehicle,0.0);SetVehicleUndriveable(vehicle,false)
      for wheel=0,7 do SetVehicleTyreFixed(vehicle,wheel) end
    elseif op=='fuel' and tonumber(value) then
      local level=math.max(0.0,math.min(100.0,tonumber(value)+0.0))
      local ok=GetResourceState('LegacyFuel')=='started' and pcall(function() exports.LegacyFuel:SetFuel(vehicle,level) end)
      if not ok then SetVehicleFuelLevel(vehicle,level) end
    elseif op=='livery' and type(value)=='table' and tonumber(value.index) then
      applyLivery(vehicle,tonumber(value.index),value.kind)
    end
  end)
end)
-- /setcar livery: comprueba que tipos de livery admite el modelo y devuelve el que corresponde.
RegisterNetEvent('osdev:setcarLiveryCheck',function(netId,index,kind)
  if source~=65535 then return end
  local vehicle=NetworkDoesNetworkIdExist(netId or 0) and NetworkGetEntityFromNetworkId(netId) or 0
  if vehicle==0 or not DoesEntityExist(vehicle) then return msg('Acercate al vehiculo: tiene que estar cargado para ver sus liveries.') end
  SetVehicleModKit(vehicle,0)
  local native,mods=GetVehicleLiveryCount(vehicle),GetNumVehicleMods(vehicle,48)
  if not kind then
    if native>0 and mods>0 then return msg('Este vehiculo admite dos tipos: /setcar livery '..index..' native|mod48 ...') end
    kind=native>0 and 'native' or (mods>0 and 'mod48' or nil)
  end
  if not kind then return msg('Este vehiculo no tiene liveries.') end
  local count=kind=='native' and native or mods
  if index>=count then return msg(('Livery fuera de rango: hay %d (0 a %d).'):format(count,count-1)) end
  TriggerServerEvent('osdev:setcarLivery',netId,index,kind)
end)
RegisterNetEvent('osdev:doSetLivery',function(args)
  local veh=currentVehicle();if not veh then return end
  local n=tonumber(args[1]);if not n or n%1~=0 or n<0 then return msg('Uso: /setlivery <indice> [native|mod48]') end
  SetVehicleModKit(veh,0)
  local native=math.max(GetVehicleLiveryCount(veh),0)
  local mods=math.max(GetNumVehicleMods(veh,48),0)
  local kind=args[2]
  if not kind then
    if native>0 and mods>0 then return msg('Este vehiculo soporta dos tipos. Usa /setlivery <indice> native|mod48') end
    kind=native>0 and 'native' or 'mod48'
  end
  local max=kind=='native' and native or kind=='mod48' and mods or 0
  if n>=max then return msg(('Indice inexistente para %s (cantidad %d).'):format(kind,max)) end
  applyLivery(veh,n,kind)
  TriggerServerEvent('osdev:vehicleAppearance',GetVehicleNumberPlateText(veh):gsub('%s+$',''),nil,nil,n,kind)
  msg(('Livery %s #%d aplicada.'):format(kind,n))
end)
RegisterNetEvent('osdev:requestCeder',function(target)
  local veh=currentVehicle();if not veh then return end
  local plate=GetVehicleNumberPlateText(veh):gsub('%s+$','')
  TriggerServerEvent('osdev:cederVehicle',target,plate)
end)


-- HUD de desarrollo: ID de sesion + efectivo del personaje activo.
-- `setr osdev_hud false` en server.cfg lo apaga para todos (p. ej. con Oxide HUD) y deja /hud libre.
-- Los datos (osdev:hudData) se siguen enviando: los usa el adaptador de o-link.
local hudAllowed = GetConvar('osdev_hud','true') ~= 'false'
local hudEnabled = hudAllowed and GetResourceKvpString('osdev_hud_visible') ~= 'false'
local hud = {playerId=nil,cash=nil,character=nil}
-- Otros recursos pueden pedir pantalla limpia (p. ej. la vista en directo de camaras de os_security).
local hudHiddenBy = {}
local function renderHud()
  SendNUIMessage({action='hud',visible=hudEnabled and not IsPauseMenuActive() and next(hudHiddenBy)==nil,playerId=hud.playerId,cash=hud.cash,character=hud.character})
end
AddEventHandler('os_security:cameraView',function(active)
  hudHiddenBy.camera = active==true or nil
  renderHud()
end)
RegisterNetEvent('osdev:hudData',function(data)
  if type(data)~='table' then return end
  hud.playerId=tonumber(data.playerId) or GetPlayerServerId(PlayerId())
  hud.cash=tonumber(data.cash)
  hud.character=data.character
  renderHud()
end)
if hudAllowed then
  RegisterCommand('hud',function()
    hudEnabled=not hudEnabled
    SetResourceKvp('osdev_hud_visible',tostring(hudEnabled))
    renderHud()
    msg(hudEnabled and 'HUD activado.' or 'HUD oculto.')
  end,false)
end
CreateThread(function()
  Wait(1500)
  local lastPause=nil
  local nextSync=0
  while true do
    local now=GetGameTimer()
    if now>=nextSync then
      TriggerServerEvent('osdev:requestHud')
      nextSync=now+15000
    end
    local paused=IsPauseMenuActive()
    if paused~=lastPause then lastPause=paused;renderHud() end
    Wait(500)
  end
end)
