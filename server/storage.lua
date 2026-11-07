-- El data.json original se conserva. Las revisiones nuevas usan dos slots propios.
function OSDevtools.openStorage(resource)
    local files=OSDevtools.ResourceFiles.new({resource=resource,load=LoadResourceFile,save=SaveResourceFile,open=io.open})
    local seed={version=1,nextVehicle=1,nextBusiness=1,characters={},bindings={},vehicles={},businesses={},properties={},audit={}}
    local legacy, legacyError = nil,nil
    local a,ae=files.read('data/core.a.json');local b,be=files.read('data/core.b.json')
    if ae or be then return nil,'No se pudo leer el almacenamiento.' end
    if a==nil and b==nil then
        legacy,legacyError=files.read('data.json')
        if legacyError then return nil,'No se pudo leer data.json.' end
        if legacy then
            if #legacy>OSDevtools.CoreConfig.MaxFileBytes then return nil,'data.json excede el limite.' end
            local ok,decoded=pcall(OSDevtools.JsonCodec.decode,legacy)
            if not ok then return nil,'data.json corrupto; no se sobrescribe.' end
            seed=decoded
        end
    end
    local migrated,reason=OSDevtools.State.migrate(seed)
    if not migrated then return nil,reason end
    local journal=OSDevtools.JsonStorage.new({base='data/core',limits=OSDevtools.CoreConfig,
        initialSnapshot=migrated,validation=OSDevtools.State,read=files.read,write=files.write,
        encode=OSDevtools.JsonCodec.encode,decode=OSDevtools.JsonCodec.decode,
        log=function(message) print('[os_devtools] '..message) end})
    local data,err=journal.load();if not data then return nil,err end
    local savedLegacy=legacy==nil
    local storage={data=data,journal=journal,needsMigration=a==nil and b==nil}
    function storage.save(candidate)
        if not savedLegacy then
            local backup,readError=files.read('data/migration-013-source.json')
            if readError or (backup and backup~=legacy) then return nil,'Copia heredada distinta; revision manual requerida.' end
            if not backup then
                local ok=files.write('data/migration-013-source.json',legacy)
                local observed=files.read('data/migration-013-source.json')
                if not ok or observed~=legacy then return nil,'No se pudo verificar el respaldo heredado.' end
            end
            savedLegacy=true
        end
        candidate.revision=storage.data.revision+1
        local ok,saveError=journal.save(candidate)
        if ok then storage.data=OSDevtools.Util.copy(candidate) end
        return ok,saveError
    end
    return storage
end
