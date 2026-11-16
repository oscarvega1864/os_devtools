-- Menu /negocio: rangos, plantilla y contratar (el servidor valida todo). Invitacion recibida: Aceptar o Rechazar.
local open, invited = false, false
local function focus() SetNuiFocus(open or invited, open or invited) end
RegisterNetEvent('osdev:business:open', function()
    if source ~= 65535 then return end
    open = true; focus()
    SendNUIMessage({ action = 'business', open = true })
end)
RegisterNetEvent('osdev:business:data', function(data, message, kind)
    if source ~= 65535 or type(data) ~= 'table' then return end
    SendNUIMessage({ action = 'businessData', data = data, message = message, kind = kind })
end)
RegisterNetEvent('osdev:business:invited', function(data)
    if source ~= 65535 or type(data) ~= 'table' then return end
    invited = true; focus()
    SendNUIMessage({ action = 'businessInvite', data = data })
end)
RegisterNUICallback('businessClose', function(_, cb) open = false; focus(); SendNUIMessage({ action = 'business', open = false }); cb({}) end)
RegisterNUICallback('businessRefresh', function(_, cb) TriggerServerEvent('osdev:business:refresh'); cb({}) end)
RegisterNUICallback('businessRank', function(d, cb)
    if type(d) == 'table' then TriggerServerEvent('osdev:business:rank', d.id, d.op, d.name, d.dir) end
    cb({})
end)
RegisterNUICallback('businessInvite', function(d, cb)
    if type(d) == 'table' then TriggerServerEvent('osdev:business:invite', d.id, d.target, d.rank) end
    cb({})
end)
RegisterNUICallback('businessDutyPoint', function(d, cb)
    if type(d) == 'table' then TriggerServerEvent('osdev:business:dutyPoint', d.id) end
    cb({})
end)
RegisterNUICallback('businessSalary', function(d, cb)
    if type(d) == 'table' then TriggerServerEvent('osdev:business:salary', d.id, d.rank, d.amount) end
    cb({})
end)
RegisterNUICallback('businessStaff', function(d, cb)
    if type(d) == 'table' then TriggerServerEvent('osdev:business:staff', d.id, d.alias, d.op, d.rank) end
    cb({})
end)
RegisterNUICallback('businessAnswer', function(d, cb)
    invited = false; focus()
    TriggerServerEvent('osdev:business:answer', type(d) == 'table' and d.accept == true)
    cb({})
end)
AddEventHandler('onResourceStop', function(name) if name == GetCurrentResourceName() and (open or invited) then SetNuiFocus(false, false) end end)

-- Puntos de servicio de mis negocios: marcador y E para entrar o salir de servicio.
local dutyPoints = {}
RegisterNetEvent('osdev:dutyPoints', function(list) if source == 65535 and type(list) == 'table' then dutyPoints = list end end)
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    Wait(5000)
    TriggerServerEvent('osdev:dutyPointsRequest')
    while true do
        local wait = 1000
        local here = GetEntityCoords(PlayerPedId())
        for _, p in ipairs(dutyPoints) do
            local d = #(here - vector3(p.x, p.y, p.z))
            if d < 20.0 then
                wait = 0
                DrawMarker(27, p.x, p.y, p.z - 0.97, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 1.1, 1.1, p.onDuty and 74 or 127, p.onDuty and 222 or 201, p.onDuty and 128 or 142, 150, false, false, 2, false, nil, nil, false)
                if d < 1.6 and not IsNuiFocused() then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName(('~INPUT_CONTEXT~ %s servicio · %s'):format(p.onDuty and 'Salir de' or 'Entrar de', p.name))
                    EndTextCommandDisplayHelp(0, false, false, -1)
                    if IsControlJustPressed(0, 38) then TriggerServerEvent('osdev:business:duty', p.id); Wait(500) end
                end
            end
        end
        Wait(wait)
    end
end)
RegisterNetEvent('osdev:characterChanged', function() if source == 65535 then TriggerServerEvent('osdev:dutyPointsRequest') end end)
