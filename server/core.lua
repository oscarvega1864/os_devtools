-- Nucleo servidor independiente de nativos: identidad, persistencia y ciclo vital.
OSDevtools.Core={}
function OSDevtools.Core.new(options)
    local u,domain,config=OSDevtools.Util,OSDevtools.State,OSDevtools.CoreConfig
    local storage=options.storage
    local state=storage and u.copy(storage.data) or {characters={},bindings={},vehicles={},businesses={},properties={},audit={}}
    local active,cache,pending,completed={}, {}, {}, {}
    local loaded=false
    local spawnCounter=0
    local core={}
    local function publish() options.publish(u.copy(state),core.status()) end
    function core.status() return loaded and storage~=nil and not storage.journal.isBlocked() end
    function core.lookup(source)
        if not core.status() then return nil end
        local account=core.account(source);local alias=account and state.bindings[account]
        return alias and state.characters[alias].account==account and alias or nil
    end
    function core.account(source)
        if not u.integer(source,1,2147483647) or not options.connected(source) then return nil,'player_disconnected' end
        local known,preferred,seen={},{},{}
        for _,identifier in ipairs(options.identifiers(source) or {}) do
            if domain.account(identifier) then
                local kind=identifier:match('^([^:]+):')
                if seen[kind] and seen[kind]~=identifier then return nil,'ambiguous_identifiers' end
                seen[kind]=identifier
            end
        end
        for _,kind in ipairs({'license','license2','fivem'}) do
            local account=seen[kind]
            preferred[1]=preferred[1] or account
            if account and state.bindings[account] then
                if known.alias and known.alias~=state.bindings[account] then return nil,'conflicting_bindings' end
                known.account,known.alias=account,state.bindings[account]
            end
        end
        return known.account or preferred[1],(known.account or preferred[1]) and nil or 'no_persistent_identifier'
    end
    function core.change(actor,label,callback)
        if not core.status() then return false,'Registro bloqueado; revisar almacenamiento.' end
        local candidate=u.copy(state)
        local ok,reason=callback(candidate)
        if not ok then return false,reason or 'Operacion rechazada.' end
        local at=math.max(options.now(),state.audit[#state.audit] and state.audit[#state.audit].time or 0)
        candidate.audit[#candidate.audit+1]={time=at,actor=actor==0 and 'console' or (core.account(actor) or ('session:'..actor)),operation=label}
        if #candidate.audit>300 then table.remove(candidate.audit,1) end
        local saved,err=storage.save(candidate)
        if not saved then publish();return false,err or 'Escritura no confirmada.' end
        state=u.copy(storage.data);publish();return true
    end
    function core.start()
        if not storage then return false,'Almacenamiento invalido.' end
        loaded=true
        if storage.needsMigration then
            local ok,reason=core.change(0,'migration_013',function() return true end)
            if not ok then loaded=false;publish();return false,reason end
        end
        publish();return true
    end
    local function notifyChange(source,alias)
        local c=state.characters[alias]
        active[source]={alias=alias,account=c.account,id=c.id}
        cache[source]=nil;pending[source]=nil;completed[source]=nil
        options.changed(source,{characterId=c.id,alias=alias,connected=true})
    end
    function core.ensure(source)
        if not core.status() then return nil,'storage_unavailable' end
        local account,err=core.account(source);if not account then return nil,err end
        local alias=state.bindings[account]
        if alias and state.characters[alias] and state.characters[alias].account==account then
            if not active[source] or active[source].alias~=alias or active[source].account~=account then notifyChange(source,alias) end
            return alias
        end
        local owned,unclaimed={},false
        for name,c in pairs(state.characters) do
            if c.account==account then owned[#owned+1]=name end
            if c.account==nil then unclaimed=true end
        end
        if #owned>1 then return nil,'multiple_owned_characters' end
        if #owned==0 and unclaimed then return nil,'legacy_link_required' end
        alias=owned[1]
        local ok,reason=core.change(0,'automatic_identity',function(d)
            if not alias then
                local id=d.nextCharacter;alias=('auto_%010d'):format(id)
                while d.characters[alias] do alias=alias..'_x' end
                if not domain.alias(alias) then return false,'No hay alias automatico disponible.' end
                d.characters[alias]={id=('oschar_%010d'):format(id),account=account,cash=0,bank=0,job='unemployed',rank='-',duty=false,life='alive',deaths={},nextDeath=1}
                d.nextCharacter=id+1
            end
            d.bindings[account]=alias;return true
        end)
        if not ok then return nil,reason end
        notifyChange(source,alias);return alias
    end
    function core.resolve(value)
        return domain.resolve(state,value,function(source) return core.ensure(source) end)
    end
    function core.dto(source)
        local alias,err=core.ensure(source);local c=alias and state.characters[alias]
        return c and {characterId=c.id,alias=alias,source=source,connected=true,spawning=pending[source]~=nil} or nil,err
    end
    function core.find(value)
        local alias,err=core.resolve(value);local c=alias and state.characters[alias]
        if not c then return nil,err end
        local dto={characterId=c.id,alias=alias,connected=false}
        for player,context in pairs(active) do
            if context.id==c.id and options.connected(player) and core.lookup(player)==alias then dto.connected=true;dto.source=player;break end
        end
        return dto
    end
    function core.position(source)
        local point,health=options.world(source)
        if not domain.position(point,false) or not config.AllowedBuckets[point.bucket] then return nil,health end
        point=u.copy(point)
        for _,axis in ipairs({'x','y','z','h'}) do point[axis]=domain.number(point[axis]) end
        return point,health
    end
    local function stamp(point,reason,previous)
        local p=u.copy(point);p.at=math.max(options.now(),previous and previous.at or 0);p.time=p.at;p.reason=reason;return p
    end
    local function captured(source,reason,force)
        local context=active[source]
        local alias=context and context.alias
        local c=alias and state.characters[alias]
        if not c or pending[source] then return nil end
        if c.life=='dead' then
            if reason~='disconnect' then return nil end
            local deadPoint=core.position(source) or c.lastDeathPosition
            return deadPoint and alias or nil,deadPoint and stamp(deadPoint,reason,c.lastLogoutPosition) or nil,true
        end
        local point,health=core.position(source)
        if not point or not health or health<=0 then
            point=({disconnect=true,resource_stop=true,server_shutdown=true})[reason] and cache[source] or nil
        end
        if not point then return nil end
        local old=c.lastValidPosition or c.lastPosition
        if not force and old and old.bucket==point.bucket and math.abs(old.h-point.h)<1
            and (old.x-point.x)^2+(old.y-point.y)^2+(old.z-point.z)^2<config.MinPositionMove^2 then return nil end
        return alias,stamp(point,reason,old)
    end
    function core.savePositions(sources,reason,force)
        if not core.status() then return false,'Registro bloqueado.' end
        local updates={}
        for _,source in ipairs(sources) do
            if not active[source] and options.connected(source) then core.ensure(source) end
            local alias,point,dead=captured(source,reason,force)
            if alias then updates[alias]={point=point,dead=dead} end
        end
        if not next(updates) then return false,'No hay una posicion viva valida nueva.' end
        return core.change(0,'positions:'..reason,function(d)
            for alias,update in pairs(updates) do
                local point=update.point;local c=d.characters[alias]
                if not update.dead then c.lastPosition=u.copy(point);c.lastValidPosition=u.copy(point) end
                if reason=='disconnect' then c.lastLogoutPosition=u.copy(point) end
            end
            return true
        end)
    end
    function core.createCharacter(actor,target,alias)
        local account,err=core.account(target);if not account then return false,err end
        if not domain.alias(alias) then return false,'Alias invalido.' end
        for name in pairs(state.characters) do if name:lower()==alias:lower() then return false,'Alias duplicado.' end end
        local prior=state.bindings[account]
        local saved,reason=core.change(actor,'create_character '..alias,function(d)
            local id=d.nextCharacter
            d.characters[alias]={id=('oschar_%010d'):format(id),account=account,cash=0,bank=0,job='unemployed',rank='-',duty=false,life='alive',deaths={},nextDeath=1}
            d.nextCharacter=id+1
            if not d.bindings[account] then d.bindings[account]=alias end
            return true
        end)
        if saved and not prior then core.ensure(target);core.requestSpawn(target,'new_character') end
        return saved,reason
    end
    function core.select(actor,target,value,claim)
        local account,err=core.account(target);if not account then return false,err end
        if state.bindings[account] then core.ensure(target) end
        local alias,reason=core.resolve(value);if not alias then return false,reason end
        local selected=state.characters[alias]
        if selected.account~=account and not (claim and selected.account==nil) then return false,'Personaje de otra cuenta o vinculo heredado no confirmado.' end
        if pending[target] then return false,'Aparicion en curso.' end
        local old=state.bindings[account]
        if old==alias and selected.account==account then return true end
        local oldAlias,point=captured(target,'character_switch',true)
        if old and state.characters[old].life~='dead' and not oldAlias then return false,'No se pudo guardar la posicion anterior; cambio cancelado.' end
        local ok,errorMessage=core.change(actor,(claim and 'claim_character ' or 'select_character ')..selected.id,function(d)
            if oldAlias then d.characters[oldAlias].lastPosition=point;d.characters[oldAlias].lastValidPosition=u.copy(point) end
            d.characters[alias].account=account;d.bindings[account]=alias;return true
        end)
        if ok then notifyChange(target,alias);core.requestSpawn(target,'character_switch') end
        return ok,errorMessage
    end
    function core.spawnSelection(source,fallback)
        local alias,err=core.ensure(source);local c=alias and state.characters[alias]
        if not c then return nil,err end
        local point
        if c.life=='dead' then point=config.HospitalSpawn
        elseif fallback then point=config.DefaultSpawn
        elseif c.spawnOverridePending then point=c.customSpawn
        else point=c.lastValidPosition or c.lastPosition or c.customSpawn or config.DefaultSpawn end
        if not domain.position(point,false) or not config.AllowedBuckets[point.bucket] then point=config.DefaultSpawn end
        if not domain.position(point,false) or not config.AllowedBuckets[point.bucket] then return nil,'Spawn configurado invalido.' end
        return u.copy(point),c.id
    end
    function core.requestSpawn(source,reason,fallback)
        if OSDevtools.SpawnConfig.Mode~='spawnmanager' then return false,'external_spawn_owner' end
        if pending[source] then return false,'spawn_in_progress' end
        local point,id=core.spawnSelection(source,fallback);if not point then return false,id end
        spawnCounter=spawnCounter+1
        local token=('%d:%d:%d'):format(source,spawnCounter,options.clock())
        pending[source]={id=id,token=token,position=point,at=options.clock(),expires=options.clock()+config.SpawnMilliseconds,fallback=fallback==true}
        local alias=core.lookup(source);local c=alias and state.characters[alias]
        options.spawn(source,{token=token,position=point,reason=reason,appearance=c and c.id==id and u.copy(c.appearance) or nil})
        return true
    end
    function core.spawnAck(source,token)
        local prior=completed[source]
        if prior and prior.token==token and options.clock()<prior.expires then options.spawnAccepted(source,token);return true end
        local context=pending[source]
        if not context or token~=context.token or options.clock()<context.at or options.clock()>=context.expires then return false end
        local alias=core.ensure(source);local c=alias and state.characters[alias]
        local point,health=core.position(source)
        local target=context.position
        if not c or c.id~=context.id or not point or not health or health<=0 or point.bucket~=target.bucket
            or (point.x-target.x)^2+(point.y-target.y)^2+(point.z-target.z)^2>64 then return false end
        local saved=core.change(0,'spawn '..c.id,function(d)
            local record=d.characters[alias];record.life='alive';record.spawnOverridePending=false
            record.lastPosition=stamp(point,'spawn',record.lastPosition);record.lastValidPosition=u.copy(record.lastPosition)
            return true
        end)
        if not saved then return false end
        pending[source]=nil;cache[source]=point;completed[source]={token=token,expires=options.clock()+10000}
        options.spawnAccepted(source,token);return true
    end
    function core.spawnFailed(source,token)
        local context=pending[source]
        if not context or context.token~=token then return false end
        pending[source]=nil
        if context.fallback then return false end
        return core.requestSpawn(source,'safe_fallback',true)
    end
    function core.observe(source)
        local alias=core.ensure(source);local c=alias and state.characters[alias]
        if not c then return false end
        local context=pending[source]
        if context then
            if options.clock()<context.at or options.clock()>=context.expires then return core.spawnFailed(source,context.token) end
            return true
        end
        local point,health=core.position(source)
        if not point or not health then return false end
        if health<=0 then
            if c.life=='dead' then return true end
            local saved=core.change(0,'death '..c.id,function(d)
                local record=d.characters[alias];local death=stamp(point,'death',record.lastDeathPosition)
                record.lastDeathPosition=death;record.life='dead'
                record.deaths[#record.deaths+1]={id=record.nextDeath,characterId=record.id,position=u.copy(death),cause='unknown'}
                record.nextDeath=record.nextDeath+1
                if #record.deaths>config.MaxDeaths then table.remove(record.deaths,1) end
                return true
            end)
            if saved then options.schedule(config.RespawnMilliseconds,function()
                local current=core.ensure(source)
                if current==alias and state.characters[alias].life=='dead' then core.requestSpawn(source,'death') end
            end) end
            return saved
        end
        cache[source]=point
        if c.life=='dead' then
            -- Un ped nuevo puede tener salud antes de completar el spawn de reconexion.
            -- Solo el ACK del spawn propio puede cerrar la muerte en este modo.
            if OSDevtools.SpawnConfig.Mode=='spawnmanager' then return true end
            return core.change(0,'revived '..c.id,function(d) d.characters[alias].life='alive';return true end)
        end
        return true
    end
    function core.drop(source)
        core.savePositions({source},'disconnect',true)
        active[source],cache[source],pending[source],completed[source]=nil,nil,nil,nil
        options.changed(source,nil)
    end
    function core.setSpawn(actor,target)
        local alias,err=core.resolve(target);if not alias then return false,err end
        local point=core.position(actor);if not point then return false,'Posicion administrativa no valida.' end
        return core.change(actor,'setspawn '..state.characters[alias].id,function(d)
            d.characters[alias].customSpawn=stamp(point,'assigned_spawn');d.characters[alias].spawnOverridePending=true;return true
        end)
    end
    -- Solo el personaje activo, vivo y fuera de una aparicion puede guardar su apariencia;
    -- asi una apariencia anterior nunca se escribe sobre el personaje recien seleccionado.
    function core.saveAppearance(source,value)
        local context=active[source];local alias=context and context.alias
        local c=alias and core.lookup(source)==alias and state.characters[alias]
        if not c then return false,'Identidad no disponible.' end
        if pending[source] then return false,'Aparicion en curso; apariencia no guardada.' end
        if c.life=='dead' then return false,'Personaje muerto; apariencia no guardada.' end
        local appearance=domain.normalizeAppearance(value)
        if not appearance then return false,'Apariencia invalida; no se guarda.' end
        if u.equal(appearance,c.appearance) then return true,'unchanged' end
        local ok,err=core.change(source,'appearance '..c.id,function(d) d.characters[alias].appearance=appearance;return true end)
        return ok,err
    end
    -- Importacion administrativa: escribe la apariencia de un personaje aunque este desconectado.
    function core.importAppearance(actor,target,value)
        local alias,err=core.resolve(target);if not alias then return false,err end
        local appearance=domain.normalizeAppearance(value)
        if not appearance then return false,'Apariencia invalida; no se importa.' end
        local c=state.characters[alias]
        local ok,reason=core.change(actor,'import_appearance '..c.id,function(d) d.characters[alias].appearance=appearance;return true end)
        if not ok then return false,reason end
        return true,alias
    end
    -- Jugadores conectados con ese personaje activo.
    function core.sourcesOf(alias)
        local result={}
        for player,context in pairs(active) do
            if context.alias==alias and options.connected(player) and core.lookup(player)==alias then result[#result+1]=player end
        end
        return result
    end
    function core.snapshot() return core.status() and u.copy(state) or nil end
    return core
end
