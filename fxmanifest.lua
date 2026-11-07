fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'OSCAR - entorno de pruebas'
description 'Herramientas standalone de personajes, economia y activos para DEV; NO produccion'
version '0.1.3-pretest.1'
server_scripts {
    'config/authorization.lua', 'server/lib/util.lua', 'server/auth_identity.lua',
    'server/authorization_hub.lua', 'server/auth_boot.lua', 'server.lua'
}
client_script 'client.lua'

ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }
