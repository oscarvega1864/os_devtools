-- Selector de personaje (NUI). Al entrar: escena con camara fija, cierra la pantalla de carga y
-- espera a que el jugador elija. Con /personajes: el mismo panel sobre el juego para cambiar.
-- El cliente solo propone un alias o un nombre; el servidor valida cuenta, propiedad y aparicion.
local scene=OSDevtools.SelectScene
local view={open=false,mode=nil,payload=nil,ready=false,cam=nil,staged=false,appearances={}}
-- Previsualizacion: ped local (no se sincroniza con nadie) con el aspecto del personaje marcado.
local preview={ped=nil,alias=nil,generation=0,ground=nil}
local FEMALE,MALE=GetHashKey('mp_f_freemode_01'),GetHashKey('mp_m_freemode_01')

local function sameModel(a,b) return type(a)=='number' and (a%4294967296)==(b%4294967296) end
local function label(text) return text and text~='' and text~='NULL' and text or nil end
-- Lugar legible de la ultima posicion (calle y zona) calculado en este cliente.
local function place(position)
    if type(position)~='table' or not tonumber(position.x) then return nil end
    local x,y,z=position.x+0.0,position.y+0.0,position.z+0.0
    local zone=label(GetLabelText(GetNameOfZone(x,y,z)))
    local street=GetStreetNameAtCoord(x,y,z)
    street=street and street~=0 and label(GetStreetNameFromHashKey(street)) or nil
    if street and zone then return street..', '..zone end
    return street or zone
end
local function decorate(payload)
    local rows={}
    view.appearances={}
    for _,c in ipairs(payload.characters or {}) do
        if type(c.alias)=='string' then view.appearances[c.alias]=type(c.appearance)=='table' and c.appearance or false end
        rows[#rows+1]={alias=c.alias,characterId=c.characterId,cash=c.cash,bank=c.bank,job=c.job,rank=c.rank,duty=c.duty,
            dead=c.dead,active=c.active,lastSeen=c.lastSeen,place=place(c.position),
            gender=sameModel(c.model,FEMALE) and 'female' or sameModel(c.model,MALE) and 'male' or (c.model and 'other' or nil)}
    end
    return {action='select',open=true,mode=payload.mode,characters=rows,allowCreate=payload.allowCreate==true,
        maxCharacters=payload.maxCharacters,message=payload.message}
end

local function stageScene()
    if view.staged then return end
    view.staged=true
    local ped=PlayerPedId()
    FreezeEntityPosition(ped,true);SetEntityVisible(ped,false,false);SetEntityInvincible(ped,true);SetEntityCollision(ped,false,false)
    -- Camara delante del punto del ped; se apunta a un lado para dejarlo a la derecha del encuadre.
    local p=scene.ped
    local h=math.rad(p.h)
    local fx,fy=-math.sin(h),math.cos(h)          -- hacia donde mira el ped
    local rx,ry=-fy,fx                            -- derecha de la camara (que mira al ped)
    local cx,cy,cz=p.x+fx*scene.distance,p.y+fy*scene.distance,p.z+scene.height
    SetFocusPosAndVel(p.x,p.y,p.z,0.0,0.0,0.0)
    RequestCollisionAtCoord(p.x,p.y,p.z)
    view.cam=CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',cx,cy,cz,0.0,0.0,0.0,scene.fov or 40.0,false,0)
    PointCamAtCoord(view.cam,p.x-rx*scene.shift,p.y-ry*scene.shift,p.z-0.05)
    SetCamActive(view.cam,true);RenderScriptCams(true,false,0,true,true)
    DisplayRadar(false)
    CreateThread(function()
        while view.staged do HideHudAndRadarThisFrame();Wait(0) end
    end)
end
local function deletePreview()
    preview.generation=preview.generation+1
    if preview.ped and DoesEntityExist(preview.ped) then DeleteEntity(preview.ped) end
    preview.ped,preview.alias=nil,nil
end
local function groundZ(p)
    if preview.ground then return preview.ground end
    RequestCollisionAtCoord(p.x,p.y,p.z)
    for _=1,30 do
        local found,z=GetGroundZFor_3dCoord(p.x,p.y,p.z+1.0,false)
        if found then preview.ground=z;return z end
        Wait(50)
    end
    return p.z-1.0
