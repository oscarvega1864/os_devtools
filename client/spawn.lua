local mode=OSDevtools.SpawnConfig.Mode
local frozen=false
local function release()
    if frozen then FreezeEntityPosition(PlayerPedId(),false);frozen=false end
    DoScreenFadeIn(500)
end
local controller=OSDevtools.SpawnClient.new({
    schedule=SetTimeout,
    ack=function(token) TriggerServerEvent('osdev:characterSpawned',token) end,
    failed=function(token) TriggerServerEvent('osdev:spawnFailed',token) end,
    release=release,
    notify=function(text) TriggerEvent('chat:addMessage',{args={'OS DEV',text}}) end,
    spawn=function(point,callback,isCurrent)
        if GetResourceState('spawnmanager')~='started' then callback(false);return end
        exports.spawnmanager:setAutoSpawn(false)
        exports.spawnmanager:spawnPlayer({x=point.x,y=point.y,z=point.z,heading=point.h,skipFade=false},function()
            if not isCurrent() then return end
            CreateThread(function()
                if not isCurrent() then return end
                local ped=PlayerPedId();FreezeEntityPosition(ped,true);frozen=true
                RequestCollisionAtCoord(point.x,point.y,point.z)
                local deadline=GetGameTimer()+5000
                while isCurrent() and not HasCollisionLoadedAroundEntity(ped) and GetGameTimer()<deadline do Wait(50) end
                if not isCurrent() then return end
                ClearPedBloodDamage(ped)
                callback(HasCollisionLoadedAroundEntity(ped))
            end)
        end)
    end
})
-- os_devtools es el unico dueno de la aparicion: si otro recurso (p. ej. basic-gamemode al
-- iniciar un mapa) reactiva el autospawn y fuerza un respawn, spawnmanager llamara a este
-- callback en lugar de spawnPlayer() y no movera al personaje a un punto del mapa.
local function claimAutoSpawn()
    if mode~='spawnmanager' or GetResourceState('spawnmanager')~='started' then return end
    exports.spawnmanager:setAutoSpawnCallback(function() exports.spawnmanager:setAutoSpawn(false) end)
    exports.spawnmanager:setAutoSpawn(false)
end
claimAutoSpawn()
local function setup()
    if mode~='spawnmanager' or not NetworkIsSessionStarted() then return end
    if GetResourceState('spawnmanager')~='started' then
        TriggerEvent('chat:addMessage',{args={'OS DEV','Falta spawnmanager; iniciar antes de os_devtools o configurar Mode=external.'}})
        return
    end
    exports.spawnmanager:setAutoSpawn(false);TriggerServerEvent('osdev:requestCharacterSpawn')
end
RegisterNetEvent('osdev:spawnCharacter',function(context) if source==65535 and mode=='spawnmanager' then controller.receive(context) end end)
RegisterNetEvent('osdev:spawnAccepted',function(token) if source==65535 then controller.accepted(token) end end)
RegisterNetEvent('osdev:characterChanged',function() if source==65535 then TriggerServerEvent('osdev:requestHud') end end)
AddEventHandler('onClientResourceStart',function(name)
    if name=='spawnmanager' then claimAutoSpawn() end
    if name==GetCurrentResourceName() or name=='spawnmanager' then setup() end
end)
AddEventHandler('onClientResourceStop',function(name)
    if name=='spawnmanager' and mode=='spawnmanager' then controller.stop();return end
    if name~=GetCurrentResourceName() then return end
    controller.stop()
    if mode=='spawnmanager' and GetResourceState('spawnmanager')=='started' then
        -- Devuelve el comportamiento por defecto y no deja una referencia a funcion caducada.
        exports.spawnmanager:setAutoSpawnCallback(nil)
        exports.spawnmanager:setAutoSpawn(true)
    end
end)
CreateThread(function() while not NetworkIsSessionStarted() do Wait(250) end;setup() end)
CreateThread(function()
    local dead=false
    while true do
        Wait(1000)
        local current=IsEntityDead(PlayerPedId())
        if current and not dead then TriggerServerEvent('osdev:deathObserved') end
        dead=current
    end
end)
