fx_version 'cerulean'
game 'gta5'

author 'Nate Dogg (Lint Error)'
version '1.0.0'
description 'Remote deployable spike box: place a box, link a key fob, trigger synced rolling spike strips'

lua54 'yes'
ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    'config/shared.lua',
}

client_scripts {
    'bridge/client/*.lua',
    'client/spikes.lua',
    'client/main.lua',
}

server_scripts {
    'server/version.lua',
    'server/storage.lua',
    'bridge/server/framework/*.lua',
    'bridge/server/inventory/*.lua',
    'server/main.lua',
}

files {
    'locales/*.json',
    'sounds/dlc_stinger/stinger.awc',
    'sounds/data/stinger.dat54.rel',
    'stream/nd_spikebox.ytyp',
    'stream/nd_spikefob.ytyp',
}

data_file 'AUDIO_WAVEPACK' 'sounds/dlc_stinger'
data_file 'AUDIO_SOUNDDATA' 'sounds/data/stinger.dat'
data_file 'DLC_ITYP_REQUEST' 'stream/nd_spikebox.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/nd_spikefob.ytyp'

dependencies {
    'ox_lib',
}
