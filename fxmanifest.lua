fx_version 'cerulean'

shared_script "@SecureServe/src/module/module.lua"
shared_script "@SecureServe/src/module/module.js"
file "@SecureServe/secureserve.key"
lua54 'yes'
game 'gta5'
author 'KurdY'
description 'A highly advanced recoil script for fivem'
client_scripts {
    'config.lua',
    'client.lua'
}

server_scripts {
    'config.lua',
    'server.lua'
}

files {
    'recoil.json',
    'ui.html'
}

ui_page 'ui.html'
kr = true -- :()