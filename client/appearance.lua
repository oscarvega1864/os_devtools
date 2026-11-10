-- Captura y aplicacion de la apariencia del ped local. El servidor valida y persiste.
OSDevtools=OSDevtools or {}
local Appearance={ready=false,locked=false,spawning=false,last=nil}
OSDevtools.Appearance=Appearance

local DEFAULT_MODEL='mp_m_freemode_01'
local PROPS={0,1,2,6,7}
local function round(value) return math.floor(value*1000+0.5)/1000 end
local function clamp(value,minimum,maximum) return math.max(minimum,math.min(maximum,value)) end
local function freemode(model) return model==GetHashKey('mp_m_freemode_01') or model==GetHashKey('mp_f_freemode_01') end

-- GET_PED_HEAD_BLEND_DATA escribe una estructura de 10 campos de 8 bytes; se lee con string.unpack.
-- El bufer empieza en 0xFF: si el nativo no escribe, los enteros quedan en -1 y se descartan.
local function readBlend(ped)
    local ok,blend=pcall(function()
        local buffer=string.rep('\255',80)
        Citizen.InvokeNative(0x2746BD9D88C5C5D0,ped,buffer)
        local function int(offset) return string.unpack('<i4',buffer,offset+1) end
        local function float(offset) return string.unpack('<f',buffer,offset+1) end
        return {sf=int(0),ss=int(8),st=int(16),kf=int(24),ks=int(32),kt=int(40),sm=round(float(48)),km=round(float(56)),tm=round(float(64))}
    end)
    if not ok or type(blend)~='table' then return nil end
    for _,key in ipairs({'sf','ss','st','kf','ks','kt'}) do if blend[key]<0 or blend[key]>255 then return nil end end
    for _,key in ipairs({'sm','km','tm'}) do if blend[key]~=blend[key] or blend[key]<0 or blend[key]>1 then return nil end end
    return blend
end

