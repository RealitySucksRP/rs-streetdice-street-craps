fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rs-streetdice'
author 'Reality Sucks RP / William Brito'
description 'Mobile street craps dice game with Bank NPC pot handling, locked bets, server-side rolls, internal bridge, placeholder sound hooks, and customizable config.'
version '0.3.19-test'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'sounds/*.ogg'
}
