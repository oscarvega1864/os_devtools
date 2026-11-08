-- Blips de negocios y propiedades. Uno por ID y categoria: una lista nueva actualiza o retira los existentes, sin duplicar.
local blips={} -- 'b'/'p'..id -> {handle, signature}

local function remove(id)
    local entry=blips[id]
    if entry and DoesBlipExist(entry.handle) then RemoveBlip(entry.handle) end
    blips[id]=nil
end

local function create(b,kind,scale)
    local blip=AddBlipForCoord(b.x+0.0,b.y+0.0,b.z+0.0)
    SetBlipSprite(blip,kind.sprite)
    SetBlipColour(blip,kind.color)
    SetBlipScale(blip,scale)
    SetBlipAsShortRange(blip,true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(b.name)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function apply(list,types,prefix,scale,wanted)
    if type(list)~='table' then return end
    for _,b in ipairs(list) do
        local kind=type(b)=='table' and types[b.type]
        if kind and tonumber(b.id) and tonumber(b.x) and tonumber(b.y) and tonumber(b.z) and type(b.name)=='string' then
            local key=prefix..b.id
            local signature=table.concat({b.type,b.name,b.x,b.y,b.z},'|')
            wanted[key]=true
            if not blips[key] or blips[key].signature~=signature then
                remove(key)
                blips[key]={handle=create(b,kind,scale),signature=signature}
            end
        end
    end
end

RegisterNetEvent('osdev:businessBlips',function(list,properties)
    if source~=65535 or type(list)~='table' then return end
    local wanted={}
    apply(list,OSDevtools.BusinessTypes,'b',OSDevtools.BusinessBlipScale or 0.8,wanted)
    apply(properties,OSDevtools.PropertyBlipTypes or {},'p',OSDevtools.PropertyBlipScale or 0.7,wanted)
    for key in pairs(blips) do if not wanted[key] then remove(key) end end
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    TriggerServerEvent('osdev:requestBusinessBlips')
end)

AddEventHandler('onClientResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    for id in pairs(blips) do remove(id) end
end)
