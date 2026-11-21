-- Disenador de personaje (NUI). Se abre al aparecer con un personaje sin apariencia guardada
-- (context.design del servidor) o con /disenarpj. Solo modelos freemode. Al terminar se guarda por
-- la ruta normal (osdev:saveAppearance), que el servidor valida y persiste.
local Appearance=OSDevtools.Appearance
local MALE,FEMALE=GetHashKey('mp_m_freemode_01'),GetHashKey('mp_f_freemode_01')
local CLOTHES={top=11,undershirt=8,arms=3,legs=4,shoes=6,mask=1,bag=5,accessory=7}
local PROPS={hat=0,glasses=1,watch=6,bracelet=7}
-- wardrobe: abierto desde un armario (solo ropa y conjuntos); original: ropa con la que se entro (Cancelar).
local view={open=false,cam=nil,mode='body',heading=0.0,baseHeading=0.0,state=nil,wardrobe=false,original=nil}
local outfits={} -- conjuntos del personaje (los manda el servidor)
local function outfitSummary()
    local list={}
    for i,o in ipairs(outfits) do list[#list+1]={index=i,name=o.name,sex=o.sex,fits=view.state and o.sex==view.state.sex or false} end
    return list
end

local function int(value,minimum,maximum,fallback)
    value=math.tointeger(tonumber(value)) or fallback
    if value<minimum then return minimum end
    if value>maximum then return maximum end
    return value
end
local function unit(value,minimum,fallback)
    value=tonumber(value);if not value or value~=value then return fallback end
    return math.max(minimum or 0.0,math.min(1.0,value))
end

-- Estado del disenador leido del ped actual (base de la edicion).
local function read(ped)
    local data=Appearance.capture(ped) or {components={},props={}}
    local head=data.head or {}
    local blend=head.blend or {sf=0,ss=21,sm=0.5,km=0.5}
    local overlays=head.overlays or {}
    local function overlay(index,none)
        local o=overlays[index+1]
        if not o or o.v==255 then return {style=none,opacity=1.0,color=0} end
        return {style=o.v,opacity=o.o,color=o.c}
    end
    local state={sex=GetEntityModel(ped)==FEMALE and 'female' or 'male',
        father=blend.sf,mother=blend.ss,shapeMix=blend.sm,skinMix=blend.km,features={},
        hair={style=data.components[3] and data.components[3].d or 0,color=head.hair and head.hair.c or 0,highlight=head.hair and head.hair.h or 0},
        eyebrows=overlay(2,0),beard=overlay(1,-1),eyes=head.eyes or 0,clothes={},props={}}
    for i=1,20 do state.features[i]=head.features and head.features[i] or 0.0 end
    for key,component in pairs(CLOTHES) do
        local c=data.components[component+1] or {d=0,t=0};state.clothes[key]={d=c.d,t=c.t}
    end
    for key,index in pairs(PROPS) do
        state.props[key]={d=-1,t=0}
        for _,p in ipairs(data.props) do if p.i==index then state.props[key]={d=p.d,t=math.max(p.t,0)} end end
    end
    return state
end

local function limits(ped,state)
    local result={hair=GetNumberOfPedDrawableVariations(ped,2),hairColors=GetNumHairColors(),eyebrows=GetPedHeadOverlayNum(2),
        beard=GetPedHeadOverlayNum(1),clothes={},props={}}
    for key,component in pairs(CLOTHES) do
        result.clothes[key]={d=GetNumberOfPedDrawableVariations(ped,component),t=GetNumberOfPedTextureVariations(ped,component,state.clothes[key].d)}
    end
    for key,index in pairs(PROPS) do
        local d=state.props[key].d
        result.props[key]={d=GetNumberOfPedPropDrawableVariations(ped,index),t=d>=0 and GetNumberOfPedPropTextureVariations(ped,index,d) or 0}
    end
    return result
end

-- Todo lo que llega de la pagina se acota a lo que existe en este ped.
local function sanitize(ped,input,base)
    local s=base
    if type(input)~='table' then return s end
    s.father=int(input.father,0,45,s.father);s.mother=int(input.mother,0,45,s.mother)
    s.shapeMix=unit(input.shapeMix,0.0,s.shapeMix);s.skinMix=unit(input.skinMix,0.0,s.skinMix)
    if type(input.features)=='table' then for i=1,20 do s.features[i]=unit(input.features[i],-1.0,s.features[i]) end end
    local l=limits(ped,s)
    if type(input.hair)=='table' then
        s.hair.style=int(input.hair.style,0,math.max(l.hair-1,0),s.hair.style)
        s.hair.color=int(input.hair.color,0,math.max(l.hairColors-1,0),s.hair.color)
        s.hair.highlight=int(input.hair.highlight,0,math.max(l.hairColors-1,0),s.hair.highlight)
    end
    for key,none in pairs({eyebrows=0,beard=-1}) do
        local value=input[key]
        if type(value)=='table' then
            local count=key=='eyebrows' and l.eyebrows or l.beard
            s[key]={style=int(value.style,none,math.max(count-1,none),s[key].style),opacity=unit(value.opacity,0.0,s[key].opacity),color=int(value.color,0,63,s[key].color)}
        end
    end
    if s.sex=='female' then s.beard.style=-1 end
    s.eyes=int(input.eyes,0,31,s.eyes)
    for key in pairs(CLOTHES) do
        local value=type(input.clothes)=='table' and input.clothes[key]
        if type(value)=='table' then
            local d=int(value.d,0,math.max(l.clothes[key].d-1,0),s.clothes[key].d)
            local textures=d==s.clothes[key].d and l.clothes[key].t or GetNumberOfPedTextureVariations(ped,CLOTHES[key],d)
            s.clothes[key]={d=d,t=int(value.t,0,math.max(textures-1,0),0)}
        end
    end
    for key,index in pairs(PROPS) do
        local value=type(input.props)=='table' and input.props[key]
        if type(value)=='table' then
            local d=int(value.d,-1,math.max(l.props[key].d-1,-1),s.props[key].d)
            local textures=d>=0 and GetNumberOfPedPropTextureVariations(ped,index,d) or 0
            s.props[key]={d=d,t=d>=0 and int(value.t,0,math.max(textures-1,0),0) or 0}
        end
    end
    return s
end

local function apply(ped,s)
    SetPedHeadBlendData(ped,s.father,s.mother,0,s.father,s.mother,0,s.shapeMix+0.0,s.skinMix+0.0,0.0,false)
    for i=1,20 do SetPedFaceFeature(ped,i-1,s.features[i]+0.0) end
    SetPedComponentVariation(ped,2,s.hair.style,0,0)
    SetPedHairColor(ped,s.hair.color,s.hair.highlight)
    SetPedHeadOverlay(ped,2,s.eyebrows.style,s.eyebrows.opacity+0.0);SetPedHeadOverlayColor(ped,2,1,s.eyebrows.color,s.eyebrows.color)
    if s.beard.style<0 then SetPedHeadOverlay(ped,1,255,0.0)
    else SetPedHeadOverlay(ped,1,s.beard.style,s.beard.opacity+0.0);SetPedHeadOverlayColor(ped,1,1,s.beard.color,s.beard.color) end
    SetPedEyeColor(ped,s.eyes)
    for key,component in pairs(CLOTHES) do SetPedComponentVariation(ped,component,s.clothes[key].d,s.clothes[key].t,0) end
    for key,index in pairs(PROPS) do
        local p=s.props[key]
        if p.d<0 then ClearPedProp(ped,index) else SetPedPropIndex(ped,index,p.d,p.t,true) end
    end
end

local function hold(ped)
    FreezeEntityPosition(ped,true);SetEntityInvincible(ped,true);SetEntityHeading(ped,view.baseHeading+view.heading)
    ClearPedTasksImmediately(ped)
end
local function placeCamera()
    local ped=PlayerPedId()
    local face=view.mode=='face'
    local base=GetEntityCoords(ped)
    -- Cuerpo entero: mas lejos y a la altura de la cadera, mirando algo por debajo, para que entren los pies.
    local distance,height=face and 0.75 or 3.1,face and 0.65 or -0.05
    local target=face and GetPedBoneCoords(ped,31086,0.0,0.0,0.0) or vector3(base.x,base.y,base.z-0.2)
    -- La camara mira al ped desde delante segun su orientacion inicial (no gira con el).
    local h=math.rad(view.baseHeading)
    local dir=vector3(-math.sin(h),math.cos(h),0.0)
    local position=vector3(base.x+dir.x*distance,base.y+dir.y*distance,base.z+height)
    if not view.cam then view.cam=CreateCam('DEFAULT_SCRIPTED_CAMERA',true) end
    SetCamCoord(view.cam,position.x,position.y,position.z)
    PointCamAtCoord(view.cam,target.x,target.y,target.z)
    SetCamFov(view.cam,face and 30.0 or 45.0)
    SetCamActive(view.cam,true);RenderScriptCams(true,true,350,true,true)
end

local function setSex(sex)
    local model=sex=='female' and FEMALE or MALE
    if GetEntityModel(PlayerPedId())==model then return true end
    RequestModel(model)
    local deadline=GetGameTimer()+5000
    while not HasModelLoaded(model) and GetGameTimer()<deadline do Wait(0) end
    if not HasModelLoaded(model) then return false end
    SetPlayerModel(PlayerId(),model);SetModelAsNoLongerNeeded(model)
    local ped=PlayerPedId()
    SetPedDefaultComponentVariation(ped)
    SetPedHeadBlendData(ped,0,21,0,0,21,0,0.5,0.5,0.0,false)
    hold(ped)
    return true
end

local function payload() local ped=PlayerPedId();return {state=view.state,limits=limits(ped,view.state)} end

local function open(mode)
    if view.open then return end
    local ped=PlayerPedId()
    if IsEntityDead(ped) then return end
    local model=GetEntityModel(ped)
    -- Armario: solo ropa; un modelo que no es freemode no tiene ropa por piezas.
    if mode=='wardrobe' and model~=MALE and model~=FEMALE then return OSDevtools.Notify('Tu personaje no usa un modelo con ropa por piezas.','warning') end
    view.open=true;view.mode='body';view.heading=0.0;view.baseHeading=GetEntityHeading(ped)
    view.wardrobe=mode=='wardrobe'
    Appearance.designing=true
    -- Un modelo que no es freemode no tiene cabeza editable: se parte del freemode masculino.
    if model~=MALE and model~=FEMALE then setSex('male');ped=PlayerPedId() end
    hold(ped)
    view.state=read(ped)
    view.original=view.wardrobe and read(ped) or nil
    apply(ped,view.state)
    placeCamera();DisplayRadar(false)
    CreateThread(function()
        while view.open do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            Wait(0)
        end
    end)
    local data=payload();data.action='creator';data.open=true
    data.wardrobe=view.wardrobe;data.outfits=view.wardrobe and outfitSummary() or nil
    SendNUIMessage(data)
    SetNuiFocus(true,true)
end
local function close()
    if not view.open then return end
    view.open=false;view.wardrobe=false;view.original=nil;Appearance.designing=false
    SetNuiFocus(false,false)
    SendNUIMessage({action='creator',open=false})
    if view.cam then RenderScriptCams(false,true,500,true,true);DestroyCam(view.cam,false);view.cam=nil end
    local ped=PlayerPedId()
    FreezeEntityPosition(ped,false);SetEntityInvincible(ped,false)
    DisplayRadar(true)
end
OSDevtools.Creator={open=open,close=close}

RegisterNUICallback('creatorApply',function(data,cb)
    if not view.open or type(data)~='table' then return cb({}) end
    -- En el armario solo se cambia la ropa (ni sexo, ni cara, ni pelo).
    if view.wardrobe then
        local ped=PlayerPedId()
        view.state=sanitize(ped,{clothes=data.clothes,props=data.props},view.state)
        apply(ped,view.state)
        return cb(payload())
    end
    local sex=data.sex=='female' and 'female' or 'male'
    if sex~=view.state.sex then
        if not setSex(sex) then return cb({error='No se pudo cargar el modelo.'}) end
        local ped=PlayerPedId()
        local keep=view.state
        view.state=read(ped)
        -- Se conserva la cara elegida; ropa y pelo vuelven a los del nuevo modelo.
        view.state.father,view.state.mother,view.state.shapeMix,view.state.skinMix=keep.father,keep.mother,keep.shapeMix,keep.skinMix
        view.state.features,view.state.eyes=keep.features,keep.eyes
        apply(ped,view.state);placeCamera()
        return cb(payload())
    end
    local ped=PlayerPedId()
    view.state=sanitize(ped,data,view.state)
    apply(ped,view.state)
    cb(payload())
end)
RegisterNUICallback('creatorView',function(data,cb)
    cb({})
    if not view.open or type(data)~='table' then return end
    if data.mode=='face' or data.mode=='body' then view.mode=data.mode end
    view.heading=(tonumber(data.heading) or 0.0)%360
    SetEntityHeading(PlayerPedId(),view.baseHeading+view.heading)
    if data.mode then placeCamera() end
end)
RegisterNUICallback('creatorFinish',function(_,cb)
    cb({})
    if not view.open then return end
    local ped=PlayerPedId()
    SetEntityHeading(ped,view.baseHeading)
    local data=Appearance.capture(ped)
    close()
    if not data then return OSDevtools.Notify('No se pudo leer el aspecto; usa /guardarropa.','error') end
    Appearance.locked=false
    Appearance.last=Appearance.signature(data)
    TriggerServerEvent('osdev:saveAppearance',data,true)
end)

-- Armario: Cancelar deja la ropa con la que se entro; los conjuntos los guarda el servidor por personaje.
RegisterNUICallback('creatorCancel',function(_,cb)
    cb({})
    if not view.open then return end
    if view.wardrobe and view.original then
        local ped=PlayerPedId()
        SetEntityHeading(ped,view.baseHeading)
        apply(ped,view.original)
    end
    close()
end)
RegisterNUICallback('wardrobeWear',function(data,cb)
    local outfit=view.open and view.wardrobe and type(data)=='table' and outfits[math.tointeger(tonumber(data.index)) or 0]
    if not outfit then return cb({error='Conjunto no encontrado.'}) end
    if outfit.sex~=view.state.sex then return cb({error='Ese conjunto es de otro modelo (hombre / mujer).'}) end
    local ped=PlayerPedId()
    -- Las prendas que no guarda el conjunto se quedan como estan.
    view.state=sanitize(ped,{clothes=outfit.clothes,props=outfit.props},view.state)
    apply(ped,view.state)
    cb(payload())
end)
RegisterNUICallback('wardrobeSave',function(data,cb)
    cb({})
    if not view.open or not view.wardrobe or type(data)~='table' then return end
    TriggerServerEvent('osdev:outfits:save',{name=tostring(data.name or ''),sex=view.state.sex,clothes=view.state.clothes,props=view.state.props})
end)
RegisterNUICallback('wardrobeDelete',function(data,cb)
    cb({})
    if view.open and view.wardrobe and type(data)=='table' then TriggerServerEvent('osdev:outfits:delete',math.tointeger(tonumber(data.index))) end
end)
RegisterNetEvent('osdev:outfits:list',function(list)
    if source~=65535 or type(list)~='table' then return end
    outfits=list
    if view.open and view.wardrobe then SendNUIMessage({action='wardrobeOutfits',outfits=outfitSummary()}) end
end)
RegisterNetEvent('osdev:wardrobe:open',function(list)
    if source~=65535 then return end
    outfits=type(list)=='table' and list or {}
    if Appearance.spawning or IsPedInAnyVehicle(PlayerPedId(),false) then return end
    open('wardrobe')
end)

-- Puntos de armario (los manda el servidor): marca cerca y E para abrir; el servidor comprueba llave y distancia.
local wardrobePoints={}
RegisterNetEvent('osdev:wardrobes',function(list) if source==65535 and type(list)=='table' then wardrobePoints=list end end)
CreateThread(function()
    TriggerServerEvent('osdev:wardrobes:request')
    local lastUse=0
    while true do
        local sleep=1000
        if not view.open and #wardrobePoints>0 then
            local ped=PlayerPedId();local p=GetEntityCoords(ped)
            local best,dist
            for _,w in ipairs(wardrobePoints) do
                local d=#(p-vector3(w.x,w.y,w.z))
                if d<15.0 and (not dist or d<dist) then best,dist=w,d end
            end
            if best then
                sleep=0
                DrawMarker(2,best.x,best.y,best.z,0.0,0.0,0.0,0.0,180.0,0.0,0.25,0.25,0.25,127,201,142,170,true,true,2,false,nil,nil,false)
                if dist<1.5 then
                    BeginTextCommandDisplayHelp('STRING');AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ Abrir el armario');EndTextCommandDisplayHelp(0,false,false,-1)
                    if IsControlJustPressed(0,38) and GetGameTimer()-lastUse>1500 then lastUse=GetGameTimer();TriggerServerEvent('osdev:wardrobe:use',best.id) end
                end
            end
        end
        Wait(sleep)
    end
end)

-- Aparicion con context.design: se abre cuando el servidor la acepta y la aparicion termina.
local designToken=nil
RegisterNetEvent('osdev:spawnCharacter')
AddEventHandler('osdev:spawnCharacter',function(context)
    if source~=65535 then return end
    if view.open then close() end
    designToken=type(context)=='table' and context.design==true and context.token or nil
end)
RegisterNetEvent('osdev:spawnAccepted')
AddEventHandler('osdev:spawnAccepted',function(token)
    if source~=65535 or not designToken or token~=designToken then return end
    designToken=nil
    CreateThread(function()
        while Appearance.spawning do Wait(100) end
        Wait(400)
        open()
    end)
end)
RegisterCommand('disenarpj',function()
    if Appearance.spawning then return OSDevtools.Notify('Espera a terminar de aparecer.','warning') end
    if IsEntityDead(PlayerPedId()) or IsPedInAnyVehicle(PlayerPedId(),false) then return OSDevtools.Notify('Sal del vehiculo y sigue con vida para disenar tu personaje.','warning') end
    open()
end,false)
AddEventHandler('onClientResourceStop',function(name) if name==GetCurrentResourceName() then close() end end)
