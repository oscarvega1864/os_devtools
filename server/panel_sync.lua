-- Envio de bienes y auditoria a la web del panel (os_admin -> os_panel). Logica pura: diff entre lo ultimo
-- enviado y el estado actual. Las facciones son negocios de tipo 'faccion' y van en su propia categoria.
OSDevtools = OSDevtools or {}
OSDevtools.PanelSync = {}
local M = OSDevtools.PanelSync

local SOURCES = { { 'properties', 'properties' }, { 'businesses', 'businesses' }, { 'vehicles', 'vehicles' } }
local function round(v) return type(v) == 'number' and math.floor(v * 100 + 0.5) / 100 or nil end

-- Payload de un bien (lo que se ve en la web). label(category, id, record) viene de server.lua.
function M.payload(category, id, record, label)
    local pos = type(record.position) == 'table' and record.position or {}
    local out = { category = category, id = math.tointeger(tonumber(id)), label = tostring(label(category == 'factions' and 'businesses' or category, id, record)):sub(1, 96),
        owner = type(record.owner) == 'string' and record.owner or nil, price = math.tointeger(record.price), job = type(record.job) == 'string' and record.job or nil,
        plate = type(record.plate) == 'string' and record.plate or nil, x = round(pos.x), y = round(pos.y), z = round(pos.z),
        extra = { type = record.type, model = record.model, fixed = record.fixed, fleet = record.fleet } }
    -- Plantilla del negocio o faccion: quien esta contratado y con que rango.
    if type(record.staff) == 'table' then
        local staff, keyParts = {}, {}
        for alias, rank in pairs(record.staff) do staff[#staff + 1] = { alias = tostring(alias), rank = tostring(rank) } end
        table.sort(staff, function(a, b) return a.alias < b.alias end)
        for _, m in ipairs(staff) do keyParts[#keyParts + 1] = m.alias .. '=' .. m.rank end
        out.extra.staff, out.extra.staffKey = staff, table.concat(keyParts, ',')
    end
    return out
end
local function key(p) return p.category .. ':' .. tostring(p.id) end
local function same(a, b)
    if not a then return false end
    for _, field in ipairs({ 'label', 'owner', 'price', 'job', 'plate', 'x', 'y', 'z' }) do if a[field] ~= b[field] then return false end end
    for _, field in ipairs({ 'type', 'model', 'fixed', 'fleet', 'staffKey' }) do if a.extra[field] ~= b.extra[field] then return false end end
    return true
end

-- Devuelve la lista de cambios (altas/cambios y bajas) y el nuevo "ultimo enviado".
function M.diff(state, last, label)
    local current, changes = {}, {}
    for _, source in ipairs(SOURCES) do
        for id, record in pairs(state[source[1]] or {}) do
            local category = source[2] == 'businesses' and record.type == 'faccion' and 'factions' or source[2]
            local p = M.payload(category, id, record, label)
            if p.id then current[key(p)] = p end
        end
    end
    for k, p in pairs(current) do if not same(last[k], p) then changes[#changes + 1] = p end end
    for k, p in pairs(last) do if not current[k] then changes[#changes + 1] = { category = p.category, id = p.id, label = p.label, deleted = true } end end
    table.sort(changes, function(a, b) return key(a) < key(b) end)
    return changes, current
end

-- Entradas de auditoria nuevas desde la ultima enviada (la auditoria es una ventana deslizante de 300).
function M.newAudit(audit, marker)
    local function sig(e) return ('%s|%s|%s'):format(tostring(e.time), tostring(e.actor), tostring(e.operation)) end
    if #audit == 0 then return {}, marker end
    local start = 1
    if marker then
        for i = #audit, 1, -1 do if sig(audit[i]) == marker then start = i + 1; break end end
    else
        return {}, sig(audit[#audit]) -- primer arranque: no se reenvia el historial
    end
    local list = {}
    for i = start, #audit do list[#list + 1] = audit[i] end
    return list, sig(audit[#audit])
end

-- Personajes: ID numerico propio (distinto del ID de usuario de la web), cuenta, dinero, trabajo y estado.
local CHAR_FIELDS = { 'ref', 'alias', 'account', 'cash', 'bank', 'job', 'rank', 'duty', 'life' }
function M.characterPayload(alias, c)
    return { id = math.tointeger(tonumber(tostring(c.id or ''):match('(%d+)$'))), ref = c.id, alias = alias, account = c.account,
        cash = math.tointeger(c.cash) or 0, bank = math.tointeger(c.bank) or 0, job = c.job, rank = c.rank, duty = c.duty == true, life = c.life }
end
function M.characters(state, last)
    local current, changes = {}, {}
    for alias, c in pairs(state.characters or {}) do
        local p = M.characterPayload(alias, c)
        if p.id then current[alias] = p end
    end
    for alias, p in pairs(current) do
        local was = last[alias]
        local differs = not was
        if was then for _, f in ipairs(CHAR_FIELDS) do if was[f] ~= p[f] then differs = true; break end end end
        if differs then changes[#changes + 1] = p end
    end
    for alias, p in pairs(last) do if not current[alias] then changes[#changes + 1] = { id = p.id, alias = alias, deleted = true } end end
    table.sort(changes, function(a, b) return a.id < b.id end)
    return changes, current
end