function Appearance.capture(ped)
    local model=GetEntityModel(ped)
    if model==0 then return nil end
    local data={model=model,components={},props={}}
    for component=0,11 do
        data.components[#data.components+1]={d=clamp(GetPedDrawableVariation(ped,component),0,4095),t=clamp(GetPedTextureVariation(ped,component),0,255),p=clamp(GetPedPaletteVariation(ped,component),0,3)}
    end
    for _,index in ipairs(PROPS) do
        data.props[#data.props+1]={i=index,d=clamp(GetPedPropIndex(ped,index),-1,4095),t=clamp(GetPedPropTextureIndex(ped,index),-1,255)}
    end
    if freemode(model) then
        local head={blend=readBlend(ped),features={},overlays={},hair={c=clamp(GetPedHairColor(ped),0,63),h=clamp(GetPedHairHighlightColor(ped),0,63)},eyes=clamp(GetPedEyeColor(ped),0,31)}
        for feature=0,19 do head.features[#head.features+1]=clamp(round(GetPedFaceFeature(ped,feature)),-1,1) end
        for overlay=0,12 do
            local _,value,colorType,color,second,opacity=GetPedHeadOverlayData(ped,overlay)
            head.overlays[#head.overlays+1]={v=clamp(value or 255,0,255),o=clamp(round(opacity or 0),0,1),ct=clamp(colorType or 0,0,2),c=clamp(color or 0,0,63),c2=clamp(second or 0,0,63)}
        end
        data.head=head
    end
    return data
end

-- Firma estable para detectar cambios sin depender del orden de json.encode.
function Appearance.signature(data)
    if not data then return '' end
    local parts={tostring(data.model)}
    for _,c in ipairs(data.components) do parts[#parts+1]=c.d..':'..c.t..':'..c.p end
    for _,p in ipairs(data.props) do parts[#parts+1]=p.i..':'..p.d..':'..p.t end
    local h=data.head
    if h then
        local b=h.blend
        parts[#parts+1]=b and table.concat({b.sf,b.ss,b.st,b.kf,b.ks,b.kt,b.sm,b.km,b.tm},',') or 'noblend'
        for _,f in ipairs(h.features) do parts[#parts+1]=tostring(f) end
        for _,o in ipairs(h.overlays) do parts[#parts+1]=table.concat({o.v,o.o,o.ct,o.c,o.c2},',') end
        parts[#parts+1]=h.hair.c..','..h.hair.h..','..h.eyes
    end
    return table.concat(parts,'|')
end

-- Decide el modelo antes de aparecer. Un modelo ausente (mod retirado) no borra los datos:
-- se usa el modelo por defecto y se bloquea el guardado automatico hasta /guardarropa.
function Appearance.plan(data)
    if type(data)=='table' and tonumber(data.model) then
        local model=tonumber(data.model)
        if IsModelInCdimage(model) and IsModelValid(model) then return {model=model,data=data,locked=false} end
        return {model=GetHashKey(DEFAULT_MODEL),data=nil,locked=true}
    end
    return {model=GetHashKey(DEFAULT_MODEL),data=nil,locked=false}
end

local function applyHead(ped,head)
    local b=head.blend
    if b then SetPedHeadBlendData(ped,b.sf,b.ss,b.st,b.kf,b.ks,b.kt,b.sm+0.0,b.km+0.0,b.tm+0.0,false) end
    for index,value in ipairs(head.features) do SetPedFaceFeature(ped,index-1,value+0.0) end
    for index,o in ipairs(head.overlays) do
        SetPedHeadOverlay(ped,index-1,o.v,o.o+0.0)
        if o.ct>0 then SetPedHeadOverlayColor(ped,index-1,o.ct,o.c,o.c2) end
    end
    SetPedHairColor(ped,head.hair.c,head.hair.h)
    SetPedEyeColor(ped,head.eyes)
end

function Appearance.apply(ped,plan)
    if GetEntityModel(ped)~=plan.model then return false end
    if not plan.data then
        SetPedDefaultComponentVariation(ped)
        if freemode(plan.model) then SetPedHeadBlendData(ped,0,0,0,0,0,0,0.5,0.5,0.0,false) end
        return true
    end
    for index,c in ipairs(plan.data.components) do
        local component=index-1
        -- Solo variaciones que existen en este modelo: nunca ropa de otro modelo.
        if c.d<GetNumberOfPedDrawableVariations(ped,component) then SetPedComponentVariation(ped,component,c.d,c.t,c.p) end
    end
    for _,p in ipairs(plan.data.props) do
        if p.d<0 then ClearPedProp(ped,p.i)
        elseif p.d<GetNumberOfPedPropDrawableVariations(ped,p.i) then SetPedPropIndex(ped,p.i,p.d,math.max(p.t,0),true) end
    end
    if plan.data.head and freemode(plan.model) then applyHead(ped,plan.data.head) end
    return true
end

-- Cambia el modelo del jugador si hace falta. Devuelve false si no carga a tiempo.
function Appearance.setModel(plan)
    if GetEntityModel(PlayerPedId())==plan.model then return true end
    RequestModel(plan.model)
    local deadline=GetGameTimer()+5000
    while not HasModelLoaded(plan.model) and GetGameTimer()<deadline do Wait(0) end
    if not HasModelLoaded(plan.model) then return false end
    SetPlayerModel(PlayerId(),plan.model)
    SetModelAsNoLongerNeeded(plan.model)
    return true
end

-- Tras una aparicion confirmada: la apariencia actual pasa a ser la referencia sin guardarla de nuevo.
function Appearance.settled(plan)
    Appearance.locked=plan.locked
    Appearance.last=Appearance.signature(Appearance.capture(PlayerPedId()))
    Appearance.ready=true
    if plan.locked then
        OSDevtools.Notify('Tu modelo guardado no esta disponible; se conservan sus datos. Usa /guardarropa para sustituirlos por el aspecto actual.','warning')
    end
end

-- Apariencia importada por un administrador: se aplica en el sitio, sin reaparecer.
RegisterNetEvent('osdev:applyAppearance',function(data)
    if source~=65535 or type(data)~='table' then return end
    CreateThread(function()
        while Appearance.spawning do Wait(250) end
        local plan=Appearance.plan(data)
        if plan.locked or not Appearance.setModel(plan) then
            OSDevtools.Notify('El modelo importado no esta disponible en este cliente; datos conservados en el servidor.','error')
            return
        end
        Appearance.apply(PlayerPedId(),plan)
        Appearance.settled(plan)
    end)
end)

RegisterCommand('guardarropa',function()
    local data=Appearance.capture(PlayerPedId())
    if not data then return end
    Appearance.locked=false
    Appearance.last=Appearance.signature(data)
    TriggerServerEvent('osdev:saveAppearance',data,true)
end,false)

CreateThread(function()
    while true do
        Wait(10000)
        local ped=PlayerPedId()
        if Appearance.ready and not Appearance.locked and not Appearance.spawning and not Appearance.designing and DoesEntityExist(ped) and not IsEntityDead(ped) then
            local data=Appearance.capture(ped)
            local signature=Appearance.signature(data)
            if data and signature~=Appearance.last then
                Appearance.last=signature
                TriggerServerEvent('osdev:saveAppearance',data,false)
            end
        end
    end
end)
