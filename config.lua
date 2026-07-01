Config = {}

-- ============================================================
--  rs-streetdice  config.lua
--  All v0.1.0 values preserved. New options at the bottom of
--  each block and in the new Config.Sounds section.
-- ============================================================

Config.Debug = false
Config.Framework = 'auto' -- auto, qbcore, qbox, esx, standalone
Config.ResourceName = 'rs-streetdice'

Config.Bridge = {
    -- auto detects qb-core, qbx_core, es_extended, then standalone.
    -- standalone uses in-resource test balances only and is NOT recommended for live economy.
    framework = Config.Framework,
    notify = 'auto',
    useFrameworkCommands = true,
    useFrameworkItem = true,
    standaloneStartingCash = 10000
}

Config.Item = {
    enabled = true,
    name = 'streetdice',
    removeOnUse = false
}

Config.Money = {
    type = 'cash',
    minBet = 100,
    maxBet = 2500,
    allowNpcBankCoverage = true, -- true lets The Bank cover missing action for solo/small games; false is authentic player-vs-player street dice
    npcBankrollPerGame = 50000
}

Config.Game = {
    joinRadius = 8.0,
    bankSpawnDistance = 9.0,
    bankArriveDelaySeconds = 8,
    bettingSeconds = 30,
    idleCleanupSeconds = 120,
    dicePropLifetimeSeconds = 12,
    requireBankArrivedBeforeBets = true,
    lockAfterFirstBet = true,
    allowEndDuringBettingOnlyIfNoBets = true,

    -- v0.2.0 additions
    shooterMustBet = true,             -- shooter is required to have a bet on the table to roll
    shooterBetSide = 'with',           -- street dice: shooter must ride with themselves, never fade their own roll
    requireFadeToRoll = true,          -- at least one player must fade the shooter before dice can fly
    requireCoveredAction = true,        -- riding and fading money must match before the shooter can roll
    enforceBettingDeadline = false,     -- false keeps betting open until the shooter rolls; coverage gates the roll
    passDiceOnSevenOut = true,         -- after a seven-out, dice pass to the next player in the circle
    passDiceOnComeoutCraps = true,      -- street variant: if shooter craps out on come-out, dice pass
    maxConcurrentGames = 6,            -- global cap on simultaneous dice circles on the server
    bettingWarningSeconds = 5,         -- send "bets closing" hype this many seconds before bettingSeconds expires
    autoCancelIfNoRollSeconds = 60,    -- after betting expires, if shooter never rolls, refund and end

    -- v0.2.3 additions
    bankInteractDistance = 2.8,        -- distance in meters at which "Press E" prompt appears over the Bank NPC

    -- v0.3.14 scene visibility for nearby non-member spectators
    sceneRenderDistance = 70.0,        -- meters; players inside this range receive scene presence updates
    scenePresenceMs = 3000,            -- server heartbeat for nearby scene updates
    sceneStaleMs = 9000                -- client cleanup if a spectator stops receiving scene presence
}

Config.Bank = {
    label = 'The Bank',
    -- Bank walk-in polish. The Bank spawns close enough to be seen, then walks to the dice circle.
    walkTargetOffset = 1.35,
    snapIfFarDistance = 18.0,
    snapIfUnderGround = true,
    -- false avoids GTA clipboard/notepad props dropping on the ground when scenarios restart.
    -- Set true if you prefer the clipboard look and do not see prop litter on your server.
    useClipboardScenario = false,
    models = {
        'g_m_y_ballaeast_01',
        'g_m_y_famca_01',
        'g_m_y_mexgoon_02',
        'a_m_m_eastsa_02'
    },
    idleScenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    takingBetsScenario = 'WORLD_HUMAN_CLIPBOARD',
    hypeScenario = 'WORLD_HUMAN_CHEERING',
    payoutScenario = 'WORLD_HUMAN_GUARD_STAND'
}

Config.Crowd = {
    enabled = true,
    -- Keep the default crowd small. Larger crowds are cool later, but during testing
    -- they can look like a clone wall if a bad restart leaves old local peds behind.
    minPeds = 2,
    maxPeds = 4,
    radius = 5.2,
    arriveSpread = 2.4,
    models = {
        'g_m_y_ballaeast_01',
        'g_m_y_ballaorig_01',
        'g_m_y_famca_01',
        'g_m_y_famdnf_01',
        'a_m_y_ktown_01',
        'a_m_y_soucent_02',
        'a_f_y_soucent_01',
        'a_f_y_eastsa_03'
    },
    scenarios = {
        'WORLD_HUMAN_CHEERING',
        'WORLD_HUMAN_MOBILE_FILM_SHOCKING',
        'WORLD_HUMAN_STAND_IMPATIENT',
        'WORLD_HUMAN_HANG_OUT_STREET'
    }
}

