function OSDevtools.bindCore(options)
    local core,reply,guard=options.core,options.reply,options.guard
    local list=options.list or reply -- listados: siempre al chat
    local resource=GetCurrentResourceName()
    local appearanceAt,appearanceHold={},{} -- limite de guardado y bloqueo tras importar, por jugador
    local function identityGuard(source) return guard(source,'osdev.identity') end
    local function result(source,ok,err,detail) reply(source,ok and ('Operacion persistida'..(detail and ': '..detail or '')..'.') or (err or 'Operacion rechazada.'),ok and 'success' or 'error') end
    local function label(value)
        local dto=core.find(value);return dto and (dto.alias..' ['..dto.characterId..']') or tostring(value)
    end
    RegisterCommand('crearpersonaje',function(source,args)
        if not identityGuard(source) then return end
        if #args~=2 then return reply(source,'Uso: /crearpersonaje <idJugador> <alias>') end
        local ok,err=core.createCharacter(source,tonumber(args[1]),args[2]);result(source,ok,err,label('alias:'..args[2]))
    end,false)
    RegisterCommand('seleccionarpersonaje',function(source,args)
        if not identityGuard(source) then return end
        if #args~=2 then return reply(source,'Uso: /seleccionarpersonaje <idJugador> <alias|char:id>') end
        local ok,err=core.select(source,tonumber(args[1]),args[2],false);result(source,ok,err,label(args[2]))
    end,false)
    RegisterCommand('vincularpersonaje',function(source,args)
        if not identityGuard(source) then return end
        if #args~=3 or args[3]~='CONFIRMAR' then return reply(source,'Uso: /vincularpersonaje <idJugador> <alias|char:id> CONFIRMAR') end
        local ok,err=core.select(source,tonumber(args[1]),args[2],true);result(source,ok,err,label(args[2]))
    end,false)
    RegisterCommand('personaje',function(source,args)
        if source==0 then return reply(source,'Comando personal dentro del juego.') end
        if #args==0 then
            local account,err=core.account(source);local snapshot=core.snapshot()
            if not account or not snapshot then return reply(source,err or 'Identidad no disponible.') end
            local names={}
            for alias,c in pairs(snapshot.characters) do if c.account==account then names[#names+1]=alias..' ['..c.id..']' end end
            table.sort(names);return list(source,#names>0 and table.concat(names,' | ') or 'Sin personajes propios.')
        end
        local ok,err=core.select(source,source,args[1],false);result(source,ok,err,label(args[1]))
    end,false)
    RegisterCommand('guardarpos',function(source)
        if source==0 then return end
        core.ensure(source);result(source,core.savePositions({source},'manual',true))
    end,false)
    RegisterCommand('ultimaubicacion',function(source)
        if source==0 then return end
        local alias,err=core.ensure(source);local snapshot=core.snapshot();local c=alias and snapshot and snapshot.characters[alias]
        if not c then return reply(source,err or 'Identidad no disponible.') end
        for _,field in ipairs({'lastValidPosition','lastLogoutPosition','lastDeathPosition'}) do
            local p=c[field]
            list(source,p and ('%s: %.4f %.4f %.4f h=%.2f bucket=%d fecha=%d motivo=%s'):format(field,p.x,p.y,p.z,p.h,p.bucket,p.at,p.reason) or (field..': sin registro'))
        end
    end,false)
    -- importarropa <destinatario> <archivo>: XML de Menyoo en data/<archivo>.xml (carpeta fuera de Git).
    RegisterCommand('importarropa',function(source,args)
        if not identityGuard(source) then return end
        local file=args[2] and args[2]:gsub('%.xml$','')
        if #args~=2 or not file:match('^[%w_%-]+$') or #file>64 then return reply(source,'Uso: importarropa <idJugador|alias|char:id> <archivo> (XML de Menyoo en data/<archivo>.xml)') end
        local text=LoadResourceFile(resource,'data/'..file..'.xml')
        if not text then return reply(source,'No existe data/'..file..'.xml en os_devtools.','error') end
        if not OSDevtools.AppearanceXml then return reply(source,'Lector XML no cargado: reinicia el servidor completo para que FiveM relea fxmanifest.lua.','error') end
        local appearance,detail=OSDevtools.AppearanceXml.parse(text)
        if not appearance then return reply(source,detail,'error') end
        local ok,alias=core.importAppearance(source,args[1],appearance)
        if not ok then return reply(source,alias or 'Importacion rechazada.','error') end
        for _,player in ipairs(core.sourcesOf(alias)) do
            appearanceHold[player]=GetGameTimer()+15000
            TriggerClientEvent('osdev:applyAppearance',player,appearance)
        end
        reply(source,'Apariencia importada en '..label('alias:'..alias)..(detail and (' (no incluye: '..detail..')') or '')..'.','success')
    end,false)
    RegisterCommand('setspawn',function(source,args)
        if not guard(source,'osdev.assets') then return end
        local ok,err=core.setSpawn(source,args[1]);result(source,ok,err,label(args[1]))
    end,false)
    RegisterCommand('tpusuario',function(source,args)
        if not guard(source,'osdev.assets') then return end
        local target=tonumber(args[1]);local point=target and GetPlayerName(target) and core.position(target)
        local ped=source>0 and GetPlayerPed(source) or 0
        if not point or ped==0 or not DoesEntityExist(ped) then return reply(source,'Uso dentro del juego: /tpusuario <idJugadorConectado>; posicion y bucket autorizados.') end
        local saved,err=core.change(source,'tpusuario '..target,function() return true end)
        if not saved then return reply(source,err,'error') end
        SetPlayerRoutingBucket(source,point.bucket);SetEntityCoords(ped,point.x+1,point.y,point.z,false,false,false,false)
        reply(source,'Administrador desplazado al jugador '..target..'.','success')
    end,false)
    local requested={}
    AddEventHandler('onResourceStart',function(name) if name=='spawnmanager' then requested={} end end)
    local function spawnOnConnect(player)
        if requested[player] then return end
        local alias,err=core.ensure(player)
        if not alias then return reply(player,err or 'Identidad no disponible.') end
        requested[player]=true;core.requestSpawn(player,'connect')
    end
    RegisterNetEvent('osdev:requestCharacterSpawn',function()
        local player=source
        if not OSDevtools.Util.integer(player,1,2147483647) then return end
        spawnOnConnect(player)
    end)
    -- Selector de personaje (NUI). El cliente solo envia un alias o un nombre; la cuenta,
    -- la propiedad del personaje y la posicion de aparicion se deciden aqui.
    local selectAt={}
    local function selectSettings() return OSDevtools.CoreConfig.CharacterSelect or {} end
    local function throttled(player)
        local now=GetGameTimer();local last=selectAt[player]
        if last and now>=last and now-last<(selectSettings().RequestMilliseconds or 1000) then return true end
        selectAt[player]=now;return false
    end
    local function sendRoster(player,mode,message)
        local rows,err=core.roster(player)
        if not rows then return reply(player,err or 'Identidad no disponible.','error') end
        local settings=selectSettings()
        TriggerClientEvent('osdev:characterSelect',player,{mode=mode,characters=rows,allowCreate=settings.AllowCreate==true,
            maxCharacters=settings.MaxCharacters or 1,message=message})
    end
    RegisterNetEvent('osdev:requestCharacterSelect',function()
        local player=source
        if not OSDevtools.Util.integer(player,1,2147483647) or throttled(player) then return end
        if not selectSettings().Enabled or core.hasSpawned(player) then return spawnOnConnect(player) end
        if core.isSelecting(player) then return sendRoster(player,'connect') end
        -- Crea la identidad automatica de un jugador nuevo (si procede) antes de listar.
        core.ensure(player)
        local ok,err=core.beginSelection(player)
        if not ok then
            if err=='already_spawned' or err=='spawn_in_progress' then return end
            return reply(player,err or 'Identidad no disponible.','error')
        end
        sendRoster(player,'connect')
    end)
    local function selectResult(player,ok,message)
        TriggerClientEvent('osdev:characterSelectResult',player,{ok=ok==true,message=message})
    end
    RegisterNetEvent('osdev:chooseCharacter',function(alias)
        local player=source
        if not OSDevtools.Util.integer(player,1,2147483647) or type(alias)~='string' or #alias>40 then return end
        if throttled(player) then return selectResult(player,false,'Demasiado rapido; vuelve a intentarlo.') end
        if core.isSelecting(player) then
            local ok,err=core.choose(player,alias)
            if ok then requested[player]=true end -- la aparicion de entrada ya esta en marcha
            return selectResult(player,ok,ok and nil or err)
        end
        if not core.hasSpawned(player) then return selectResult(player,false,'Aun no has entrado al servidor.') end
        local ok,err=core.select(player,player,'alias:'..alias,false)
        selectResult(player,ok,ok and nil or err)
        if ok then reply(player,'Ahora juegas como '..label('alias:'..alias)..'.','success') end
    end)
    RegisterNetEvent('osdev:createOwnCharacter',function(first,last)
        local player=source
        if not OSDevtools.Util.integer(player,1,2147483647) then return end
        if not core.isSelecting(player) and not core.hasSpawned(player) then return end
        if throttled(player) then return selectResult(player,false,'Demasiado rapido; vuelve a intentarlo.') end
        local ok,result,switchError=core.createOwn(player,first,last)
        if not ok then return selectResult(player,false,result) end
        if switchError then -- creado, pero no se pudo entrar con el: se muestra en la lista
            return sendRoster(player,core.isSelecting(player) and 'connect' or 'switch','Personaje '..result..' creado; no se pudo entrar con el: '..switchError)
        end
        if not core.hasSpawned(player) then requested[player]=true end -- la aparicion de entrada ya esta en marcha
        selectResult(player,true)
        reply(player,'Personaje '..label('alias:'..result)..' creado.'..(selectSettings().DesignWithoutAppearance and ' Disena su aspecto.' or ''),'success')
    end)
    RegisterCommand('personajes',function(source)
        if source==0 then return reply(source,'Comando personal dentro del juego.') end
        if not selectSettings().Enabled then return reply(source,'El selector de personajes esta desactivado; usa /personaje.') end
        if core.isSelecting(source) then return sendRoster(source,'connect') end
        if not core.hasSpawned(source) then return reply(source,'Espera a terminar de aparecer.','warning') end
        sendRoster(source,'switch')
    end,false)
    RegisterNetEvent('osdev:characterSpawned',function(token) core.spawnAck(source,token) end)
    RegisterNetEvent('osdev:spawnFailed',function(token) core.spawnFailed(source,token) end)
    RegisterNetEvent('osdev:deathObserved',function() core.observe(source) end)
    -- Apariencia: guardado automatico (solo si cambia) y manual con /guardarropa.
    RegisterNetEvent('osdev:saveAppearance',function(appearance,manual)
        local player=source
        if not OSDevtools.Util.integer(player,1,2147483647) then return end
        manual=manual==true
        local now=GetGameTimer();local last=appearanceAt[player]
        -- Tras una importacion, un guardado automatico en vuelo no puede pisar lo importado.
        if not manual and appearanceHold[player] and now<appearanceHold[player] then return end
        if last and now>=last and now-last<(manual and 2000 or OSDevtools.CoreConfig.AppearanceMinMilliseconds) then
            if manual then reply(player,'Espera unos segundos antes de volver a guardar la ropa.','warning') end
            return
        end
        appearanceAt[player]=now
        local ok,detail=core.saveAppearance(player,appearance)
        if manual then reply(player,ok and (detail=='unchanged' and 'Ropa y aspecto ya estaban guardados.' or 'Ropa y aspecto guardados en tu personaje.') or detail,ok and 'success' or 'error')
        elseif not ok then print(('[os_devtools] apariencia no guardada para %d: %s'):format(player,tostring(detail))) end
    end)
    AddEventHandler('playerJoining',function()
        local player=tonumber(source)
        SetTimeout(500,function() if GetPlayerName(player) then local alias,err=core.ensure(player);if not alias then reply(player,err,'error') end end end)
    end)
    AddEventHandler('playerDropped',function()
        local player=tonumber(source);core.drop(player);requested[player]=nil;appearanceAt[player]=nil;appearanceHold[player]=nil;selectAt[player]=nil
    end)
    local function checkpoint(reason)
        local sources={};for _,id in ipairs(GetPlayers()) do sources[#sources+1]=tonumber(id) end
        core.savePositions(sources,reason,true)
    end
    AddEventHandler('onResourceStop',function(name) if name==resource then checkpoint('resource_stop') end end)
    AddEventHandler('txAdmin:events:serverShuttingDown',function() checkpoint('server_shutdown') end)
    CreateThread(function()
        while true do
            Wait(OSDevtools.CoreConfig.MonitorMilliseconds)
            for _,id in ipairs(GetPlayers()) do core.observe(tonumber(id)) end
        end
    end)
    CreateThread(function()
        while true do
            Wait(OSDevtools.CoreConfig.PositionSeconds*1000)
            local sources={};for _,id in ipairs(GetPlayers()) do sources[#sources+1]=tonumber(id) end
            core.savePositions(sources,'periodic',false)
        end
    end)
    local function reader()
        local caller=GetInvokingResource()
        return caller==nil or caller==resource or OSDevtools.CoreConfig.IdentityReaders[caller]==true
    end
    exports('GetActiveCharacter',function(player) if not reader() then return nil,'resource_not_authorized' end;return core.dto(player) end)
    exports('GetActiveEmployment',function(player) if not reader() then return nil,'resource_not_authorized' end;return core.employment(player) end)
    exports('ResolveCharacter',function(value) if not reader() then return nil,'resource_not_authorized' end;return core.find(value) end)
    exports('GetIdentityStatus',function() return {ready=core.status(),version='0.1.5',provider='os_devtools'} end)
    -- Ingreso de un recurso de trabajo autorizado (Payers) al personaje activo; queda en la auditoria.
    exports('PayCharacter',function(player,amount,account,reason)
        local caller=GetInvokingResource()
        if not caller or not OSDevtools.CoreConfig.Payers[caller] then return false,'resource_not_authorized' end
        local n=math.tointeger(tonumber(amount));account=account or 'bank'
        if not n or n<=0 or n>OSDevtools.CoreConfig.MaxPayment or (account~='bank' and account~='cash') then return false,'invalid_amount' end
        local alias,err=core.ensure(player);if not alias then return false,err end
        local label=('pay %s %s %s %d %s'):format(caller,alias,account,n,tostring(reason or ''):gsub('[^%w_%-]',''):sub(1,40))
        local ok,why=core.change(player,label,function(d)
            local c=d.characters[alias];if not c then return false,'Personaje no encontrado.' end
            if c[account]+n>2147483647 then return false,'Saldo fuera de rango.' end
            c[account]=c[account]+n;return true
        end)
        return ok==true,ok and nil or why
    end)
    -- Cobro de un recurso autorizado (Chargers, p. ej. la tienda de os_security) al personaje activo.
    -- Falla sin tocar nada si no hay saldo suficiente en esa cuenta; queda en la auditoria.
    exports('ChargeCharacter',function(player,amount,account,reason)
        local caller=GetInvokingResource()
        if not caller or not OSDevtools.CoreConfig.Chargers[caller] then return false,'resource_not_authorized' end
        local n=math.tointeger(tonumber(amount));account=account or 'bank'
        if not n or n<=0 or n>OSDevtools.CoreConfig.MaxCharge or (account~='bank' and account~='cash') then return false,'invalid_amount' end
        local alias,err=core.ensure(player);if not alias then return false,err end
        local label=('charge %s %s %s %d %s'):format(caller,alias,account,n,tostring(reason or ''):gsub('[^%w_%-]',''):sub(1,40))
        local ok,why=core.change(player,label,function(d)
            local c=d.characters[alias];if not c then return false,'Personaje no encontrado.' end
            if (tonumber(c[account]) or 0)<n then return false,'insufficient_funds' end
            c[account]=c[account]-n;return true
        end)
        return ok==true,ok and nil or why
    end)
    -- Saldo del personaje activo (solo lectura) para recursos lectores.
    exports('GetCharacterBalance',function(player)
        if not reader() then return nil,'resource_not_authorized' end
        return core.balance(player)
    end)
    -- Pantalla de carga: el jugador aun conecta (id temporal), por eso se leen sus identificadores.
    exports('GetLoadingPreview',function(player)
        if not reader() or not tonumber(player) then return nil end
        return core.preview(GetPlayerIdentifiers(player))
    end)
    exports('GetCharacterSpawn',function(player) if reader() then return core.spawnSelection(player) end end)
    -- Compatibilidad con el inventario pretest; el contrato nuevo es GetActiveCharacter.
    exports('GetCharacterId',function(player) if reader() then return core.ensure(player) end end)
    exports('GetCharacterByAlias',function(alias)
        if not reader() or type(alias)~='string' then return nil end
        local found=core.find('alias:'..alias);return found and found.alias or nil
    end)
    -- Proveedor bancario (Bankers): fichas por ID persistente, busqueda y movimientos de saldo.
    -- Todo cambio pasa por core.change y queda en la auditoria con el recurso que lo pidio.
    local function banker()
        local caller=GetInvokingResource()
        return caller~=nil and OSDevtools.CoreConfig.Bankers[caller]==true,caller
    end
    local function bankSheet(alias)
        local sheet=core.sheet(alias);if not sheet then return nil end
        local found=core.find('alias:'..alias)
        sheet.connected=found~=nil and found.connected==true;sheet.source=found and found.source or nil
        return sheet
    end
    local function aliasOf(characterId)
        if type(characterId)~='string' or not characterId:match('^oschar_%d+$') then return nil end
        return (core.resolve('char:'..characterId))
    end
    exports('BankGetCharacter',function(player)
        if not banker() then return nil,'resource_not_authorized' end
        local alias=core.lookup(tonumber(player));return alias and bankSheet(alias) or nil
    end)
    exports('BankFindCharacter',function(characterId)
        if not banker() then return nil,'resource_not_authorized' end
        local alias=aliasOf(characterId);return alias and bankSheet(alias) or nil
    end)
    exports('BankSearch',function(query,limit)
        if not banker() or type(query)~='string' then return {} end
        local raw=query:lower()
        local needle=raw:gsub('[%s_]+',' '):gsub('^ ',''):gsub(' $','')
        if #needle<2 then return {} end
        limit=math.min(math.tointeger(tonumber(limit)) or 20,OSDevtools.CoreConfig.MaxBankSearch)
        local out={}
        for _,alias in ipairs(core.aliases()) do
            if #out>=limit then break end
            local sheet=core.sheet(alias)
            if sheet and (alias:gsub('_',' '):find(needle,1,true) or sheet.characterId:lower()==raw) then out[#out+1]=bankSheet(alias) end
        end
        return out
    end)
    exports('BankAdjust',function(characterId,account,delta,reason)
        local allowed,caller=banker();if not allowed then return false,'resource_not_authorized' end
        local n=math.tointeger(tonumber(delta))
        if not n or n==0 or math.abs(n)>OSDevtools.CoreConfig.MaxBankMove or (account~='bank' and account~='cash') then return false,'invalid_amount' end
        local alias=aliasOf(characterId);if not alias then return false,'character_not_found' end
        local label=('bank %s %s %s %+d %s'):format(caller,alias,account,n,tostring(reason or ''):gsub('[^%w_%-]',''):sub(1,40))
        local balance
        local ok,why=core.change(0,label,function(d)
            local c=d.characters[alias];if not c then return false,'character_not_found' end
            local value=(tonumber(c[account]) or 0)+n
            if value<0 then return false,'insufficient_funds' end
            if value>2147483647 then return false,'out_of_range' end
            c[account]=value;balance=value;return true
        end)
        if ok then return true,balance end
        return false,why
    end)
end
