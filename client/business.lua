-- Blips de negocios. Uno por ID: una lista nueva actualiza o retira los existentes, sin duplicar.
local blips={} -- id -> {handle, signature}

local function remove(id)
    local entry=blips[id]
    if entry and DoesBlipExist(entry.handle) then RemoveBlip(entry.handle) end
    blips[id]=nil
end

local function create(b,kind)
    local blip=AddBlipForCoord(b.x+0.0,b.y+0.0,b.z+0.0)
    SetBlipSprite(blip,kind.sprite)
    SetBlipColour(blip,kind.color)
    SetBlipScale(blip,OSDevtools.BusinessBlipScale or 0.8)
    SetBlipAsShortRange(blip,true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(b.name)
    EndTextCommandSetBlipName(blip)
    return blip
end

RegisterNetEvent('osdev:businessBlips',function(list)
    if source~=65535 or type(list)~='table' then return end
    local wanted={}
    for _,b in ipairs(list) do
        local kind=type(b)=='table' and OSDevtools.BusinessTypes[b.type]
        if kind and tonumber(b.id) and tonumber(b.x) and tonumber(b.y) and tonumber(b.z) and type(b.name)=='string' then
            local signature=table.concat({b.type,b.name,b.x,b.y,b.z},'|')
            wanted[b.id]=true
            if not blips[b.id] or blips[b.id].signature~=signature then
                remove(b.id)
                blips[b.id]={handle=create(b,kind),signature=signature}
            end
        end
    end
    for id in pairs(blips) do if not wanted[id] then remove(id) end end
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    TriggerServerEvent('osdev:requestBusinessBlips')
end)

AddEventHandler('onClientResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    for id in pairs(blips) do remove(id) end
end)
