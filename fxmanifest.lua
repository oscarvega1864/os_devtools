fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'OSCAR - entorno de pruebas'
description 'Herramientas standalone de personajes, economia y activos para DEV; NO produccion'
version '0.1.3'
shared_script 'config/spawn.lua'
server_scripts {
    'config/authorization.lua', 'config/core.lua', 'server/lib/util.lua',
    'server/storage/codec.lua', 'server/storage/resource_files.lua', 'server/storage/json.lua',
    'server/state.lua', 'server/appearance_xml.lua', 'server/storage.lua', 'server/core.lua',
    'server/auth_identity.lua', 'server/authorization_hub.lua', 'server/auth_boot.lua',
    'server/identity_commands.lua', 'server.lua'
}
client_scripts { 'client.lua', 'client/appearance.lua', 'client/spawn_controller.lua', 'client/spawn.lua' }

ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }
