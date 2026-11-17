-- Concesionarios: blips y mostradores (E) con la lista que manda el servidor (puede cambiarla un admin), catalogo de
-- compra y panel de administracion (/concesionarios). El servidor valida todo.
local open, adminOpen, dealers, blips = nil, false, {}, {}
local function rebuildBlips()
    for _, blip in ipairs(blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    blips = {}
    for _, d in ipairs(dealers) do
        local c = d.counter
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, d.blip.sprite); SetBlipColour(blip, d.blip.color); SetBlipScale(blip, d.blip.scale); SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(d.label); EndTextCommandSetBlipName(blip)
        blips[#blips + 1] = blip
    end
end
RegisterNetEvent('osdev:dealers', function(list)
    if source ~= 65535 or type(list) ~= 'table' then return end
    dealers = list
    rebuildBlips()
end)
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    Wait(4000)
    TriggerServerEvent('osdev:dealersRequest')
    while true do
        local wait = 1000
        local here = GetEntityCoords(PlayerPedId())
        for _, d in ipairs(dealers) do
            local c = d.counter
            local dist = #(here - vector3(c.x, c.y, c.z))
            if dist < 15.0 then
                wait = 0
                DrawMarker(36, c.x, c.y, c.z + 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.6, 0.6, 127, 201, 142, 170, true, true, 2, false, nil, nil, false)
                if dist < d.distance and not open and not IsNuiFocused() then
                    BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ ' .. d.label); EndTextCommandDisplayHelp(0, false, false, -1)
                    if IsControlJustPressed(0, 38) then TriggerServerEvent('osdev:dealer:open', d.id) end
                end
            end
        end
        Wait(wait)
    end
end)
-- Vista previa: el modelo elegido aparece (solo para ti, no se sincroniza) en el punto de vista previa del concesionario,
-- con el color marcado. El coche esta quieto y la camara la mueve el jugador: arrastrar en la zona libre de la
-- pantalla gira alrededor y sube o baja; la rueda acerca y aleja. El catalogo queda a la derecha.
local preview = { vehicle = nil, cam = nil, point = nil, model = nil, angle = 0.0, height = 0.0, zoom = 1.0, token = 0 }
local function clearPreview()
    preview.token = preview.token + 1
    if preview.vehicle and DoesEntityExist(preview.vehicle) then DeleteEntity(preview.vehicle) end
    preview.vehicle, preview.model = nil, nil
    if preview.cam then RenderScriptCams(false, true, 400, true, false); DestroyCam(preview.cam, false); preview.cam = nil end
    ClearFocus()
end
local function placeCamera()
    local v = preview.vehicle
    if not preview.cam or not v or not DoesEntityExist(v) then return end
    local minDim, maxDim = GetModelDimensions(GetEntityModel(v))
    local size = math.max(maxDim.x - minDim.x, maxDim.y - minDim.y)
    local dist = math.max(4.8, size * 1.2) * preview.zoom
    local c = GetEntityCoords(v)
    local a = math.rad(preview.angle)
    local cx, cy, cz = c.x + math.cos(a) * dist, c.y + math.sin(a) * dist, c.z + 0.9 + size * 0.06 + preview.height
    -- Se apunta un poco a la derecha del coche para que quede a la izquierda de la pantalla (el catalogo va a la derecha).
    local dx, dy = c.x - cx, c.y - cy
    local len = math.sqrt(dx * dx + dy * dy); dx, dy = dx / len, dy / len
    local shift = dist * 0.3
    SetCamCoord(preview.cam, cx, cy, cz)
    PointCamAtCoord(preview.cam, c.x + dy * shift, c.y - dx * shift, c.z + 0.2)
end
local function showPreview(model, color)
    local point = preview.point
    if not point or type(model) ~= 'string' or not model:match('^[%w_]+$') then return end
    preview.token = preview.token + 1
    local token = preview.token
    CreateThread(function()
        local hash = GetHashKey(model)
        if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then SendNUIMessage({ action = 'dealerPreview', ok = false }); return end
        if preview.model ~= model or not (preview.vehicle and DoesEntityExist(preview.vehicle)) then
            SetFocusPosAndVel(point.x, point.y, point.z, 0.0, 0.0, 0.0)
            RequestModel(hash)
            local deadline = GetGameTimer() + 8000
            while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
            if token ~= preview.token or not open or not HasModelLoaded(hash) then return end
            if preview.vehicle and DoesEntityExist(preview.vehicle) then DeleteEntity(preview.vehicle) end
            local v = CreateVehicle(hash, point.x, point.y, point.z, point.h or 0.0, false, false)
            SetModelAsNoLongerNeeded(hash)
            SetVehicleOnGroundProperly(v)
            FreezeEntityPosition(v, true)
            SetEntityInvincible(v, true)
            SetVehicleDoorsLocked(v, 2)
            SetVehicleDirtLevel(v, 0.0)
            SetVehicleNumberPlateText(v, 'VENTA')
            preview.vehicle, preview.model = v, model
        end
        if color then SetVehicleColours(preview.vehicle, color, color) end
        if not preview.cam then
            preview.angle, preview.height, preview.zoom = (point.h or 0.0) + 60.0, 0.0, 1.0
            preview.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
            SetCamFov(preview.cam, 45.0)
            placeCamera()
            RenderScriptCams(true, true, 600, true, false)
            CreateThread(function()
                while preview.cam do
                    placeCamera() -- sin giro automatico: solo se mueve cuando el jugador arrastra
                    HideHudAndRadarThisFrame()
                    Wait(0)
                end
            end)
        end
    end)
