local mode=OSDevtools.SpawnConfig.Mode
local frozen=false
local currentPlan=nil
local function release()
    if frozen then FreezeEntityPosition(PlayerPedId(),false);frozen=false end
    DoScreenFadeIn(500)
    -- El guardado automatico solo se reanuda cuando la aparicion termina.
    OSDevtools.Appearance.spawning=false
    if currentPlan then OSDevtools.Appearance.settled(currentPlan);currentPlan=nil end
    -- Armas del personaje (client/weapons.lua): se dan con la aparicion ya confirmada.
    if OSDevtools.Weapons then OSDevtools.Weapons.release() end
end
local controller=OSDevtools.SpawnClient.new({
    schedule=SetTimeout,
    ack=function(token) TriggerServerEvent('osdev:characterSpawned',token) end,
    failed=function(token) TriggerServerEvent('osdev:spawnFailed',token) end,
    release=release,
    notify=function(text) OSDevtools.Notify(text,'error') end,
    spawn=function(point,callback,isCurrent,context)
        if GetResourceState('spawnmanager')~='started' then callback(false);return end
        local appearance=OSDevtools.Appearance
        appearance.spawning=true
        if OSDevtools.Weapons then OSDevtools.Weapons.hold(context and context.weapons) end
        CreateThread(function()
            -- El modelo y la ropa se aplican con la pantalla en negro: spawnmanager
            -- retira el fundido antes de devolver el control.
            local plan=appearance.plan(context and context.appearance)
            DoScreenFadeOut(500)
            local fade=GetGameTimer()+1500
            while not IsScreenFadedOut() and GetGameTimer()<fade do Wait(0) end
            if not isCurrent() then return end
            if not appearance.setModel(plan) then plan={model=GetEntityModel(PlayerPedId()),data=nil,locked=true} end
            appearance.apply(PlayerPedId(),plan)
            if not isCurrent() then return end
            exports.spawnmanager:setAutoSpawn(false)
            exports.spawnmanager:spawnPlayer({x=point.x,y=point.y,z=point.z,heading=point.h,skipFade=false},function()
                if not isCurrent() then return end
                CreateThread(function()
                    if not isCurrent() then return end
                    local ped=PlayerPedId();FreezeEntityPosition(ped,true);frozen=true
                    -- La resurreccion puede recrear el ped: se reaplica sobre el ped definitivo.
                    appearance.apply(ped,plan)
                    RequestCollisionAtCoord(point.x,point.y,point.z)
                    local deadline=GetGameTimer()+5000
                    while isCurrent() and not HasCollisionLoadedAroundEntity(ped) and GetGameTimer()<deadline do Wait(50) end
                    if not isCurrent() then return end
                    ClearPedBloodDamage(ped)
                    currentPlan=plan
                    callback(HasCollisionLoadedAroundEntity(ped))
                end)
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
        OSDevtools.Notify('Falta spawnmanager; iniciar antes de os_devtools o configurar Mode=external.','error')
        return
    end
    -- El servidor decide: selector de personaje al entrar o aparicion directa (ya jugando / selector desactivado).
    exports.spawnmanager:setAutoSpawn(false);TriggerServerEvent('osdev:requestCharacterSelect')
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