end
-- Crea el ped del personaje con su aspecto guardado (o el modelo por defecto) y hace un fundido
-- con el anterior. Una eleccion mas reciente invalida la que estaba cargando.
local function showPreview(alias)
    if not view.staged or preview.alias==alias or view.appearances[alias]==nil then return end
    preview.generation=preview.generation+1
    local generation=preview.generation
    preview.alias=alias
    CreateThread(function()
        local Appearance=OSDevtools.Appearance
        local plan=Appearance.plan(view.appearances[alias] or nil)
        RequestModel(plan.model)
        local deadline=GetGameTimer()+5000
        while not HasModelLoaded(plan.model) and GetGameTimer()<deadline do Wait(0) end
        if generation~=preview.generation or not HasModelLoaded(plan.model) then return end
        local p=scene.ped
        local z=groundZ(p)
        if generation~=preview.generation then return end
        local ped=CreatePed(4,plan.model,p.x,p.y,z,p.h,false,true)
        SetModelAsNoLongerNeeded(plan.model)
        if ped==0 then return end
        SetEntityAlpha(ped,0,false)
        SetEntityInvincible(ped,true);SetBlockingOfNonTemporaryEvents(ped,true);SetPedCanRagdoll(ped,false)
        Appearance.apply(ped,plan)
        FreezeEntityPosition(ped,true)
        if scene.scenario then TaskStartScenarioInPlace(ped,scene.scenario,0,true) end
        local old=preview.ped
        preview.ped=ped
        for alpha=0,255,51 do
            if generation~=preview.generation then break end
            SetEntityAlpha(ped,alpha,false)
            if old and DoesEntityExist(old) then SetEntityAlpha(old,255-alpha,false) end
            Wait(16)
        end
        if DoesEntityExist(ped) then ResetEntityAlpha(ped) end
        if old and DoesEntityExist(old) then DeleteEntity(old) end
        -- Si otra eleccion llego durante el fundido, este ped ya no es el actual.
        if generation~=preview.generation and preview.ped~=ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    end)
end
local function clearScene()
    deletePreview()
    if not view.staged then return end
    view.staged=false
    if view.cam then RenderScriptCams(false,false,0,true,true);SetCamActive(view.cam,false);DestroyCam(view.cam,false);view.cam=nil end
    ClearFocus()
    local ped=PlayerPedId()
    SetEntityCollision(ped,true,true);SetEntityInvincible(ped,false)
    DisplayRadar(true)
end
local function endLoading()
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
end
OSDevtools.EndLoading=endLoading

local function push() if view.payload then SendNUIMessage(view.payload) end end
local function close()
    if not view.open then return end
    view.open=false;view.payload=nil
    SetNuiFocus(false,false)
    SendNUIMessage({action='select',open=false})
end

RegisterNetEvent('osdev:characterSelect',function(payload)
    if source~=65535 or type(payload)~='table' then return end
    view.mode=payload.mode=='switch' and 'switch' or 'connect'
    view.payload=decorate(payload);view.open=true
    if view.mode=='connect' then
        stageScene()
        push()
        endLoading()
        if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(800) end
    else push() end
    SetNuiFocus(true,true)
end)
RegisterNetEvent('osdev:characterSelectResult',function(result)
    if source~=65535 or type(result)~='table' then return end
    if result.ok then SendNUIMessage({action='selectBusy',busy=true}) return end
    SendNUIMessage({action='selectError',message=type(result.message)=='string' and result.message or 'Operacion rechazada.'})
end)
-- Cualquier aparicion (eleccion, personaje nuevo o reserva) cierra el panel; la escena se
-- retira cuando la pantalla ya esta en negro para que no se vea el salto de camara.
RegisterNetEvent('osdev:spawnCharacter')
AddEventHandler('osdev:spawnCharacter',function()
    if source~=65535 then return end
    close();endLoading()
    if not view.staged then return end
    CreateThread(function()
        local deadline=GetGameTimer()+2000
        while not IsScreenFadedOut() and GetGameTimer()<deadline do Wait(0) end
        clearScene()
    end)
end)

RegisterNUICallback('selectPreview',function(data,cb)
    cb({})
    if view.open and view.mode=='connect' and type(data)=='table' and type(data.alias)=='string' then showPreview(data.alias) end
end)
RegisterNUICallback('selectReady',function(_,cb) view.ready=true;cb({});if view.open then push() end end)
RegisterNUICallback('selectCharacter',function(data,cb)
    cb({})
    if not view.open or type(data)~='table' or type(data.alias)~='string' then return end
    TriggerServerEvent('osdev:chooseCharacter',data.alias)
end)
RegisterNUICallback('createCharacter',function(data,cb)
    cb({})
    if not view.open or type(data)~='table' then return end
    local xml=type(data.xml)=='string' and #data.xml<=65536 and data.xml or nil
    -- Con XML se usa un evento latente (va en trozos): un XML de Menyoo puede pasar de varios KB.
    if xml then TriggerLatentServerEvent('osdev:createOwnCharacter',50000,tostring(data.first or ''),tostring(data.last or ''),xml)
    else TriggerServerEvent('osdev:createOwnCharacter',tostring(data.first or ''),tostring(data.last or '')) end
end)
RegisterNUICallback('selectClose',function(_,cb)
    cb({})
    if view.mode=='switch' then close() end
end)

AddEventHandler('onClientResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    if view.open then SetNuiFocus(false,false) end
    local staged=view.staged
    clearScene()
    if staged then local ped=PlayerPedId();SetEntityVisible(ped,true,false);FreezeEntityPosition(ped,false) end
end)