Config.Dice = {
    prop = 'prop_dice_01',
    -- If the main prop is not on your build, the first of these that loads is used for
    -- the physical dice. If none load, the on-screen dice + throw animation still play,
    -- so the roll always gives feedback. Add your own streamed dice model here if you have one.
    propFallbacks = { 'prop_dice_single_01', 'prop_poker_dice', 'v_res_dice' },
    throwAnimDict = 'anim@mp_snowball',
    throwAnimName = 'throw_snowball',
    throwAnimMs = 1550,
    releaseDelayMs = 760,
    pickupAnimDict = 'pickup_object',
    pickupAnimName = 'pickup_low',
    pickupAnimMs = 1200,
    pickupGrabDelayMs = 650,
    rollVisualMs = 2600
}

Config.UI = {
    -- The menu can be dragged by the top/header area in-game. The position is saved per player in NUI localStorage.
    draggable = true,
    defaultRight = '2.5vw',
    defaultTop = '12vh'
}

Config.Hype = {
    enabled = true,
    cooldownMs = 1500,                 -- minimum gap between any two hype broadcasts per game
    lines = {
        bank_arriving = {'Bank coming over!', 'Hold up, Bank walking in!', 'Circle up, money man coming!'},
        betting       = {'Who riding with the shooter?', 'Who fading the shooter?', 'Cover that money!', 'Cash down, dice up!', 'Do not talk it, match it!', 'Fade me then!', 'Who got the back line?'},
        warning       = {'Last call on the fade!', 'Cover it now!', 'Money closing!', 'Last money before dice fly!'},
        locked        = {'Money locked!', 'Dice hot, hands back!', 'No late money!', 'Back up, shooter got dice!'},
        natural       = {'Seven-eleven, shooter eats!', 'Natural! Pay the line!', 'Winner on the come out!'},
        craps         = {'Craps! Fade side eats!', 'Two, three, twelve, shooter burned!', 'Crap out, pay the fade!'},
        point         = {'Point marked!', 'That is the number now!', 'Bring it back before seven!', 'Point on, keep them dice hot!'},
        sevenout      = {'Seven out! Pass them dice!', 'Seven showed, fade side eats!', 'Dice move!', 'Missout, next shooter!'},
        hitpoint      = {'Point hit! Shooter brought it back!', 'Pay the line, point made!', 'Shooter made the point!'},
        payout        = {'Pay it right!', 'Settle the money!', 'Do not short nobody!', 'Cash out the line!'},
        ambient       = {'Money on the pavement!', 'Get it covered!', 'Ride or fade!', 'Shooter got hands!', 'Cover the back!', 'Eyes on the dice!', 'No side switching!', 'Keep the dice in the circle!'}
    },

    -- v0.2.0 ambient yelling. While bank is on scene during betting/point states,
    -- he randomly hypes the circle on this interval.
    ambient = {
        enabled = true,
        minIntervalMs = 8000,
        maxIntervalMs = 14000
    }
}

-- ============================================================
--  v0.2.0 Sound system
--  Drop .ogg files into the /sounds folder of this resource and
--  list their filenames in the arrays below. Each bucket plays a
--  random file from its list when that hype event fires. Effects
--  are direct filenames for throw, land, and pickup dice SFX.
--  Files are streamed through the NUI Audio API so they play
--  even when the dice panel is closed, as long as the player is
--  inside audibleRadius of the dice circle.
-- ============================================================
Config.Sounds = {
    enabled = false,        -- placeholder .ogg filenames ship empty; replace files and enable
    volume = 0.7,           -- 0.0 to 1.0
    audibleRadius = 25.0,   -- meters; players outside this range do not hear the bank

    files = {
        bank_arriving = {'arriving_1.ogg', 'arriving_2.ogg'},
        betting       = {'betting_1.ogg', 'betting_2.ogg', 'betting_3.ogg'},
        warning       = {'warning_1.ogg', 'warning_2.ogg'},
        locked        = {'locked_1.ogg', 'locked_2.ogg'},
        natural       = {'natural_1.ogg', 'natural_2.ogg'},
        craps         = {'craps_1.ogg', 'craps_2.ogg'},
        point         = {'point_1.ogg', 'point_2.ogg'},
        sevenout      = {'sevenout_1.ogg', 'sevenout_2.ogg'},
        hitpoint      = {'hitpoint_1.ogg', 'hitpoint_2.ogg'},
        payout        = {'payout_1.ogg', 'payout_2.ogg'},
        ambient       = {'ambient_1.ogg', 'ambient_2.ogg', 'ambient_3.ogg', 'ambient_4.ogg'}
    },

    effects = {
        throw  = 'dice_throw.ogg',
        land   = 'dice_land.ogg',
        pickup = 'dice_pickup.ogg'
    }
}
