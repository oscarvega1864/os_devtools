-- Ajustes del mundo controlados por el servidor: /policianpc y /npcs.
-- Ninguno borra entidades ni afecta a jugadores, a policias jugadores o a las alertas de OS Security.

-- Policia NPC desactivada: sin nivel de busqueda ni envios policiales.
-- Despachos policiales/militares: 1 coche, 2 helicoptero, 4 SWAT, 6 a caballo, 7-10 peticiones,
-- controles y patrullas, 12-15 SWAT aereo, barco y ejercito (la tabla oficial numera 12-15 de
-- forma ambigua; se cubren todos). Nunca 3 bomberos, 5 ambulancia ni 11 bandas.
local POLICE_DISPATCH={1,2,4,6,7,8,9,10,12,13,14,15}
local world={npcPolice=true,ambientNpcs=true}

local function applyPolice(enabled)
    local player=PlayerId()
    for _,service in ipairs(POLICE_DISPATCH) do EnableDispatchService(service,enabled) end
    SetPoliceIgnorePlayer(player,not enabled)
    SetDispatchCopsForPlayer(player,enabled)
    SetMaxWantedLevel(enabled and 5 or 0)
    if not enabled then ClearPlayerWantedLevel(player) end
end
-- Peatones y trafico: los multiplicadores de densidad se aplican cada fotograma (bucle de abajo);
-- aqui solo los interruptores persistentes. Los NPC existentes no se borran: desaparecen al alejarse.
local function applyAmbient(enabled)
    SetGarbageTrucks(enabled)
    SetRandomBoats(enabled)
end

RegisterNetEvent('osdev:worldSettings',function(settings)
    if source~=65535 or type(settings)~='table' then return end
    if type(settings.npcPolice)=='boolean' and settings.npcPolice~=world.npcPolice then
        world.npcPolice=settings.npcPolice;applyPolice(world.npcPolice)
    end
    if type(settings.ambientNpcs)=='boolean' and settings.ambientNpcs~=world.ambientNpcs then
        world.ambientNpcs=settings.ambientNpcs;applyAmbient(world.ambientNpcs)
    end
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    TriggerServerEvent('osdev:requestWorldSettings')
    -- Otros scripts o la reaparicion pueden restablecer el nivel de busqueda: se mantiene cada segundo.
    while true do
        Wait(1000)
        if not world.npcPolice then
            local player=PlayerId()
            if GetPlayerWantedLevel(player)>0 then ClearPlayerWantedLevel(player) end
            SetMaxWantedLevel(0)
            SetPoliceIgnorePlayer(player,true)
        end
    end
end)

CreateThread(function()
    while true do
        if world.ambientNpcs then
            Wait(500)
        else
            SetPedDensityMultiplierThisFrame(0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0,0.0)
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
            Wait(0)
        end
    end
end)

AddEventHandler('onClientResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    if not world.npcPolice then applyPolice(true) end
    if not world.ambientNpcs then applyAmbient(true) end
end)
