-- Identidad de autorizacion, independiente de aliases y del almacenamiento RP.
OSDevtools.AuthIdentity={}
function OSDevtools.AuthIdentity.valid(value)
    if type(value)~='string' then return false end
    local kind,id=value:match('^([%w]+):(.+)$')
    if kind=='license' or kind=='license2' then return #id==40 and id:match('^[a-f0-9]+$')~=nil end
    return kind=='fivem' and #id<=20 and id:match('^[1-9]%d*$')~=nil
end
function OSDevtools.AuthIdentity.resolve(source)
    if not OSDevtools.Util.integer(source,1,2147483647) or not GetPlayerName(source) then return nil end
    local identifiers={}
    for _,identifier in ipairs(GetPlayerIdentifiers(source) or {}) do
        if OSDevtools.AuthIdentity.valid(identifier) then
            local kind=identifier:match('^([^:]+):')
            if identifiers[kind] and identifiers[kind]~=identifier then return nil end
            identifiers[kind]=identifier
        end
    end
    return identifiers.license or identifiers.license2 or identifiers.fivem
end
function OSDevtools.AuthIdentity.mask(value)
    if not OSDevtools.AuthIdentity.valid(value) then return 'no disponible' end
    local kind,id=value:match('^([^:]+):(.+)$')
    return kind..':'..(#id>12 and id:sub(1,4)..'…'..id:sub(-4) or '…'..id:sub(-2))
end
