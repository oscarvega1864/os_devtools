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

-- Registra (o vuelve a registrar) las secciones si os_admin esta iniciado.
function OSDevtools.AdminSections.publish(options)
    if GetResourceState('os_admin') ~= 'started' then return end
    local ok, err = pcall(function() return exports.os_admin:RegisterSection(OSDevtools.AdminSections.characters(options)) end)
    if not ok then print('[os_devtools] No se pudo registrar la seccion de administracion: ' .. tostring(err)) end
end