end
-- Camara de la vista previa movida por el jugador desde la NUI (arrastrar y rueda).
RegisterNUICallback('dealerCamera', function(d, cb)
    cb({})
    if not preview.cam or type(d) ~= 'table' then return end
    local dx, dy, wheel = tonumber(d.dx) or 0, tonumber(d.dy) or 0, tonumber(d.wheel) or 0
    if dx ~= dx or dy ~= dy or wheel ~= wheel then return end -- NaN
    preview.angle = (preview.angle - math.max(-200, math.min(200, dx)) * 0.35) % 360.0
    preview.height = math.max(-0.6, math.min(3.5, preview.height + math.max(-200, math.min(200, dy)) * 0.015))
    if wheel ~= 0 then preview.zoom = math.max(0.55, math.min(1.8, preview.zoom + (wheel > 0 and 0.08 or -0.08))) end
    placeCamera()
end)
RegisterNUICallback('dealerPreview', function(d, cb)
    cb({})
    if open and type(d) == 'table' then showPreview(d.model, math.tointeger(tonumber(d.color))) end
end)
AddEventHandler('onResourceStop', function(name) if name == GetCurrentResourceName() then clearPreview() end end)

RegisterNetEvent('osdev:dealer', function(data)
    if source ~= 65535 or type(data) ~= 'table' then return end
    open = data.id
    preview.point = type(data.preview) == 'table' and data.preview or nil
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'dealer', data = data })
end)
RegisterNetEvent('osdev:dealerResult', function(ok, text)
    if source ~= 65535 then return end
    SendNUIMessage({ action = 'dealerResult', ok = ok == true, text = text })
end)
RegisterNUICallback('dealerBuy', function(d, cb)
    cb({})
    if not open or type(d) ~= 'table' then return end
    local id = open
    CreateThread(function()
        -- Con tarjeta: pasarla por el lector de os_inventory (se suelta el foco mientras tanto).
        if d.account == 'bank' and GetResourceState('os_inventory') == 'started' then
            SetNuiFocus(false, false)
            local ok, swiped = pcall(function() return exports.os_inventory:CardSwipe({ card = 'bank', title = 'Pago con tarjeta', detail = d.price and ('$' .. tostring(d.price)) or nil }) end)
            if open then SetNuiFocus(true, true) end
            if not ok or swiped ~= true then SendNUIMessage({ action = 'dealerResult', ok = false, text = 'Pago cancelado.' }); return end
        end
        TriggerServerEvent('osdev:dealer:buy', id, d.model, d.color, d.account)
    end)
end)
RegisterNUICallback('dealerClose', function(_, cb) open = nil; adminOpen = false; clearPreview(); SetNuiFocus(false, false); cb({}) end)
-- Panel de administracion.
RegisterNetEvent('osdev:dealerAdmin', function(data, message, kind)
    if source ~= 65535 or type(data) ~= 'table' then return end
    adminOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'dealerAdmin', data = data, message = message, kind = kind })
end)
RegisterNUICallback('dealerAdmin', function(d, cb)
    cb({})
    if not adminOpen or type(d) ~= 'table' then return end
    if d.op == 'counter' or d.op == 'delivery' or d.op == 'preview' then SetNuiFocus(false, false) end -- el punto es donde estas
    TriggerServerEvent('osdev:dealer:admin', d.op, d.id, d.a, d.b, d.c)
end)
-- GPS al concesionario mas cercano (lo usa el menu de inicio de os_hud).
RegisterCommand('gpsconcesionario', function()
    local here, best, bestDistance = GetEntityCoords(PlayerPedId()), nil, nil
    for _, d in ipairs(dealers) do
        local dist = #(here - vector3(d.counter.x, d.counter.y, d.counter.z))
        if not bestDistance or dist < bestDistance then best, bestDistance = d, dist end
    end
    if best then SetNewWaypoint(best.counter.x, best.counter.y) end
end, false)
TriggerEvent('chat:addSuggestion', '/concesionarios', '[admin] Precios, modelos y puntos de los concesionarios')
