-- Armas guardadas con cada personaje: al aparecer se quitan las del ped y se dan las guardadas; despues se
-- comprueba cada pocos segundos y se envia al servidor solo si cambian (cambio de armas o accesorios al momento;
-- solo municion, como mucho cada 30 s). Mientras aparece, esta muerto o cambia de personaje no se envia nada.
local W = OSDevtools.WeaponsConfig
local AMMO_ONLY_MILLISECONDS = 30000
local weapons = { syncing = false }
local pendingList, lastKey, lastAmmoKey, lastSent = nil, nil, nil, 0
local hashes, componentHashes = {}, {}
for _, name in ipairs(W.List) do hashes[name] = GetHashKey(name) end
for _, name in ipairs(W.Components) do componentHashes[name] = GetHashKey(name) end

local function snapshot(ped)
    local list = {}
    for _, name in ipairs(W.List) do
        local hash = hashes[name]
        if HasPedGotWeapon(ped, hash, false) then
            local entry = { name = name, ammo = math.max(0, math.min(W.MaxAmmo, GetAmmoInPedWeapon(ped, hash))) }
            local tint = GetPedWeaponTintIndex(ped, hash)
            if tint and tint > 0 and tint <= W.MaxTint then entry.tint = tint end
            local parts = {}
            for _, component in ipairs(W.Components) do
                local ch = componentHashes[component]
                if #parts < W.MaxComponents and DoesWeaponTakeWeaponComponent(hash, ch) and HasPedGotWeaponComponent(ped, hash, ch) then parts[#parts + 1] = component end
            end
            if #parts > 0 then entry.components = parts end
            list[#list + 1] = entry
            if #list >= W.MaxWeapons then break end
        end
    end
    return list
end
-- Claves para saber que ha cambiado: equipo (armas, tintes, accesorios) y municion por separado.
local function keys(list)
    local gear, ammo = {}, {}
    for _, w in ipairs(list) do
        gear[#gear + 1] = w.name .. ':' .. tostring(w.tint or 0) .. ':' .. table.concat(w.components or {}, '+')
        ammo[#ammo + 1] = w.name .. ':' .. w.ammo
    end
    return table.concat(gear, '|'), table.concat(ammo, '|')
end

-- Al recibir la aparicion: deja de enviar y guarda la lista que se dara al terminar.
function weapons.hold(list)
    weapons.syncing = false
    pendingList = type(list) == 'table' and list or nil
end
-- Aparicion confirmada: sustituye las armas del ped por las del personaje y reanuda el envio.
function weapons.release()
    if not W.Enabled then return end
    local list = pendingList; pendingList = nil
    if not list then return end -- sin datos de armas (servidor antiguo o desactivado): no se toca nada
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    for _, w in ipairs(list) do
        local hash = type(w) == 'table' and hashes[w.name]
        if hash then
            GiveWeaponToPed(ped, hash, 0, false, false)
            SetPedAmmo(ped, hash, math.max(0, math.min(W.MaxAmmo, math.floor(tonumber(w.ammo) or 0))))
            for _, component in ipairs(type(w.components) == 'table' and w.components or {}) do
                if componentHashes[component] then GiveWeaponComponentToPed(ped, hash, componentHashes[component]) end
            end
            if tonumber(w.tint) then SetPedWeaponTintIndex(ped, hash, math.floor(tonumber(w.tint))) end
        end
    end
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    lastKey, lastAmmoKey = keys(snapshot(ped)); lastSent = GetGameTimer()
    weapons.syncing = true
end

CreateThread(function()
    if not W.Enabled then return end
    while true do
        Wait(W.CheckMilliseconds)
        local ped = PlayerPedId()
        if weapons.syncing and not IsEntityDead(ped) then
            local list = snapshot(ped)
            local gear, ammo = keys(list)
            local now = GetGameTimer()
            if gear ~= lastKey or (ammo ~= lastAmmoKey and now - lastSent >= AMMO_ONLY_MILLISECONDS) then
                lastKey, lastAmmoKey, lastSent = gear, ammo, now
                TriggerServerEvent('osdev:weapons', list)
            end
        end
    end
end)
-- Al cambiar de personaje el servidor ignora los envios hasta que el nuevo personaje aparece (y aqui hold/release).

OSDevtools.Weapons = weapons
