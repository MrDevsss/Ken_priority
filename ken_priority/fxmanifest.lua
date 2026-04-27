
fx_version 'cerulean'
game 'gta5'

author 'Ken Mondragon'
description 'Priority Cooldown System'
version '1.0.0'

dependencies {
    'es_extended',
}

shared_scripts {
    '@es_extended/imports.lua',
   
    'shared/config.lua'
}

server_scripts {
     '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server.lua'
}

client_scripts {
    'client/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}