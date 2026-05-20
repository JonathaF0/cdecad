fx_version 'cerulean'
game 'gta5'

name 'CDECAD_Template'
description 'CDECAD_Template with SA lore departments (LSPD, LCSO, SASP, BCSO, LSFD, BCFD). Drop-in alternative to CDECAD.'
author 'CDECAD'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'civ/vehicles.lua',
}

server_scripts {
    'tablet/server_main.lua',
    'duty/server.lua',
    'duty/diagnostics.lua',
    '@oxmysql/lib/MySQL.lua',
    'civ/server_main.lua',
    '911/server.lua',
    'wraith/server.lua',
    'ers/server.lua',
}

client_scripts {
    'tablet/client_main.lua',
    'duty/client.lua',
    'duty/diagnostics.lua',
    'civ/client_main.lua',
    'civ/client_nui.lua',
    '911/client.lua',
    '911/npc.lua',
    'wraith/client.lua',
    'ers/client.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/tablet/index.html',
    'html/tablet/style.css',
    'html/tablet/script.js',
    'html/civ/index.html',
    'html/civ/style.css',
    'html/civ/script.js',
    'html/wraith/index.html',
}

dependencies {
    'ox_lib',
}
