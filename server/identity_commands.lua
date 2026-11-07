function OSDevtools.bindCore(options)
    local core,reply,guard=options.core,options.reply,options.guard
    local resource=GetCurrentResourceName()
    local function identityGuard(source) return guard(source,'osdev.identity') end
    local function result(source,ok,err,detail) reply(source,ok and ('Operacion persistida'..(detail and ': '..detail or '')..'.') or (err or 'Operacion rechazada.')) end
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
            table.sort(names);return reply(source,#names>0 and table.concat(names,' | ') or 'Sin personajes propios.')
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
            reply(source,p and ('%s: %.4f %.4f %.4f h=%.2f bucket=%d fecha=%d motivo=%s'):format(field,p.x,p.y,p.z,p.h,p.bucket,p.at,p.reason) or (field..': sin registro'))
        end
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
        if not saved then return reply(source,err) end
        SetPlayerRoutingBucket(source,point.bucket);SetEntityCoords(ped,point.x+1,point.y,point.z,false,false,false,false)
        reply(source,'Administrador desplazado al jugador '..target..'.')
    end,false)
    local requested={}
    AddEventHandler('onResourceStart',function(name) if name=='spawnmanager' then requested={} end end)
    RegisterNetEvent('osdev:requestCharacterSpawn',function()
        local player=source
        if not OSDevtools.Util.integer(player,1,2147483647) or requested[player] then return end
        local alias,err=core.ensure(player)
        if not alias then return reply(player,err or 'Identidad no disponible.') end
        requested[player]=true;core.requestSpawn(player,'connect')
    end)
    RegisterNetEvent('osdev:characterSpawned',function(token) core.spawnAck(source,token) end)
    RegisterNetEvent('osdev:spawnFailed',function(token) core.spawnFailed(source,token) end)
    RegisterNetEvent('osdev:deathObserved',function() core.observe(source) end)
    AddEventHandler('playerJoining',function()
        local player=tonumber(source)
        SetTimeout(500,function() if GetPlayerName(player) then local alias,err=core.ensure(player);if not alias then reply(player,err) end end end)
    end)
    AddEventHandler('playerDropped',function()
        local player=tonumber(source);core.drop(player);requested[player]=nil
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
    exports('ResolveCharacter',function(value) if not reader() then return nil,'resource_not_authorized' end;return core.find(value) end)
    exports('GetIdentityStatus',function() return {ready=core.status(),version='0.1.3',provider='os_devtools'} end)
    exports('GetCharacterSpawn',function(player) if reader() then return core.spawnSelection(player) end end)
    -- Compatibilidad con el inventario pretest; el contrato nuevo es GetActiveCharacter.
    exports('GetCharacterId',function(player) if reader() then return core.ensure(player) end end)
    exports('GetCharacterByAlias',function(alias)
        if not reader() or type(alias)~='string' then return nil end
        local found=core.find('alias:'..alias);return found and found.alias or nil
    end)
end
