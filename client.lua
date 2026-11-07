local function msg(text)
  TriggerEvent('chat:addMessage',{color={90,205,135},args={'OS DEV',text}})
end
RegisterNetEvent('osdev:msg',function(text) msg(text) end)
RegisterNetEvent('osdev:own',function(vehicles,businesses,properties,alias,character)
  msg(('Mis bienes · %s | Dinero en mano: $%d | Banco: $%d'):format(alias,character.cash or 0,character.bank or 0))
  for _,category in ipairs({{'Vehiculos',vehicles},{'Negocios',businesses},{'Propiedades',properties}}) do
    local rows={}
    for id,item in pairs(category[2]) do
      if item.owner==alias then rows[#rows+1]=('#%s %s'):format(id,item.name or item.model or item.type or '') end
    end
    table.sort(rows)
    msg(category[1]..': '..(#rows>0 and table.concat(rows,', ') or 'ninguno'))
  end
end)
local function applyLivery(vehicle,index,kind)
  SetVehicleModKit(vehicle,0)
  if kind=='native' then SetVehicleLivery(vehicle,index)
  elseif kind=='mod48' then SetVehicleMod(vehicle,48,index,false) end
end
RegisterNetEvent('osdev:spawnVehicle',function(data)
  local model=GetHashKey(data.model)
  if not IsModelInCdimage(model) or not IsModelAVehicle(model) then
    return TriggerServerEvent('osdev:spawned',data.nonce,0,'modelo invalido')
  end
  RequestModel(model)
  local deadline=GetGameTimer()+7500
  while not HasModelLoaded(model) and GetGameTimer()<deadline do Wait(0) end
  if not HasModelLoaded(model) then return TriggerServerEvent('osdev:spawned',data.nonce,0,'timeout modelo') end
  local p=data.position
  local vehicle=CreateVehicle(model,p.x+3.0,p.y+2.0,p.z+0.2,p.h,true,true)
  SetModelAsNoLongerNeeded(model)
  if vehicle==0 or not DoesEntityExist(vehicle) then return TriggerServerEvent('osdev:spawned',data.nonce,0,'CreateVehicle fallo; revisar entity lockdown') end
  SetVehicleColours(vehicle,data.primary,data.secondary)
  SetVehicleNumberPlateText(vehicle,data.plate)
  if data.livery~=nil then applyLivery(vehicle,data.livery,data.liveryType) end
  SetVehicleOnGroundProperly(vehicle)
  local deadlineNet=GetGameTimer()+3000
  while not NetworkGetEntityIsNetworked(vehicle) and GetGameTimer()<deadlineNet do Wait(0) end
  local netId=NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or 0
  TriggerServerEvent('osdev:spawned',data.nonce,netId,netId==0 and 'network id unavailable' or nil)
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
local hudEnabled = GetResourceKvpString('osdev_hud_visible') ~= 'false'
local hud = {playerId=nil,cash=nil,character=nil}
local function renderHud()
  SendNUIMessage({action='hud',visible=hudEnabled and not IsPauseMenuActive(),playerId=hud.playerId,cash=hud.cash,character=hud.character})
end
RegisterNetEvent('osdev:hudData',function(data)
  if type(data)~='table' then return end
  hud.playerId=tonumber(data.playerId) or GetPlayerServerId(PlayerId())
  hud.cash=tonumber(data.cash)
  hud.character=data.character
  renderHud()
end)
RegisterCommand('hud',function()
  hudEnabled=not hudEnabled
  SetResourceKvp('osdev_hud_visible',tostring(hudEnabled))
  renderHud()
  msg(hudEnabled and 'HUD activado.' or 'HUD oculto.')
end,false)
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
