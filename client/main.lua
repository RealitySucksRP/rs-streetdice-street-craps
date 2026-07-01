local ActiveGames = {}
local MyGame = nil
local BankPeds = {}
local CrowdPeds = {}
local DiceObjects = {}
local PendingOpenGame = nil
local BankScenarioState = {}
local SceneLastSeen = {}

local function dbg(msg)
    if Config.Debug then print(('[rs-streetdice:client] %s'):format(msg)) end
end

local function loadModel(model)
    local hash = joaat(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    return hash, HasModelLoaded(hash)
end

local function loadAnim(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function notify(msg, typ)
    if GetResourceState('qb-core') == 'started' then
        local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and core and core.Functions and core.Functions.Notify then
            core.Functions.Notify(msg, typ or 'primary')
            return
        end
    end
    if GetResourceState('ox_lib') == 'started' and lib and lib.notify then
        lib.notify({ description = msg, type = typ or 'inform' })
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, false)
end

local function localizeGameForUi(game)
    if type(game) ~= 'table' or not game.id then return game end
    local out = {}
    for k, v in pairs(game) do out[k] = v end

    local myServerId = GetPlayerServerId(PlayerId())
    out.localServerId = myServerId
    out.isMeShooter = (out.shooter == myServerId)
    out.isInGame = (out.players and out.players[tostring(myServerId)] == true) or false
    return out
end

local function sendUi(action, data)
    if (action == 'show' or action == 'update') then
        data = localizeGameForUi(data)
    end
    SendNUIMessage({ action = action, data = data })
end

local function drawMarkerCircle(coords)
    DrawMarker(1, coords.x, coords.y, coords.z - 1.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        Config.Game.joinRadius * 2.0, Config.Game.joinRadius * 2.0, 0.08,
        255, 210, 80, 70,
        false, false, 2, false, nil, nil, false)
end

local function groundZ(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 20.0, false)
    if ok then return gz end
    return z
end

-- v0.2.0: try to find a navmesh-valid spawn point near the requested location
local function findSpawnNear(x, y, z, distance)
    for attempt = 1, 8 do
        local angle = math.random() * math.pi * 2.0
        local sx = x + math.cos(angle) * distance
        local sy = y + math.sin(angle) * distance
        local sz = groundZ(sx, sy, z)
        local found, nx, ny, nz = GetClosestVehicleNodeWithHeading(sx, sy, sz, 0, 1, 3.0, 0)
        if found then
            return nx, ny, nz
        end
    end
    -- fallback: just use ground at random angle
    local angle = math.random() * math.pi * 2.0
    local sx = x + math.cos(angle) * distance
    local sy = y + math.sin(angle) * distance
    return sx, sy, groundZ(sx, sy, z)
end

local function flatNorm(v)
    local len = math.sqrt((v.x * v.x) + (v.y * v.y))
    if len < 0.001 then return vector3(0.0, 1.0, 0.0) end
    return vector3(v.x / len, v.y / len, 0.0)
end

local function bankTargetCoords(game)
    local c = game.coords
    local base = vector3(c.x, c.y, c.z)
    local me = PlayerPedId()
    local pc = DoesEntityExist(me) and GetEntityCoords(me) or base
    local dir = flatNorm(pc - base)

    -- If the player is right on top of the game center, use their facing direction.
    if #(pc - base) < 0.65 then
        local fwd = GetEntityForwardVector(me)
        dir = flatNorm(vector3(fwd.x, fwd.y, 0.0))
    end

    local offset = (Config.Bank and Config.Bank.walkTargetOffset) or 1.35
    local x = c.x + dir.x * offset
    local y = c.y + dir.y * offset
    local z = groundZ(x, y, c.z)
    return vector3(x, y, z)
end

local function bankSpawnCoords(game)
    local c = game.coords
    local base = vector3(c.x, c.y, c.z)
    local me = PlayerPedId()
    local pc = DoesEntityExist(me) and GetEntityCoords(me) or base
    local distance = Config.Game.bankSpawnDistance or 9.0

    local dir = flatNorm(pc - base)
    if #(pc - base) < 0.65 then
        local fwd = GetEntityForwardVector(me)
        dir = flatNorm(vector3(fwd.x, fwd.y, 0.0))
    end

    -- Spawn outside the circle, toward the player camera side, so The Bank visibly walks in.
    local side = vector3(dir.y, -dir.x, 0.0) * ((math.random() - 0.5) * 2.2)
    local spawn = base + (dir * distance) + side
    local z = groundZ(spawn.x, spawn.y, c.z)
    return vector3(spawn.x, spawn.y, z)
end

local function placePedSafelyOnGround(ped, pos)
    if not ped or not DoesEntityExist(ped) then return end

    -- FiveM does not expose a generic PlaceEntityOnGroundProperly native in Lua.
    -- Using it was causing nil-call spam and stopping Bank/crowd/roll visual threads.
    -- For peds, resolve ground Z ourselves and place slightly above it.
    local z = groundZ(pos.x, pos.y, pos.z)
    SetEntityCoordsNoOffset(ped, pos.x, pos.y, z + 0.05, false, false, false)
end

local function spawnBank(game)
    if BankPeds[game.id] and DoesEntityExist(BankPeds[game.id]) then return end

    local spawn = bankSpawnCoords(game)
    local target = bankTargetCoords(game)

    local hash, loaded = loadModel(game.bankModel)
    if not loaded then
        -- Safe fallback so a typo/custom model in config does not make The Bank invisible.
        hash, loaded = loadModel('g_m_y_ballaeast_01')
    end
    if not loaded then
        dbg('Bank model failed to load; no Bank ped spawned.')
        return
    end

    local ped = CreatePed(4, hash, spawn.x, spawn.y, spawn.z + 0.05, 0.0, false, false)
    if not ped or ped == 0 then
        dbg('CreatePed failed for Bank.')
        return
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetEntityInvincible(ped, true)
    SetPedDiesWhenInjured(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 17, true)
    SetPedKeepTask(ped, true)
    placePedSafelyOnGround(ped, spawn)

    -- Walk in to a spot next to the shooter/circle instead of appearing on top of the game.
    TaskGoToCoordAnyMeans(ped, target.x, target.y, target.z, 1.05, 0, false, 786603, 0xbf800000)

    BankPeds[game.id] = ped
    SetModelAsNoLongerNeeded(hash)
end

local function faceCoord(ped, coords)
    local pc = GetEntityCoords(ped)
    local heading = GetHeadingFromVector_2d(coords.x - pc.x, coords.y - pc.y)
    SetEntityHeading(ped, heading)
end

local function cleanupDroppedBankProps(ped)
    if not ped or not DoesEntityExist(ped) then return end
    local pc = GetEntityCoords(ped)
    local propModels = {
        'prop_notepad_01',
        'p_amb_clipboard_01',
        'prop_cs_clipboard',
        'prop_ld_wallet_01'
    }
    for _, model in ipairs(propModels) do
        local obj = GetClosestObjectOfType(pc.x, pc.y, pc.z, 1.8, joaat(model), false, false, false)
        if obj and obj ~= 0 and DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
    end
end

local function snapBankToCircleIfNeeded(game)
    local ped = BankPeds[game.id]
    if not ped or not DoesEntityExist(ped) then
        spawnBank(game)
        ped = BankPeds[game.id]
    end
    if not ped or not DoesEntityExist(ped) then return end

    local target = bankTargetCoords(game)
    local pc = GetEntityCoords(ped)
    local distToTarget = #(pc - target)
    local farLimit = (Config.Bank and Config.Bank.snapIfFarDistance) or 18.0
    local underGround = (Config.Bank and Config.Bank.snapIfUnderGround ~= false) and (pc.z < (target.z - 2.2))

    if underGround or distToTarget > farLimit then
        -- Only snap when broken/stuck. Normal case should be a visible walk-in.
        placePedSafelyOnGround(ped, target)
        faceCoord(ped, vector3(game.coords.x, game.coords.y, game.coords.z))
        return
    end

    if distToTarget > 2.0 then
        TaskGoToCoordAnyMeans(ped, target.x, target.y, target.z, 1.05, 0, false, 786603, 0xbf800000)
    else
        faceCoord(ped, vector3(game.coords.x, game.coords.y, game.coords.z))
    end
end

local function bankScenarioForState(game)
    if game.state == 'betting' or game.state == 'round_over' then
        if Config.Bank and Config.Bank.useClipboardScenario == false then
            return Config.Bank.idleScenario or 'WORLD_HUMAN_STAND_IMPATIENT'
        end
        return Config.Bank.takingBetsScenario or 'WORLD_HUMAN_CLIPBOARD'
    elseif game.state == 'payout' then
        return Config.Bank.payoutScenario or 'WORLD_HUMAN_GUARD_STAND'
    elseif game.state == 'rolling' or game.state == 'point' or game.state == 'comeout' then
        return Config.Bank.hypeScenario or 'WORLD_HUMAN_CHEERING'
    end
    return Config.Bank.idleScenario or 'WORLD_HUMAN_STAND_IMPATIENT'
end

local function setBankScenario(gameId, scenario)
    local ped = BankPeds[gameId]
    if not ped or not DoesEntityExist(ped) then return end

    scenario = scenario or 'WORLD_HUMAN_STAND_IMPATIENT'
    if Config.Bank and Config.Bank.useClipboardScenario == false and scenario == Config.Bank.takingBetsScenario then
        scenario = Config.Bank.idleScenario or 'WORLD_HUMAN_STAND_IMPATIENT'
    end

    -- Do not restart the same scenario every bet/hype tick. Restarting clipboard-style
    -- scenarios is what causes notepads/clipboards to drop on the ground repeatedly.
    if BankScenarioState[gameId] == scenario then
        cleanupDroppedBankProps(ped)
        return
    end

    BankScenarioState[gameId] = scenario
    ClearPedTasks(ped)
    cleanupDroppedBankProps(ped)
    TaskStartScenarioInPlace(ped, scenario, 0, true)
    SetTimeout(900, function()
        if DoesEntityExist(ped) then cleanupDroppedBankProps(ped) end
    end)
end

local function setCrowdScenario(gameId, scenario)
    local crowd = CrowdPeds[gameId]
    if not crowd then return end
    for _, ped in ipairs(crowd) do
        if DoesEntityExist(ped) then
            ClearPedTasks(ped)
            TaskStartScenarioInPlace(ped, scenario, 0, true)
        end
    end
end

local function randomCrowdScenario()
    local scenarios = Config.Crowd and Config.Crowd.scenarios
    if not scenarios or #scenarios == 0 then return 'WORLD_HUMAN_CHEERING' end
    return scenarios[math.random(1, #scenarios)]
end

local function spawnCrowd(game)
    if not Config.Crowd or not Config.Crowd.enabled then return end
    if CrowdPeds[game.id] and #CrowdPeds[game.id] > 0 then return end

    local models = Config.Crowd.models or {}
    if #models == 0 then return end

    CrowdPeds[game.id] = {}
    local count = math.random(Config.Crowd.minPeds or 4, Config.Crowd.maxPeds or 7)
    local radius = Config.Crowd.radius or 5.2
    local spread = Config.Crowd.arriveSpread or 2.4
    local c = game.coords

    for i = 1, count do
        local model = models[math.random(1, #models)]
        local hash, loaded = loadModel(model)
        if loaded then
            local angle = ((math.pi * 2.0) / count) * i + (math.random() - 0.5) * 0.8
            local targetX = c.x + math.cos(angle) * radius
            local targetY = c.y + math.sin(angle) * radius
            local targetZ = groundZ(targetX, targetY, c.z)
            local spawnX = c.x + math.cos(angle) * (radius + spread + math.random())
            local spawnY = c.y + math.sin(angle) * (radius + spread + math.random())
            local spawnZ = groundZ(spawnX, spawnY, c.z)
            local heading = GetHeadingFromVector_2d(c.x - targetX, c.y - targetY)

            local ped = CreatePed(4, hash, spawnX, spawnY, spawnZ, heading, false, false)
            SetEntityAsMissionEntity(ped, true, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedCanRagdoll(ped, false)
            SetEntityInvincible(ped, true)
            SetPedFleeAttributes(ped, 0, false)
            SetPedCombatAttributes(ped, 17, true)
            TaskGoToCoordAnyMeans(ped, targetX, targetY, targetZ, 1.0, 0, false, 786603, 0xbf800000)

            CrowdPeds[game.id][#CrowdPeds[game.id] + 1] = ped
            SetTimeout(3500 + math.random(0, 1800), function()
                if DoesEntityExist(ped) then
                    SetEntityHeading(ped, heading)
                    TaskStartScenarioInPlace(ped, randomCrowdScenario(), 0, true)
                end
            end)
            SetModelAsNoLongerNeeded(hash)
        end
    end
end

local function cleanupGame(gameId)
    local shouldCloseUi = (MyGame == gameId or PendingOpenGame == gameId)
    local ped = BankPeds[gameId]
    if ped and DoesEntityExist(ped) then
        ClearPedTasks(ped)
        TaskWanderStandard(ped, 10.0, 10)
        SetTimeout(5000, function()
            if DoesEntityExist(ped) then DeleteEntity(ped) end
        end)
    end
    BankPeds[gameId] = nil
    BankScenarioState[gameId] = nil
    SceneLastSeen[gameId] = nil
    if CrowdPeds[gameId] then
        for _, ped in ipairs(CrowdPeds[gameId]) do
            if DoesEntityExist(ped) then
                ClearPedTasks(ped)
                TaskWanderStandard(ped, 10.0, 10)
                SetTimeout(5000, function()
                    if DoesEntityExist(ped) then DeleteEntity(ped) end
                end)
            end
        end
    end
    CrowdPeds[gameId] = nil
    ActiveGames[gameId] = nil
    if MyGame == gameId then MyGame = nil end
    if PendingOpenGame == gameId then PendingOpenGame = nil end
    if shouldCloseUi then
        sendUi('hide', {})
        SetNuiFocus(false, false)   -- v0.2.3: ensure cursor is released if the panel was open
    end
end

local function cleanupSpectatorScene(gameId)
    if MyGame == gameId then return end

    local ped = BankPeds[gameId]
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    BankPeds[gameId] = nil
    BankScenarioState[gameId] = nil

    if CrowdPeds[gameId] then
        for _, crowdPed in ipairs(CrowdPeds[gameId]) do
            if DoesEntityExist(crowdPed) then DeleteEntity(crowdPed) end
        end
    end
    CrowdPeds[gameId] = nil
    ActiveGames[gameId] = nil
    SceneLastSeen[gameId] = nil
    if PendingOpenGame == gameId then PendingOpenGame = nil end
end

-- ============================================================
--  Dice props (server is authoritative for face value; this just
--  spawns visual props and snaps them to the right rotation)
-- ============================================================
local diceRotations = {
    [1] = vector3(0.0, 0.0, 0.0),
    [2] = vector3(0.0, 90.0, 0.0),
    [3] = vector3(90.0, 0.0, 0.0),
    [4] = vector3(270.0, 0.0, 0.0),
    [5] = vector3(0.0, 270.0, 0.0),
    [6] = vector3(180.0, 0.0, 0.0)
}

-- ============================================================
--  Dice prop model cache (v0.3.19)
--  The old code called loadModel(Config.Dice.prop) inside makeDice/makeHandDice on
--  EVERY roll. If the prop is missing or slow to stream, each of those calls blocks
--  for up to ~5s, so the throw sequence stalled for many seconds and no dice ever
--  appeared - it looked like the ROLL button did nothing. We now load the model
--  ONCE, off the roll path, and cache it. The roll never blocks on it again, and if
--  no prop can load at all the on-screen NUI dice and the throw animation still play
--  so the roll is never silent.
-- ============================================================
local DiceModelHash = nil
local DiceModelReady = false
local DiceModelTried = false

local function ensureDiceModel()
    if DiceModelReady then return true end
    if DiceModelTried then return false end
    DiceModelTried = true

    local candidates = { Config.Dice.prop }
    if type(Config.Dice.propFallbacks) == 'table' then
        for _, m in ipairs(Config.Dice.propFallbacks) do candidates[#candidates + 1] = m end
    end

    for _, model in ipairs(candidates) do
        if model and model ~= '' then
            local hash, loaded = loadModel(model)
            if loaded then
                DiceModelHash = hash
                DiceModelReady = true
                dbg(('Dice prop loaded: %s'):format(model))
                return true
            end
        end
    end

    dbg('No dice prop model could be loaded; using on-screen dice only.')
    return false
end

-- Preload once, in the background, so the very first roll is instant.
CreateThread(function()
    Wait(500)
    ensureDiceModel()
end)

local function playDiceEffect(gameId, key)
    if not Config.Sounds or not Config.Sounds.enabled then return end
    local effects = Config.Sounds.effects or {}
    local file = effects[key]
    if not file or file == '' then return end

    local game = ActiveGames[gameId]
    if game and game.coords then
        local pc = GetEntityCoords(PlayerPedId())
        local gc = vector3(game.coords.x, game.coords.y, game.coords.z)
        if #(pc - gc) > ((Config.Sounds and Config.Sounds.audibleRadius) or 25.0) then return end
    end

    sendUi('sound', {
        file = file,
        volume = (Config.Sounds and Config.Sounds.volume) or 0.7
    })
end

local function deleteDiceObject(obj)
    if obj and obj ~= 0 and DoesEntityExist(obj) then
        SetEntityAsMissionEntity(obj, true, true)
        DetachEntity(obj, true, true)
        DeleteEntity(obj)
    end
end

local function playPickupAnim(ped)
    local dict = Config.Dice.pickupAnimDict or 'pickup_object'
    local name = Config.Dice.pickupAnimName or 'pickup_low'
    if dict and name and loadAnim(dict) then
        ClearPedSecondaryTask(ped)
        TaskPlayAnim(ped, dict, name,
            8.0, -8.0, Config.Dice.pickupAnimMs or 1200, 48, 0.0, false, false, false)
        return true
    end
    return false
end

local function attachPickupDiceToHand(ped, objects)
    local bone = GetPedBoneIndex(ped, 57005)
    local offsets = {
        { 0.060,  0.020, -0.006, 24.0, 14.0,  24.0 },
        { 0.083, -0.018, -0.006, 12.0, 8.0, 112.0 }
    }

    for i, obj in ipairs(objects or {}) do
        if DoesEntityExist(obj) then
            local o = offsets[((i - 1) % #offsets) + 1]
            SetEntityAsMissionEntity(obj, true, true)
            FreezeEntityPosition(obj, false)
            SetEntityCollision(obj, false, false)
            AttachEntityToEntity(obj, ped, bone,
                o[1], o[2], o[3],
                o[4], o[5], o[6],
                true, true, false, true, 1, true)
        end
    end
end

local function pickupDiceObjects(ped, objects, gameId)
    if not ped or not DoesEntityExist(ped) then
        for _, obj in ipairs(objects or {}) do
            deleteDiceObject(obj)
        end
        return
    end

    local firstObj
    for _, obj in ipairs(objects or {}) do
        if DoesEntityExist(obj) then
            firstObj = obj
            break
        end
    end

    if not firstObj then return end

    local oc = GetEntityCoords(firstObj)
    local animMs = Config.Dice.pickupAnimMs or 1200
    local grabDelay = Config.Dice.pickupGrabDelayMs or math.floor(animMs * 0.55)

    TaskTurnPedToFaceCoord(ped, oc.x, oc.y, oc.z, 450)
    SetTimeout(450, function()
        if DoesEntityExist(ped) then
            playPickupAnim(ped)
            playDiceEffect(gameId, 'pickup')
        end
    end)

    SetTimeout(450 + grabDelay, function()
        if DoesEntityExist(ped) then
            attachPickupDiceToHand(ped, objects)
            return
        end
        for _, obj in ipairs(objects or {}) do deleteDiceObject(obj) end
    end)

    SetTimeout(450 + animMs, function()
        for _, obj in ipairs(objects or {}) do deleteDiceObject(obj) end
        if DoesEntityExist(ped) then ClearPedSecondaryTask(ped) end
    end)
end

local function makeDice(coords, forward, result, cleanupGroup)
    if not DiceModelReady and not ensureDiceModel() then return end
    local obj = CreateObject(DiceModelHash, coords.x, coords.y, coords.z + 0.2, true, true, false)
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityCollision(obj, true, true)
    ActivatePhysics(obj)
    SetEntityVelocity(obj, forward.x * 2.8, forward.y * 2.8, 0.8)
    SetEntityAngularVelocity(obj,
        (math.random() - 0.5) * 16.0,
        (math.random() - 0.5) * 16.0,
        (math.random() - 0.5) * 16.0)
    ApplyForceToEntity(obj, 1, forward.x * 4.2, forward.y * 4.2, 1.15,
        math.random() * 0.35, math.random() * 0.35, 0.0, 0, false, true, true, false, true)
    DiceObjects[#DiceObjects + 1] = obj
    if cleanupGroup then cleanupGroup[#cleanupGroup + 1] = obj end

    SetTimeout(Config.Dice.rollVisualMs, function()
        if DoesEntityExist(obj) then
            local rot = diceRotations[result] or vector3(0.0, 0.0, 0.0)
            FreezeEntityPosition(obj, true)
            SetEntityRotation(obj, rot.x, rot.y, GetEntityHeading(obj) + rot.z, 2, true)
        end
    end)

    -- Model stays pinned in the cache (DiceModelHash); do not release it here.
    return obj
end

local function makeHandDice(ped, xOffset, yOffset)
    if not DiceModelReady and not ensureDiceModel() then return nil end
    local obj = CreateObject(DiceModelHash, 0.0, 0.0, 0.0, false, false, false)
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityCollision(obj, false, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, 57005),
        xOffset, yOffset, 0.0,
        18.0 + math.random(-8, 8), 12.0 + math.random(-8, 8), math.random(0, 180),
        true, true, false, true, 1, true)
    DiceObjects[#DiceObjects + 1] = obj
    return obj
end

local function playThrowAnim(ped)
    local dict = Config.Dice.throwAnimDict
    local name = Config.Dice.throwAnimName
    if dict and name and loadAnim(dict) then
        ClearPedSecondaryTask(ped)
        TaskPlayAnim(ped, dict, name,
            8.0, -8.0, Config.Dice.throwAnimMs or 1450, 49, 0.0, false, false, false)
        return true
    end

    -- Fallback is intentionally simple: even if a custom anim dict is missing,
    -- the player still visibly winds up and the hand dice still release.
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CHEERING', 0, true)
    SetTimeout(Config.Dice.throwAnimMs or 1450, function()
        if DoesEntityExist(ped) then ClearPedTasks(ped) end
    end)
    return false
end

local function playShooterThrow(gameId, shooterServerId, d1, d2)
    -- The on-screen dice + total must ALWAYS fire so a roll is never silent, even if
    -- the shooter ped is out of scope or the world dice prop could not load.
    local uiRolled = false
    local function pushUiRoll()
        if uiRolled then return end
        uiRolled = true
        sendUi('roll', { d1 = d1, d2 = d2, total = d1 + d2 })
    end

    local shooter = GetPlayerFromServerId(shooterServerId)
    local ped = (shooter ~= -1) and GetPlayerPed(shooter) or 0
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        pushUiRoll()
        return
    end

    -- Face the throw direction, then play the throw animation right away so it is
    -- unmistakably tied to pressing ROLL. Nothing below waits on the dice prop.
    local fwd = GetEntityForwardVector(ped)
    local face = GetEntityCoords(ped) + fwd * 2.0
    TaskTurnPedToFaceCoord(ped, face.x, face.y, face.z, 500)

    local handDie1, handDie2
    if DiceModelReady then
        handDie1 = makeHandDice(ped, 0.09, 0.025)
        handDie2 = makeHandDice(ped, 0.12, -0.025)
    end

    local turnDelay = 220
    local releaseMs = Config.Dice.releaseDelayMs or 760
    if releaseMs < (turnDelay + 380) then releaseMs = turnDelay + 380 end

    SetTimeout(turnDelay, function()
        if DoesEntityExist(ped) then
            playThrowAnim(ped)
            playDiceEffect(gameId, 'throw')
        end
    end)

    SetTimeout(releaseMs, function()
        deleteDiceObject(handDie1)
        deleteDiceObject(handDie2)
        pushUiRoll()   -- on-screen dice tumble in sync with the physical release
        if not DoesEntityExist(ped) then return end
        if not DiceModelReady then return end

        local base = GetEntityCoords(ped)
        local liveFwd = GetEntityForwardVector(ped)
        local thrownDice = {}
        makeDice(vector3(base.x + liveFwd.x * 1.05 - 0.15, base.y + liveFwd.y * 1.05 - 0.15, base.z), liveFwd, d1, thrownDice)
        makeDice(vector3(base.x + liveFwd.x * 1.05 + 0.15, base.y + liveFwd.y * 1.05 + 0.15, base.z), liveFwd, d2, thrownDice)

        SetTimeout(550, function()
            playDiceEffect(gameId, 'land')
        end)

        SetTimeout(Config.Game.dicePropLifetimeSeconds * 1000, function()
            pickupDiceObjects(ped, thrownDice, gameId)
        end)
    end)

    SetTimeout((Config.Dice.throwAnimMs or 1450) + turnDelay + 200, function()
        if DoesEntityExist(ped) then ClearPedSecondaryTask(ped) end
    end)
end

-- ============================================================
--  v0.2.3 UI focus helpers
--  Panel no longer auto-opens. It is opened via:
--    1. Press E at the Bank NPC (proximity prompt below)
--    2. /sdmenu command
--  In both cases the cursor is granted via SetNuiFocus(true, true).
-- ============================================================
local function openUi(gameId)
    local game = ActiveGames[gameId or MyGame]
    if not game then return end
    sendUi('uiConfig', Config.UI or {})
    sendUi('show', game)
    SetNuiFocus(true, true)
end

local function closeUi()
    sendUi('hide', {})
    SetNuiFocus(false, false)
end

-- ============================================================
--  Network: client receives
-- ============================================================
RegisterNetEvent('rs-streetdice:client:createScene', function(game)
    ActiveGames[game.id] = game
    SceneLastSeen[game.id] = GetGameTimer()
    spawnBank(game)
    if game.host == GetPlayerServerId(PlayerId()) then MyGame = game.id end
    -- v0.2.3: do NOT auto-show panel. Player must press E at the Bank or run /sdmenu.
    sendUi('uiConfig', Config.UI or {})
    sendUi('update', game)
end)

RegisterNetEvent('rs-streetdice:client:syncGame', function(gameId, game)
    -- gameId comes first because of how broadcast() prepends it
    ActiveGames[gameId] = game
    SceneLastSeen[gameId] = GetGameTimer()
    spawnBank(game)
    if game.bankArrived then
        snapBankToCircleIfNeeded(game)
        setBankScenario(gameId, bankScenarioForState(game))
        spawnCrowd(game)
    end

    -- v0.2.1 fix: any player listed in game.players (joiners included, not just host)
    -- needs MyGame set so /sdmenu and the close/reopen flow works for them.
    -- The server only broadcasts syncGame to players in game.players, so receiving
    -- this event at all is a strong signal the local player is in the circle.
    local myId = GetPlayerServerId(PlayerId())
    local confirmedInGame = false
    if game.players and game.players[tostring(myId)] then
        MyGame = gameId
        confirmedInGame = true
    elseif game.host == myId or game.shooter == myId then
        MyGame = gameId
        confirmedInGame = true
    end

    -- v0.2.3: send update for internal state only. The panel only becomes visible
    -- when the player explicitly opens it via E at the Bank or /sdmenu.
    sendUi('uiConfig', Config.UI or {})
    sendUi('update', game)

    -- v0.2.4: if the player pressed E to join, do not set MyGame/open UI
    -- optimistically. Wait until the server confirms membership through syncGame.
    if PendingOpenGame == gameId and confirmedInGame then
        PendingOpenGame = nil
        openUi(gameId)
    end
end)

RegisterNetEvent('rs-streetdice:client:bankHype', function(gameId, bucket, text, soundFile, audibleRadius, volume)
    -- Bank scenario flips
    if bucket == 'betting' or bucket == 'warning' then setBankScenario(gameId, Config.Bank.takingBetsScenario) end
    if bucket == 'locked' or bucket == 'natural' or bucket == 'hitpoint' then setBankScenario(gameId, Config.Bank.hypeScenario) end
    if bucket == 'payout' then setBankScenario(gameId, Config.Bank.payoutScenario) end
    if bucket == 'locked' or bucket == 'natural' or bucket == 'hitpoint' or bucket == 'sevenout' or bucket == 'craps' then
        setCrowdScenario(gameId, 'WORLD_HUMAN_CHEERING')
    elseif bucket == 'betting' or bucket == 'warning' or bucket == 'ambient' then
        setCrowdScenario(gameId, randomCrowdScenario())
    end

    -- UI hype banner
    sendUi('hype', { text = text, bucket = bucket })

    -- Sound playback gated by distance
    if soundFile and soundFile ~= '' then
        local game = ActiveGames[gameId]
        if game then
            local me = PlayerPedId()
            local mc = GetEntityCoords(me)
            local d = #(mc - vector3(game.coords.x, game.coords.y, game.coords.z))
            if d <= (audibleRadius or 25.0) then
                -- attenuate volume by distance
                local maxR = audibleRadius or 25.0
                local atten = 1.0 - (d / maxR) * 0.5  -- min 50% at edge
                if atten < 0.2 then atten = 0.2 end
                sendUi('sound', {
                    file = soundFile,
                    volume = (volume or 0.7) * atten
                })
            end
        end
    end
end)

RegisterNetEvent('rs-streetdice:client:playRoll', function(gameId, shooterSrc, d1, d2, point)
    local game = ActiveGames[gameId]
    if not game then return end
    setBankScenario(gameId, Config.Bank.hypeScenario)
    playShooterThrow(gameId, shooterSrc, d1, d2)
end)

RegisterNetEvent('rs-streetdice:client:payoutComplete', function(gameId, winnerSide, reason, paid)
    sendUi('result', { winnerSide = winnerSide, reason = reason, paid = paid })
    setBankScenario(gameId, Config.Bank.payoutScenario)
end)

RegisterNetEvent('rs-streetdice:client:cleanupScene', function(gameId)
    cleanupGame(gameId or MyGame)
end)


local function cleanupLocalStreetDicePeds(radius)
    radius = radius or 18.0
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local modelSet = {}

    local function addModels(list)
        if type(list) ~= 'table' then return end
        for _, model in ipairs(list) do modelSet[joaat(model)] = true end
    end

    addModels(Config.Bank and Config.Bank.models)
    addModels(Config.Crowd and Config.Crowd.models)

    for _, ped in pairs(BankPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    BankPeds = {}
    BankScenarioState = {}

    for _, crowd in pairs(CrowdPeds) do
        for _, ped in ipairs(crowd) do
            if DoesEntityExist(ped) then DeleteEntity(ped) end
        end
    end
    CrowdPeds = {}

    local handle, ped = FindFirstPed()
    local success = true
    local removed = 0
    repeat
        if ped and ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            local pc = GetEntityCoords(ped)
            if #(pc - mc) <= radius and modelSet[GetEntityModel(ped)] then
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
                removed = removed + 1
            end
        end
        success, ped = FindNextPed(handle)
    until not success
    EndFindPed(handle)

    notify(('Cleared %s local street dice NPC(s).'):format(removed), 'primary')
end

RegisterCommand('sdclearpeds', function()
    cleanupLocalStreetDicePeds(25.0)
end, false)

-- ============================================================
--  Local commands / NUI callbacks
-- ============================================================
RegisterCommand('sdmenu', function()
    if MyGame and ActiveGames[MyGame] then
        openUi(MyGame)
    else
        notify('Walk up to The Bank and press E, or use /streetdice first.', 'error')
    end
end, false)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb('ok')
end)

RegisterNUICallback('join', function(_, cb)
    TriggerServerEvent('rs-streetdice:server:joinNearest')
    cb('ok')
end)

RegisterNUICallback('bet', function(data, cb)
    TriggerServerEvent('rs-streetdice:server:placeBet', data.amount, data.side)
    cb('ok')
end)

RegisterNUICallback('roll', function(_, cb)
    TriggerServerEvent('rs-streetdice:server:roll')
    cb('ok')
end)

RegisterNUICallback('endGame', function(_, cb)
    TriggerServerEvent('rs-streetdice:server:endGame')
    cb('ok')
end)

RegisterNUICallback('focus', function(data, cb)
    SetNuiFocus(data and data.focus or false, data and data.focus or false)
    cb('ok')
end)

-- v0.3.14: nearby spectators receive periodic scene presence from the server.
-- If a non-member stops receiving it, clean up their local Bank/crowd/marker.
CreateThread(function()
    while true do
        Wait(2000)
        local now = GetGameTimer()
        local staleMs = Config.Game.sceneStaleMs or 9000
        for gameId, seenAt in pairs(SceneLastSeen) do
            if MyGame ~= gameId and (now - seenAt) > staleMs then
                cleanupSpectatorScene(gameId)
            end
        end
    end
end)

-- ============================================================
--  v0.2.3 Proximity loop
--  Two things happen here:
--    1. Draw the chalk circle marker on the ground for any active game within 35m.
--    2. Show "Press E" help text when within bankInteractDistance of the nearest
--       Bank NPC. Pressing E opens the panel with cursor focus. If the player is
--       not in the game yet, E also triggers a server-side join.
--  Sleep time scales so we only burn frames when something is nearby.
-- ============================================================
CreateThread(function()
    while true do
        local sleep = 1000
        local mycoords = GetEntityCoords(PlayerPedId())

        -- 1) Find the nearest Bank ped across all active games
        local nearestBankGameId, nearestBankDist
        for gameId, ped in pairs(BankPeds) do
            if DoesEntityExist(ped) then
                local pc = GetEntityCoords(ped)
                local d = #(mycoords - pc)
                if d < 35.0 then sleep = 0 end
                if d < (Config.Game.bankInteractDistance or 2.8)
                   and (not nearestBankDist or d < nearestBankDist) then
                    nearestBankGameId = gameId
                    nearestBankDist = d
                end
            end
        end

        -- 2) Draw chalk markers for nearby game circles
        for _, game in pairs(ActiveGames) do
            local gcoords = vector3(game.coords.x, game.coords.y, game.coords.z)
            local distance = #(mycoords - gcoords)
            if distance < 35.0 then
                sleep = 0
                drawMarkerCircle(gcoords)
            end
        end

        -- 3) Press-E prompt at the nearest Bank NPC
        if nearestBankGameId then
            local game = ActiveGames[nearestBankGameId]
            if game and game.bankArrived then
                local imHostOrIn = (MyGame == nearestBankGameId)
                local helpText
                if imHostOrIn then
                    helpText = 'Press ~INPUT_CONTEXT~ to talk to The Bank'
                else
                    helpText = 'Press ~INPUT_CONTEXT~ to join street dice'
                end
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(helpText)
                EndTextCommandDisplayHelp(0, false, true, -1)

                if IsControlJustPressed(0, 38) then  -- E key
                    if not imHostOrIn then
                        -- v0.2.4: request join only. Do not set MyGame or open the
                        -- panel until the server confirms this player in syncGame.
                        PendingOpenGame = nearestBankGameId
                        TriggerServerEvent('rs-streetdice:server:joinNearest')
                    else
                        openUi(nearestBankGameId)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ============================================================
--  Cleanup ped on resource stop
-- ============================================================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, ped in pairs(BankPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    for _, crowd in pairs(CrowdPeds) do
        for _, ped in ipairs(crowd) do
            if DoesEntityExist(ped) then DeleteEntity(ped) end
        end
    end
    for _, obj in pairs(DiceObjects) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
end)
