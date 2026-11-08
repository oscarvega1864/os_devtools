-- Lector acotado de XML de Menyoo (OutfitPedData) hacia el contrato de apariencia.
-- No es un parser XML general: solo extrae las etiquetas conocidas y valida el resultado.
OSDevtools.AppearanceXml={}
local reader=OSDevtools.AppearanceXml
local PROPS={0,1,2,6,7}
-- Tipo de color por superposicion (barba, cejas y vello: pelo; colorete y labios: maquillaje).
local COLOR_TYPE={[1]=1,[2]=1,[5]=2,[8]=2,[10]=1}

local function hash(value)
    local n=value and tonumber(value)
    if not n then return nil end
    if n>2147483647 then n=n-4294967296 end
    return n
end
local function tag(text,name) return text:match('<'..name..'>%s*([^<]-)%s*</'..name..'>') end
local function int(text,name) local v=tonumber(tag(text,name) or '');return v and math.floor(v) or nil end
local function num(text,name) return tonumber(tag(text,name) or '') end
local function pairsBlock(text,name)
    local block=text:match('<'..name..'[^>]*>(.-)</'..name..'>');local result={}
    if not block then return result end
    for index,first,second in block:gmatch('<_(%d+)>%s*(%-?%d+)%s*,%s*(%-?%d+)%s*</_%d+>') do
        result[tonumber(index)]={tonumber(first),tonumber(second)}
    end
    return result
end

function reader.parse(text)
    if type(text)~='string' or #text==0 or #text>65536 or not text:find('<OutfitPedData',1,true) then return nil,'No es un XML de Menyoo (OutfitPedData).' end
    local model=hash(tag(text,'ModelHash') or tag(text,'HashName'))
    if not model or model==0 then return nil,'El XML no indica el modelo.' end
    local data={model=model,components={},props={}}
    local comps=pairsBlock(text,'PedComps')
    for component=0,11 do
        local c=comps[component] or {0,0}
        data.components[#data.components+1]={d=math.max(c[1],0),t=math.max(c[2],0),p=0}
    end
    local props=pairsBlock(text,'PedProps')
    for _,index in ipairs(PROPS) do
        local p=props[index] or {-1,-1}
        data.props[#data.props+1]={i=index,d=p[1]<0 and -1 or p[1],t=p[1]<0 and -1 or math.max(p[2],0)}
    end
    local head=text:match('<HeadFeatures[^>]*>(.-)</HeadFeatures>')
    if head then
        local tone=head:match('<ShapeAndSkinTone>(.-)</ShapeAndSkinTone>') or ''
        local blend={sf=int(tone,'ShapeFatherId'),ss=int(tone,'ShapeMotherId'),st=int(tone,'ShapeOverrideId'),
            kf=int(tone,'ToneFatherId'),ks=int(tone,'ToneMotherId'),kt=int(tone,'ToneOverrideId'),
            sm=num(tone,'ShapeVal'),km=num(tone,'ToneVal'),tm=num(tone,'OverrideVal')}
        for _,key in ipairs({'sf','ss','st','kf','ks','kt','sm','km','tm'}) do if blend[key]==nil then blend=nil;break end end
        local features={}
        local block=head:match('<FacialFeatures>(.-)</FacialFeatures>') or ''
        local found={}
        for index,value in block:gmatch('<_(%d+)>%s*([%-%d%.eE]+)%s*</_%d+>') do found[tonumber(index)]=tonumber(value) end
        for index=0,19 do features[#features+1]=found[index] or 0 end
        local overlays={}
        local list=head:match('<Overlays>(.-)</Overlays>') or ''
        local parsed={}
        for item,attributes in list:gmatch('<_(%d+)(%s[^>]*)/>') do
            local function attr(name) return tonumber(attributes:match(name..'="([^"]*)"') or '') end
            parsed[tonumber(item)]={v=attr('index'),c=attr('colour'),c2=attr('colourSecondary'),o=attr('opacity')}
        end
        for index=0,12 do
            local o=type(parsed[index])=='table' and parsed[index] or {}
            overlays[#overlays+1]={v=o.v or 255,o=o.o or 0,ct=(o.v or 255)~=255 and COLOR_TYPE[index] or 0,c=o.c or 0,c2=o.c2 or 0}
        end
        data.head={blend=blend,features=features,overlays=overlays,
            hair={c=int(head,'HairColour') or 0,h=int(head,'HairColourStreaks') or 0},eyes=int(head,'EyeColour') or 0}
    end
    local normalized=OSDevtools.State.normalizeAppearance(data)
    if not normalized then return nil,'Valores del XML fuera de rango; no se importa.' end
    local skipped=text:find('<TattooLogoDecals>%s*<',1) and 'tatuajes/logos' or nil
    return normalized,skipped
end
