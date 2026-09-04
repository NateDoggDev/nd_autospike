Config = {
    locale = 'en',                      -- locales/<locale>.json
    debug = false,                      -- console prints and the /spikefobtune command
    persistence = true,                 -- save boxes to the database (needs oxmysql)
    restoreDeployed = true,             -- boxes that were deployed come back deployed after a restart

    allowedJobs = { leo = 0 },          -- {} = everyone. job name or job type = minimum grade
    acePermission = false,              -- e.g. 'nd_autospike.use' to gate by ACE as well
    ownerOnlyPickup = false,            -- only the officer who placed a box can pick it up
    ownerOnlyLink = false,              -- only the officer who placed a box can take fobs or toggle it at the box

    maxBoxes = 25,                      -- server-wide cap on placed boxes
    maxBoxesPerPlayer = 3,              -- per-officer cap on placed boxes
    maxFobsPerBox = 2,                  -- fobs a box will hand out, one per person. 0 = unlimited
    placeDistance = 8.0,                -- how far in front of you the box can be placed
    linkDistance = 3.0,                 -- how close an unlinked fob must be to a box to link to it
    fobRange = 250.0,                   -- max distance between officer and box for the fob to work
    pickupDistance = 3.0,               -- target / prompt range at the box
    autoRetract = 0,                    -- seconds until spikes retract on their own. 0 = never
    toggleCooldown = 400,               -- ms debounce on fob presses, silent
    burstNpcVehicles = true,            -- AI traffic pops tyres too
    burst = {
        rimSpeed = 60,                  -- km/h. below = flat tyre, at or above = blowout to the rim
        alwaysRim = false,              -- always blow out regardless of speed
    },
    useTarget = 'auto',                 -- 'auto', 'ox_target', 'qb-target' or false for the E / G prompt

    items = {
        box = 'spikebox',               -- item name of the placeable box
        fob = 'spikefob',               -- item name of the fob the box hands out
    },

    box = {
        model = `nd_spikebox`,          -- streamed by this resource. any vanilla prop works too
        frontOffset = 0.04,             -- box origin to where the strip starts. small = strip begins inside the slot
        placeAnim = { dict = 'anim@narcotics@trash', clip = 'drop_front', duration = 1600, flag = 48 },
        pickupAnim = { dict = 'pickup_object', clip = 'pickup_low', duration = 1200, flag = 48 },
    },

    stripMode = 'roll',                 -- 'roll' = stock stinger with its unroll animation. 'slide' = shorter static strip

    strips = {
        slide = {
            mode = 'slide',
            model = `p_stinger_03`,     -- 2.91 m static strip
            count = 2,                  -- strips laid end to end
            length = 2.91,
            width = 0.6,                -- tyre detection width across the strip
            yMin = -2.9,                -- detection bounds along the strip, model local Y
            yMax = 0.0,
            originOffset = 0.0,         -- model origin to its near end
            zOffset = 0.0,              -- raise or lower the strip after grounding
            headingOffset = 180.0,      -- flip if the strip extends toward the box instead of away
            gap = 0.0,                  -- spacing between strips
            flipTime = 650,             -- ms for the first strip to flip out of the box
            flipStartPitch = 90.0,      -- use -90.0 if it rises from the wrong side
            slideTime = 900,            -- ms for the other strips to slide out
            stagger = 0,                -- extra ms between strips
        },
        roll = {
            mode = 'roll',
            model = `p_ld_stinger_s`,   -- the only strip with a deploy animation
            animDict = 'p_ld_stinger_s',
            deployClip = 'p_stinger_s_deploy',
            holdPhase = 1.0,            -- stop the unroll early for a shorter strip. 0.7 = about two thirds
            coilSide = 'auto',          -- 'auto' detects which end the coil starts at. force 'near' or 'far'
            zOffset = 0.0,              -- raise or lower the strip after grounding
            count = 1,                  -- strips laid end to end. 1 = 3.68 m, 2 covers a two-lane road
            length = 3.68,
            width = 0.6,                -- tyre detection width across the strip
            yMin = -1.84,               -- detection bounds along the strip, model local Y
            yMax = 1.84,
            originOffset = 1.84,        -- model origin to its near end
            headingOffset = 0.0,        -- flip by 180 if the strip extends toward the box
            gap = 0.0,                  -- spacing between strips
            deployTime = 1500,          -- fallback ms if the clip length cannot be read
            retractDuration = 700,      -- ms for the roll-back
            stagger = 0,                -- extra ms between strips
        },
    },

    fob = {
        anim = { dict = 'anim@mp_player_intmenu@key_fob@', clip = 'fob_click', flag = 49, duration = 1200 },
        prop = { model = `nd_spikefob`, bone = 57005, offset = vec3(0.13, 0.03, -0.02), rotation = vec3(-90.0, 0.0, -20.0) }, -- false to disable. tune with /spikefobtune when debug is on
        sound = { name = 'Remote_Control_Fob', set = 'PI_Menu_Sounds' },   -- beep on press. false to disable
    },

    sound = {
        deploy = {
            bank = 'dlc_stinger/stinger',   -- custom bank shipped in sounds/
            name = 'deploy_stinger',
            set = 'stinger',
            fallback = { name = 'SPIKES', set = 'MP_RACE_SPIKES_SOUNDSET' },  -- used if the bank fails to load
        },
    },

    wheels = {                          -- bone name to tyre index, covers 4, 6 and 8 wheel vehicles
        { bone = 'wheel_lf', index = 0 },
        { bone = 'wheel_rf', index = 1 },
        { bone = 'wheel_lm1', index = 2 },
        { bone = 'wheel_rm1', index = 3 },
        { bone = 'wheel_lr', index = 4 },
        { bone = 'wheel_rr', index = 5 },
        { bone = 'wheel_lm2', index = 45 },
        { bone = 'wheel_lm3', index = 46 },
        { bone = 'wheel_rm2', index = 47 },
        { bone = 'wheel_rm3', index = 48 },
    },

    pickupKey = 'E',                    -- keybinds used when no target resource is running
    fobKey = 'G',
    clearCommand = 'clearspikeboxes',   -- admin command (ACE group.admin). false to disable
}

Config.strip = Config.strips[Config.stripMode]
