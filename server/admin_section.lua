-- Secciones de os_devtools para el panel y la consola de os_admin (opcional: sin os_admin no hace nada).
-- os_admin filtra por el ACE osdev.admin; cada handler vuelve a comprobar el permiso concreto con la
-- autorizacion propia de os_devtools (ACE o delegacion de txAdmin).
OSDevtools.AdminSections = {}

local function done(ok, err, detail)
    if ok then return { ok = true, message = 'Operacion persistida' .. (detail and (': ' .. detail) or '') .. '.' } end
    return { ok = false, message = err or 'Operacion rechazada.' }
end

function OSDevtools.AdminSections.characters(options)
    local core, can = options.core, options.can
    local function denied(source, permission)
        if can(source, permission) then return nil end
        return { ok = false, message = 'Sin autorizacion efectiva ' .. permission .. '.' }
    end
    local player = { id = 'jugador', label = 'Jugador', type = 'player' }
    return {
        id = 'personajes', label = 'Personajes', order = 20,
        actions = {
            { id = 'ver', label = 'Ver personaje activo', ace = 'osdev.admin', fields = { player },
              description = 'Personaje, dinero, empleo, servicio y ultima posicion guardada.',
              handler = function(source, values)
                  local blocked = denied(source, 'osdev.inspect'); if blocked then return blocked end
                  local alias, err = core.ensure(values.jugador)
                  local snapshot = core.snapshot()
                  local c = alias and snapshot and snapshot.characters[alias]
                  if not c then return { ok = false, message = err or 'Sin personaje activo.' } end
                  local p = c.lastValidPosition
                  return { ok = true, message = ('Jugador %d: %s.'):format(values.jugador, alias),
                      columns = { 'Campo', 'Valor' }, rows = {
                          { 'Personaje', alias }, { 'ID', c.id }, { 'Efectivo', '$' .. (c.cash or 0) }, { 'Banco', '$' .. (c.bank or 0) },
                          { 'Empleo', (c.job or '-') .. ' / ' .. (c.rank or '-') }, { 'De servicio', c.duty and 'Si' or 'No' },
                          { 'Ultima posicion', p and ('%.1f %.1f %.1f (bucket %d)'):format(p.x, p.y, p.z, p.bucket) or '-' } } }
              end },
            { id = 'lista', label = 'Todos los personajes', ace = 'osdev.admin', description = 'Personajes registrados y si estan conectados.',
              handler = function(source)
                  local blocked = denied(source, 'osdev.inspect'); if blocked then return blocked end
                  local snapshot = core.snapshot(); if not snapshot then return { ok = false, message = 'Registro no disponible.' } end
                  local rows = {}
                  for alias, c in pairs(snapshot.characters) do
                      local found = core.find('alias:' .. alias)
                      rows[#rows + 1] = { alias, c.id, '$' .. (c.cash or 0), '$' .. (c.bank or 0), (c.job or '-') .. '/' .. (c.rank or '-'),
                          found and found.connected and ('ID ' .. found.source) or '-' }
                  end
                  table.sort(rows, function(a, b) return a[1] < b[1] end)
                  return { ok = true, message = ('%d personajes.'):format(#rows), columns = { 'Alias', 'ID', 'Efectivo', 'Banco', 'Empleo', 'Conectado' }, rows = rows }
              end },
            { id = 'cambiar', label = 'Cambiar personaje de un jugador', ace = 'osdev.admin', confirm = true,
              fields = { player, { id = 'personaje', label = 'Personaje (alias o char:ID)', type = 'text', max = 64 } },
              handler = function(source, values)
                  local blocked = denied(source, 'osdev.identity'); if blocked then return blocked end
                  local ok, err = core.select(source, values.jugador, values.personaje, false)
                  return done(ok, err, values.personaje .. ' para el jugador ' .. values.jugador)
              end },
            { id = 'crear', label = 'Crear personaje', ace = 'osdev.admin',
              fields = { player, { id = 'alias', label = 'Alias', type = 'text', max = 40 } },
              handler = function(source, values)
                  local blocked = denied(source, 'osdev.identity'); if blocked then return blocked end
                  local ok, err = core.createCharacter(source, values.jugador, values.alias)
                  return done(ok, err, values.alias)
              end },
            { id = 'guardar_posicion', label = 'Guardar posicion ahora', ace = 'osdev.admin', fields = { player },
              handler = function(source, values)
                  local blocked = denied(source, 'osdev.identity'); if blocked then return blocked end
                  core.ensure(values.jugador)
                  local ok, err = core.savePositions({ values.jugador }, 'manual', true)
                  return done(ok, err)
              end },
            { id = 'spawn', label = 'Fijar su spawn en tu posicion', ace = 'osdev.admin', self = true, fields = { player },
              description = 'La proxima aparicion del personaje sera donde estas tu ahora.',
              handler = function(source, values)
                  local blocked = denied(source, 'osdev.assets'); if blocked then return blocked end
                  local ok, err = core.setSpawn(source, tostring(values.jugador))
                  return done(ok, err)
              end }
        }
    }
end

-- Economia y empleos: reutilizan los comandos existentes (misma validacion, permisos y auditoria).
local DESTINO = { id = 'destino', label = 'Jugador o personaje (ID o alias)', type = 'text', max = 64 }
local CUENTA = { id = 'cuenta', label = 'Cuenta', type = 'select', options = { { value = 'cash', label = 'Efectivo' }, { value = 'bank', label = 'Banco' } } }

function OSDevtools.AdminSections.economy(options)
    local run = options.run
    local function money(command)
        return function(source, values) return run(source, command, { values.destino, tostring(values.cantidad), values.cuenta }) end
    end
    return {
        id = 'economia', label = 'Economia y empleos', order = 30,
        actions = {
            { id = 'dar', label = 'Dar dinero', ace = 'osdev.admin', fields = { DESTINO, { id = 'cantidad', label = 'Cantidad', type = 'number', integer = true, min = 1, max = 2147483647 }, CUENTA }, handler = money('givemoney') },
            { id = 'quitar', label = 'Quitar dinero', ace = 'osdev.admin', fields = { DESTINO, { id = 'cantidad', label = 'Cantidad', type = 'number', integer = true, min = 1, max = 2147483647 }, CUENTA }, handler = money('removemoney') },
            { id = 'fijar', label = 'Fijar saldo', ace = 'osdev.admin', confirm = true, fields = { DESTINO, { id = 'cantidad', label = 'Saldo', type = 'number', integer = true, min = 0, max = 2147483647 }, CUENTA }, handler = money('setmoney') },
            { id = 'empleo', label = 'Asignar empleo', ace = 'osdev.admin', description = 'Deja al personaje fuera de servicio.',
              fields = { DESTINO, { id = 'empleo', label = 'Empleo (p. ej. gruppe6)', type = 'text', max = 40 }, { id = 'rango', label = 'Rango (p. ej. tecnico)', type = 'text', max = 40 } },
              handler = function(source, values) return run(source, 'setjob', { values.destino, values.empleo, values.rango }) end },
            { id = 'servicio', label = 'Entrar o salir de servicio', ace = 'osdev.admin',
              fields = { DESTINO, { id = 'estado', label = 'De servicio', type = 'boolean', default = true } },
              handler = function(source, values) return run(source, 'setduty', { values.destino, values.estado and 'on' or 'off' }) end },
            { id = 'bienes', label = 'Ver dinero y bienes', ace = 'osdev.admin', fields = { DESTINO },
              handler = function(source, values) return run(source, 'verpropiedades', { values.destino }) end }
        }
    }
end

-- Propiedades, negocios, vehiculos y mundo.
function OSDevtools.AdminSections.assets(options)
    local run = options.run
    local kinds = {}
    for key, kind in pairs(OSDevtools.BusinessTypes) do kinds[#kinds + 1] = { value = key, label = kind.label } end
    table.sort(kinds, function(a, b) return a.label < b.label end)
    local category = { id = 'categoria', label = 'Categoria', type = 'select', options = {
        { value = 'properties', label = 'Propiedades' }, { value = 'businesses', label = 'Negocios' }, { value = 'vehicles', label = 'Vehiculos' } } }
    local commandFor = {
        list = { properties = 'listpropiedades', businesses = 'listnegocios', vehicles = 'listvehiculos' },
        info = { properties = 'infopropiedad', businesses = 'infonegocio', vehicles = 'infovehiculo' },
        assign = { properties = 'setpropiedad', businesses = 'setnegocio', vehicles = 'setvehiculo' }
    }
    local id = { id = 'id', label = 'ID', type = 'number', integer = true, min = 1, max = 2147483646 }
    local color = function(field, label, required) return { id = field, label = label, type = 'number', integer = true, min = 0, max = 159, required = required } end
    return {
        id = 'bienes', label = 'Bienes y mundo', order = 40,
        actions = {
            { id = 'lista', label = 'Listar bienes', ace = 'osdev.admin', fields = { category },
              handler = function(source, values) return run(source, commandFor.list[values.categoria], {}) end },
            { id = 'info', label = 'Detalle de un bien', ace = 'osdev.admin', fields = { category, id },
              handler = function(source, values) return run(source, commandFor.info[values.categoria], { tostring(values.id) }) end },
            { id = 'asignar', label = 'Asignar propietario', ace = 'osdev.admin', fields = { category, id, DESTINO },
              handler = function(source, values) return run(source, commandFor.assign[values.categoria], { tostring(values.id), values.destino }) end },
            { id = 'propiedad', label = 'Crear propiedad aqui', ace = 'osdev.admin', self = true, description = 'En tu posicion, sin propietario; aparece su blip.',
              fields = { { id = 'numero', label = 'Numero', type = 'number', integer = true, min = 1, max = 2147483646 }, { id = 'precio', label = 'Precio', type = 'number', integer = true, min = 0, max = 2147483647 } },
              handler = function(source, values) return run(source, 'crearpropiedad', { tostring(values.numero), tostring(values.precio) }) end },
            { id = 'negocio', label = 'Crear negocio aqui', ace = 'osdev.admin', self = true, description = 'En tu posicion, sin propietario; blip segun el tipo.',
              fields = { { id = 'tipo', label = 'Tipo', type = 'select', options = kinds }, { id = 'nombre', label = 'Nombre', type = 'text', min = 3, max = 40 },
                  { id = 'precio', label = 'Precio', type = 'number', integer = true, min = 0, max = 2147483647 } },
              handler = function(source, values) return run(source, 'crearnegocio', { values.tipo, values.nombre, tostring(values.precio) }) end },
            { id = 'vehiculo', label = 'Crear vehiculo delante', ace = 'osdev.admin', self = true,
              fields = { { id = 'modelo', label = 'Modelo (p. ej. sultan)', type = 'text', max = 50 }, color('primario', 'Color primario 0-159'),
                  color('secundario', 'Color secundario', false),
                  { id = 'modo', label = 'Modo', type = 'select', options = { { value = 'temporal', label = 'Temporal' }, { value = 'fijo', label = 'Fijo (persistente)' } } },
                  { id = 'propietario', label = 'Propietario (ID o alias)', type = 'text', max = 64, required = false } },
              handler = function(source, values)
                  local args = { values.modelo, tostring(values.primario) }
                  if values.secundario then args[#args + 1] = tostring(values.secundario) end
                  args[#args + 1] = values.modo
                  if values.propietario then args[#args + 1] = values.propietario end
                  return run(source, 'crearvehiculo', args)
              end },
            { id = 'recuperar', label = 'Recuperar vehiculo delante', ace = 'osdev.admin', self = true, fields = { id },
              handler = function(source, values) return run(source, 'recuperarvehiculo', { tostring(values.id) }) end },
            { id = 'policia', label = 'Policia NPC', ace = 'osdev.admin', fields = { { id = 'estado', label = 'Activada', type = 'boolean', default = false } },
              handler = function(source, values) return run(source, 'policianpc', { values.estado and 'on' or 'off' }) end },
            { id = 'trafico', label = 'Peatones y trafico', ace = 'osdev.admin', fields = { { id = 'estado', label = 'Activados', type = 'boolean', default = true } },
              handler = function(source, values) return run(source, 'npcs', { values.estado and 'on' or 'off' }) end }
        }
    }
end

-- Registra (o vuelve a registrar) las secciones si os_admin esta iniciado.
function OSDevtools.AdminSections.publish(options)
    -- 'starting': os_admin avisa con os_admin:ready mientras termina de arrancar.
    local state = GetResourceState('os_admin')
    if state ~= 'started' and state ~= 'starting' then return end
    for _, build in ipairs({ OSDevtools.AdminSections.characters, OSDevtools.AdminSections.economy, OSDevtools.AdminSections.assets }) do
        local ok, err = pcall(function() return exports.os_admin:RegisterSection(build(options)) end)
        if not ok then print('[os_devtools] No se pudo registrar una seccion de administracion: ' .. tostring(err)) end
    end
end
