local Bridge = {
    name = 'standalone',
    core = nil,
    balances = {}
}

local function bridgeLog(msg)
    if Config.Debug then print(msg) end
end

local function resourceStarted(name)
    return GetResourceState(name) == 'started'
end

local function initBridge()
    local wanted = tostring((Config.Bridge and Config.Bridge.framework) or Config.Framework or 'auto'):lower()

    if (wanted == 'auto' or wanted == 'qbcore' or wanted == 'qb') and resourceStarted('qb-core') then
        Bridge.name = 'qbcore'
        Bridge.core = exports['qb-core']:GetCoreObject()
        bridgeLog('[rs-streetdice] Bridge: qb-core detected')
        return
    end

    if (wanted == 'auto' or wanted == 'qbox' or wanted == 'qbx') and resourceStarted('qbx_core') then
        Bridge.name = 'qbox'
        Bridge.core = exports.qbx_core
        bridgeLog('[rs-streetdice] Bridge: qbx_core detected')
        return
    end

    if (wanted == 'auto' or wanted == 'esx') and resourceStarted('es_extended') then
        Bridge.name = 'esx'
        Bridge.core = exports['es_extended']:getSharedObject()
        bridgeLog('[rs-streetdice] Bridge: es_extended detected')
        return
    end

    Bridge.name = 'standalone'
    bridgeLog('[rs-streetdice] Bridge: standalone fallback active')
end

initBridge()

-- Runtime game state.
-- These MUST be local tables before any game/betting/background loop runs.
-- The bridge rebuild accidentally dropped these declarations, which caused
-- startup cleanup threads to call pairs(nil) on Games.
local Games = {}
local PlayerGame = {}
local NextGameId = 1

local function bridgeNotify(src, msg, msgType)
    if Bridge.name == 'qbcore' then
        TriggerClientEvent('QBCore:Notify', src, msg, msgType or 'primary')
    elseif Bridge.name == 'qbox' then
        TriggerClientEvent('ox_lib:notify', src, { description = msg, type = msgType or 'inform' })
    elseif Bridge.name == 'esx' then
        TriggerClientEvent('esx:showNotification', src, msg)
    else
        TriggerClientEvent('chat:addMessage', src, { args = { 'Street Dice', msg } })
    end
end

local function bridgeGetPlayer(src)
    if Bridge.name == 'qbcore' and Bridge.core then
        return Bridge.core.Functions.GetPlayer(src)
    elseif Bridge.name == 'qbox' and Bridge.core and Bridge.core.GetPlayer then
        return Bridge.core:GetPlayer(src) or Bridge.core.GetPlayer(src)
    elseif Bridge.name == 'esx' and Bridge.core then
        return Bridge.core.GetPlayerFromId(src)
    else
        if not Bridge.balances[src] then
            Bridge.balances[src] = (Config.Bridge and Config.Bridge.standaloneStartingCash) or 10000
        end
        return { source = src, standalone = true }
    end
end

local function bridgeGetName(src, Player)
    if Bridge.name == 'qbcore' and Player and Player.PlayerData then
        local ci = Player.PlayerData.charinfo
        if ci and ci.firstname then return (ci.firstname .. ' ' .. (ci.lastname or '')) end
    elseif Bridge.name == 'qbox' and Player then
        local data = Player.PlayerData or Player
        local ci = data.charinfo
        if ci and ci.firstname then return (ci.firstname .. ' ' .. (ci.lastname or '')) end
    elseif Bridge.name == 'esx' and Player then
        return Player.getName and Player.getName() or GetPlayerName(src)
    end
    return GetPlayerName(src) or ('Player %s'):format(src)
end

local function bridgeGetMoney(src, Player)
    local account = Config.Money.type or 'cash'
    if Bridge.name == 'qbcore' and Player and Player.Functions then
        return Player.Functions.GetMoney(account) or 0
    elseif Bridge.name == 'qbox' then
        if exports.qbx_core and exports.qbx_core.GetMoney then
            return exports.qbx_core:GetMoney(src, account) or 0
        end
        local data = Player and (Player.PlayerData or Player)
        return (data and data.money and data.money[account]) or 0
    elseif Bridge.name == 'esx' and Player then
        if account == 'cash' or account == 'money' then return Player.getMoney() or 0 end
        local acc = Player.getAccount(account)
        return (acc and acc.money) or 0
    else
        Bridge.balances[src] = Bridge.balances[src] or ((Config.Bridge and Config.Bridge.standaloneStartingCash) or 10000)
        return Bridge.balances[src]
    end
end

local function bridgeRemoveMoney(src, amount, reason)
    local Player = bridgeGetPlayer(src)
    if not Player then return false end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    if bridgeGetMoney(src, Player) < amount then return false end

    local account = Config.Money.type or 'cash'
    if Bridge.name == 'qbcore' and Player.Functions then
        return Player.Functions.RemoveMoney(account, amount, reason or 'street-dice') == true
    elseif Bridge.name == 'qbox' then
        if exports.qbx_core and exports.qbx_core.RemoveMoney then
            return exports.qbx_core:RemoveMoney(src, account, amount, reason or 'street-dice') == true
        end
        return false
    elseif Bridge.name == 'esx' then
        if account == 'cash' or account == 'money' then Player.removeMoney(amount) else Player.removeAccountMoney(account, amount) end
        return true
    else
        Bridge.balances[src] = (Bridge.balances[src] or 0) - amount
        return true
    end
end

local function bridgeAddMoney(src, amount, reason)
    local Player = bridgeGetPlayer(src)
    if not Player then return false end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local account = Config.Money.type or 'cash'
    if Bridge.name == 'qbcore' and Player.Functions then
        Player.Functions.AddMoney(account, amount, reason or 'street-dice')
        return true
    elseif Bridge.name == 'qbox' then
        if exports.qbx_core and exports.qbx_core.AddMoney then
            return exports.qbx_core:AddMoney(src, account, amount, reason or 'street-dice') == true
        end
        return false
    elseif Bridge.name == 'esx' then
        if account == 'cash' or account == 'money' then Player.addMoney(amount) else Player.addAccountMoney(account, amount) end
        return true
    else
        Bridge.balances[src] = (Bridge.balances[src] or ((Config.Bridge and Config.Bridge.standaloneStartingCash) or 10000)) + amount
        return true
    end
end

local function bridgeGetPlayers()
    local list = {}
    for _, id in ipairs(GetPlayers()) do list[#list + 1] = tonumber(id) end
    return list
end
-- ============================================================
--  Boot: seed Lua RNG
--  Without this every restart starts the same dice sequence.
-- ============================================================
math.randomseed(os.time() + GetGameTimer())
for _ = 1, 10 do math.random() end

local function debugPrint(msg)
    if Config.Debug then print(('[rs-streetdice] %s'):format(msg)) end
end

local function notify(src, msg, msgType)
    bridgeNotify(src, msg, msgType)
end

local function getPlayer(src)
    return bridgeGetPlayer(src)
end

local function getPlayerCash(srcOrPlayer, maybePlayer)
    if type(srcOrPlayer) == 'number' then
        return bridgeGetMoney(srcOrPlayer, maybePlayer)
    end
    return 0
end

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Server-side coord read: do NOT trust client-supplied coords.
local function getSrcCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local v = GetEntityCoords(ped)
    return { x = v.x, y = v.y, z = v.z }
end

local function broadcast(game, eventName, ...)
    for src in pairs(game.players) do
        TriggerClientEvent(eventName, src, game.id, ...)
    end
end

-- v0.2.0: limit createScene to nearby players instead of -1.
-- This sends with NO leading game id (createScene handler reads id from the payload).
local function broadcastNearby(game, eventName, ...)
    local players = bridgeGetPlayers()
    local gc = game.coords
    local renderDist = (Config.Game.sceneRenderDistance or 70.0)
    for _, src in ipairs(players) do
        local pc = getSrcCoords(src)
        if pc and dist(pc, gc) <= renderDist then
            TriggerClientEvent(eventName, src, ...)
        end
    end
end

-- v0.3.14: scene presence for members AND nearby spectators with one uniform
-- (gameId, ...) signature (id is prepended, like broadcast()). This is what lets
-- non-members receive bank arrival, live state, and cleanup so they can see and
-- join the circle. Members always receive it even if they briefly wander out of
-- render range, preserving the old members-only guarantee.
local function broadcastSceneNearby(game, eventName, ...)
    local gc = game.coords
    local renderDist = (Config.Game.sceneRenderDistance or 70.0)
    local sent = {}
    for _, src in ipairs(bridgeGetPlayers()) do
        local pc = getSrcCoords(src)
        if pc and dist(pc, gc) <= renderDist then
            TriggerClientEvent(eventName, src, game.id, ...)
            sent[src] = true
        end
    end
    for psrc in pairs(game.players) do
        if not sent[psrc] then
            TriggerClientEvent(eventName, psrc, game.id, ...)
        end
    end
end

local function publicGame(game)
    local bets = {}
    for src, bet in pairs(game.bets) do
        bets[tostring(src)] = { amount = bet.amount, side = bet.side, name = bet.name }
    end
    -- v0.2.1: expose player list so the client can detect membership and set MyGame
    -- for joiners (not just the host).
    local players = {}
    for src in pairs(game.players) do
        players[tostring(src)] = true
    end
    local shooterName = GetPlayerName(game.shooter) or 'Shooter'
    local coveredAction = math.min(game.totalWith or 0, game.totalAgainst or 0)
    local unmatchedAction = math.abs((game.totalWith or 0) - (game.totalAgainst or 0))
    local npcBankCoverage = Config.Money and Config.Money.allowNpcBankCoverage == true
    local npcCoverSide, npcCoverAmount = nil, 0
    if npcBankCoverage and unmatchedAction > 0 then
        if (game.totalWith or 0) > (game.totalAgainst or 0) then
            npcCoverSide = 'against' -- The Bank is fading the shooter to cover RIDE action
            npcCoverAmount = unmatchedAction
        elseif (game.totalAgainst or 0) > (game.totalWith or 0) then
            npcCoverSide = 'with' -- The Bank is riding to cover FADE action
            npcCoverAmount = unmatchedAction
        end
    end
    return {
        id = game.id,
        host = game.host,
        shooter = game.shooter,
        shooterName = shooterName,
        state = game.state,
        point = game.point,
        pot = game.pot,
        coords = game.coords,
        bankModel = game.bankModel,
        bankArrived = game.bankArrived,
        bettingEndsAt = game.bettingEndsAt,
        bets = bets,
        players = players,
        totalWith = game.totalWith or 0,
        totalAgainst = game.totalAgainst or 0,
        coveredAction = coveredAction,
        unmatchedAction = unmatchedAction,
        npcBankCoverage = npcBankCoverage,
        npcCoverSide = npcCoverSide,
        npcCoverAmount = npcCoverAmount,
        npcBankroll = game.npcBankroll or 0
    }
end

local function syncGame(game)
    -- v0.3.14: was members-only (broadcast). Now reaches nearby spectators too so
    -- they get bank arrival, the live ledger, and can join via the E prompt.
    broadcastSceneNearby(game, 'rs-streetdice:client:syncGame', publicGame(game))
end

local function chooseBankModel()
    return Config.Bank.models[math.random(1, #Config.Bank.models)]
end

local function hasAnyBets(game)
    for _ in pairs(game.bets) do return true end
    return false
end

local function recomputeTotals(game)
    local with, against, pot = 0, 0, 0
    for _, bet in pairs(game.bets) do
        pot = pot + bet.amount
        if bet.side == 'with' then with = with + bet.amount else against = against + bet.amount end
    end
    game.totalWith = with
    game.totalAgainst = against
    game.pot = pot
end

local function countConcurrentGames()
    local n = 0
    for _ in pairs(Games) do n = n + 1 end
    return n
end

-- ============================================================
--  Hype broadcaster with cooldown + sound picker
-- ============================================================
local function pickSoundFile(bucket)
    if not Config.Sounds or not Config.Sounds.enabled then return nil end
    local files = Config.Sounds.files and Config.Sounds.files[bucket]
    if not files or #files == 0 then return nil end
    return files[math.random(1, #files)]
end

local function pickHypeLine(bucket)
    local lines = Config.Hype.lines[bucket]
    if not lines or #lines == 0 then return '' end
    return lines[math.random(1, #lines)]
end

local function fireHype(game, bucket, fallbackText)
    if not game then return end
    if not Config.Hype.enabled then return end
    local nowMs = GetGameTimer()
    if game.lastHypeMs and (nowMs - game.lastHypeMs) < (Config.Hype.cooldownMs or 0) then
        return
    end
    game.lastHypeMs = nowMs

    local text = pickHypeLine(bucket)
    if text == '' then text = fallbackText or '' end
    local sound = pickSoundFile(bucket)
    local radius = (Config.Sounds and Config.Sounds.audibleRadius) or 25.0
    local volume = (Config.Sounds and Config.Sounds.volume) or 0.7

    broadcastSceneNearby(game, 'rs-streetdice:client:bankHype', bucket, text, sound, radius, volume)
end

-- ============================================================
--  Helpers
-- ============================================================
local function passDiceTo(game, currentShooter)
    local order = game.playerOrder or {}
    if #order > 0 then
        local currentIndex = 0
        for i, src in ipairs(order) do
            if src == currentShooter then currentIndex = i break end
        end
        for offset = 1, #order do
            local idx = ((currentIndex + offset - 1) % #order) + 1
            local candidate = order[idx]
            if candidate ~= currentShooter and game.players[candidate] then
                return candidate
            end
        end
    end

    for src in pairs(game.players) do
        if src ~= currentShooter then return src end
    end
    return currentShooter
end

local function removeFromPlayerOrder(game, src)
    if not game.playerOrder then return end
    for i = #game.playerOrder, 1, -1 do
        if game.playerOrder[i] == src then
            table.remove(game.playerOrder, i)
        end
    end
end

local function refundAllBets(game, reason)
    for src, bet in pairs(game.bets) do
        local Player = getPlayer(src)
        if Player then
            bridgeAddMoney(src, bet.amount, 'street-dice-refund')
            notify(src, ('Refunded $%s from street dice (%s).'):format(bet.amount, reason or 'cancelled'), 'primary')
        end
    end
    game.bets = {}
    game.pot = 0
    game.totalWith = 0
    game.totalAgainst = 0
end

-- ============================================================
--  Payout
--  Bug fix v0.2.0: clears game.point so the next round always
--  starts in comeout regardless of how the previous round ended.
-- ============================================================
local function payout(game, winnerSide, reason)
    game.state = 'payout'
    recomputeTotals(game)
    syncGame(game)
    fireHype(game, 'payout', reason or 'Paying out')

    local winnerTotal = winnerSide == 'with' and game.totalWith or game.totalAgainst
    local loserTotal = winnerSide == 'with' and game.totalAgainst or game.totalWith
    local neededNpcCover = 0

    -- v0.3.13: optional NPC Bank coverage for solo/small games.
    -- If enabled, The Bank covers missing action up to its configured bankroll.
    -- If disabled and nobody is on the winning side, the round pushes/refunds so money is never burned.
    local bankCovers = Config.Money and Config.Money.allowNpcBankCoverage == true
    local noWinners = winnerTotal <= 0
    local bankWins = noWinners and bankCovers and loserTotal > 0

    if bankCovers and not noWinners and loserTotal < winnerTotal then
        neededNpcCover = winnerTotal - loserTotal
        if neededNpcCover > (game.npcBankroll or 0) then
            neededNpcCover = game.npcBankroll or 0
        end
        loserTotal = loserTotal + neededNpcCover
        game.npcBankroll = (game.npcBankroll or 0) - neededNpcCover
    end

    local paid = {}
    for src, bet in pairs(game.bets) do
        local Player = getPlayer(src)
        if Player then
            if bankWins then
                paid[#paid + 1] = { src = src, amount = bet.amount, result = 'bank_win' }
                notify(src, ('You lost $%s to The Bank.'):format(bet.amount), 'error')
            elseif noWinners then
                bridgeAddMoney(src, bet.amount, 'street-dice-push-refund')
                paid[#paid + 1] = { src = src, amount = bet.amount, result = 'push' }
                notify(src, ('Bet refunded ($%s). No one was on the winning side.'):format(bet.amount), 'primary')
            elseif bet.side == winnerSide then
                local profit = 0
                if winnerTotal > 0 then
                    profit = math.floor((bet.amount / winnerTotal) * loserTotal)
                end
                local payoutAmount = bet.amount + profit
                bridgeAddMoney(src, payoutAmount, 'street-dice-win')
                paid[#paid + 1] = { src = src, amount = payoutAmount, result = 'win' }
                notify(src, ('You won $%s from street dice.'):format(payoutAmount), 'success')
            else
                paid[#paid + 1] = { src = src, amount = bet.amount, result = 'lose' }
                notify(src, ('You lost $%s in street dice.'):format(bet.amount), 'error')
            end
        end
    end

    game.bets = {}
    game.pot = 0
    game.totalWith = 0
    game.totalAgainst = 0
    game.point = nil          -- v0.2.0 fix
    game.roundLocked = false
    game.allBetsSettled = true
    game.payoutQueueEmpty = true
    game.state = 'round_over'
    game.lastActivity = os.time()
    game.bettingWarned = false
    game.bettingEndsAt = nil

    local effectiveReason = reason or 'Round settled'
    if bankWins then
        effectiveReason = effectiveReason .. ' - The Bank eats'
    elseif noWinners then
        effectiveReason = effectiveReason .. ' - push (no winners)'
    elseif neededNpcCover > 0 then
        effectiveReason = effectiveReason .. (' - The Bank covered $%s'):format(neededNpcCover)
    end

    broadcastSceneNearby(game, 'rs-streetdice:client:payoutComplete', winnerSide, effectiveReason, paid)
    syncGame(game)
end

local function resolveRoll(game, phase, d1, d2)
    -- v0.2.1: 'phase' is the captured pre-roll phase ('comeout' or 'point').
    -- game.state is currently 'rolling' until we either payout (sets 'round_over')
    -- or transition to 'point' / continue in 'point'.
    local total = d1 + d2
    if phase == 'comeout' then
        if total == 7 or total == 11 then
            payout(game, 'with', ('Natural %s'):format(total))
            fireHype(game, 'natural', ('Natural %s'):format(total))
            return
        elseif total == 2 or total == 3 or total == 12 then
            local previousShooter = game.shooter
            payout(game, 'against', ('Craps %s'):format(total))
            fireHype(game, 'craps', ('Craps %s'):format(total))
            if Config.Game.passDiceOnComeoutCraps then
                local newShooter = passDiceTo(game, previousShooter)
                if newShooter and newShooter ~= previousShooter then
                    game.shooter = newShooter
                    notify(newShooter, 'You are the new shooter. Roll when ready.', 'primary')
                    syncGame(game)
                end
            end
            return
        else
            game.point = total
            game.state = 'point'
            game.roundLocked = false
            game.lastActivity = os.time()
            fireHype(game, 'point', ('Point is %s'):format(total))
            syncGame(game)
            return
        end
    elseif phase == 'point' then
        if total == game.point then
            local pt = game.point
            payout(game, 'with', ('Point hit: %s'):format(pt))
            fireHype(game, 'hitpoint', ('Point hit %s'):format(pt))
            return
        elseif total == 7 then
            local previousShooter = game.shooter
            payout(game, 'against', 'Seven out')
            fireHype(game, 'sevenout', 'Seven out')
            if Config.Game.passDiceOnSevenOut then
                local newShooter = passDiceTo(game, previousShooter)
                if newShooter and newShooter ~= previousShooter then
                    game.shooter = newShooter
                    notify(newShooter, 'You are the new shooter. Roll when ready.', 'primary')
                    syncGame(game)
                end
            end
            return
        else
            -- non-resolving roll: stay in point phase, release the roll lock
            game.state = 'point'
            game.roundLocked = false
            game.lastActivity = os.time()
            syncGame(game)
            return
        end
    end
end

-- ============================================================
--  Game lifecycle
-- ============================================================
local function destroyGame(gameId, broadcastCleanup)
    local game = Games[gameId]
    if not game then return end
    -- v0.3.14: cleanup also reaches nearby spectators so a bystander who rendered
    -- the scene does not leak the Bank ped/marker after the game ends.
    if broadcastCleanup then broadcastSceneNearby(game, 'rs-streetdice:client:cleanupScene') end
    for playerSrc in pairs(game.players) do
        if PlayerGame[playerSrc] == gameId then PlayerGame[playerSrc] = nil end
    end
    Games[gameId] = nil
end

local function createGame(src, coords)
    if PlayerGame[src] then
        notify(src, 'You are already in a dice game.', 'error')
        return
    end
    if countConcurrentGames() >= (Config.Game.maxConcurrentGames or 6) then
        notify(src, 'Too many dice games running on the server right now. Try again later.', 'error')
        return
    end

    local game = {
        id = NextGameId,
        host = src,
        shooter = src,
        coords = coords,
        state = 'waiting_for_bank',
        point = nil,
        pot = 0,
        totalWith = 0,
        totalAgainst = 0,
        bets = {},
        players = { [src] = true },
        playerOrder = { src },
        bankModel = chooseBankModel(),
        bankArrived = false,
        roundLocked = false,
        allBetsSettled = true,
        payoutQueueEmpty = true,
        npcBankroll = Config.Money.npcBankrollPerGame,
        createdAt = os.time(),
        lastActivity = os.time(),
        lastHypeMs = 0,
        bettingWarned = false,
        nextAmbientMs = nil
    }

    Games[game.id] = game
    PlayerGame[src] = game.id
    NextGameId = NextGameId + 1

    broadcastNearby(game, 'rs-streetdice:client:createScene', publicGame(game))
    notify(src, 'Street dice started. Wait for The Bank to walk in.', 'success')
    fireHype(game, 'bank_arriving', 'Bank coming over')

    SetTimeout(Config.Game.bankArriveDelaySeconds * 1000, function()
        local live = Games[game.id]
        if not live then return end
        live.bankArrived = true
        live.state = 'betting'
        live.bettingEndsAt = os.time() + Config.Game.bettingSeconds
        live.lastActivity = os.time()
        syncGame(live)
        fireHype(live, 'betting', 'Place your bets')
    end)
end

local function joinNearest(src)
    if PlayerGame[src] then notify(src, 'You are already in a dice game.', 'error') return end
    local coords = getSrcCoords(src)
    if not coords then return end

    local nearest, nearestDist
    for _, game in pairs(Games) do
        local d = dist(coords, game.coords)
        if d <= Config.Game.joinRadius and (not nearestDist or d < nearestDist) then
            nearest, nearestDist = game, d
        end
    end
    if not nearest then notify(src, 'No street dice game nearby.', 'error') return end
    nearest.players[src] = true
    nearest.playerOrder = nearest.playerOrder or {}
    nearest.playerOrder[#nearest.playerOrder + 1] = src
    PlayerGame[src] = nearest.id
    nearest.lastActivity = os.time()
    syncGame(nearest)
    notify(src, 'You joined the dice circle.', 'success')
end

local function placeBet(src, amount, side)
    amount = tonumber(amount)
    if amount then amount = math.floor(amount) end
    side = tostring(side or ''):lower()

    local gameId = PlayerGame[src]
    local game = gameId and Games[gameId]
    if not game then notify(src, 'You are not in a dice game.', 'error') return end
    if game.state ~= 'betting' and game.state ~= 'round_over' and game.state ~= 'point' then notify(src, 'Bets are closed.', 'error') return end
    -- By default the timer is pacing/warning only. Street dice flow is gated by
    -- covered action, not a hard clock. Servers can opt into a hard deadline.
    if Config.Game.enforceBettingDeadline and game.state == 'betting' and game.bettingEndsAt and os.time() > game.bettingEndsAt then
        notify(src, 'Bets are closed.', 'error') return
    end
    if Config.Game.requireBankArrivedBeforeBets and not game.bankArrived then notify(src, 'The Bank is not here yet.', 'error') return end

    local coords = getSrcCoords(src)
    if not coords or dist(coords, game.coords) > Config.Game.joinRadius + 2.0 then
        notify(src, 'You are too far from the dice circle.', 'error') return
    end

    if side ~= 'with' and side ~= 'against' then notify(src, 'Bet side must be with or against.', 'error') return end
    if src == game.shooter and Config.Game.shooterBetSide and side ~= Config.Game.shooterBetSide then
        notify(src, 'Shooter has to ride with their own roll.', 'error')
        return
    end
    if not amount or amount < Config.Money.minBet or amount > Config.Money.maxBet then
        notify(src, ('Bet must be between $%s and $%s.'):format(Config.Money.minBet, Config.Money.maxBet), 'error')
        return
    end
    local existingBet = game.bets[src]
    if existingBet and existingBet.side ~= side then
        notify(src, 'Your money is already on the other side this round.', 'error')
        return
    end
    if existingBet and (existingBet.amount + amount) > Config.Money.maxBet then
        notify(src, ('Your total bet cannot go over $%s.'):format(Config.Money.maxBet), 'error')
        return
    end

    local Player = getPlayer(src)
    if not Player then return end
    if bridgeGetMoney(src, Player) < amount then notify(src, 'Not enough cash.', 'error') return end

    if not bridgeRemoveMoney(src, amount, 'street-dice-pot') then
        notify(src, 'Could not remove cash.', 'error')
        return
    end

    if existingBet then
        existingBet.amount = existingBet.amount + amount
    else
        game.bets[src] = {
            amount = amount,
            side = side,
            name = bridgeGetName(src, Player)
        }
    end
    game.allBetsSettled = false
    recomputeTotals(game)
    if game.state == 'round_over' then
        game.state = 'betting'
        game.bettingEndsAt = os.time() + Config.Game.bettingSeconds
        game.bettingWarned = false
    end
    game.lastActivity = os.time()
    syncGame(game)
    local sideText = side == 'with' and 'riding with the shooter' or 'fading the shooter'
    notify(src, ('Money down: $%s %s.'):format(amount, sideText), 'success')
end

local function rollDice(src)
    local gameId = PlayerGame[src]
    local game = gameId and Games[gameId]
    if not game then notify(src, 'You are not in a dice game.', 'error') return end
    if src ~= game.shooter then notify(src, 'Only the shooter can roll.', 'error') return end

    -- v0.2.1 fix: prevent roll spam during the dice animation window.
    -- Without this, the shooter could fire /sdroll twice and resolveRoll would run twice
    -- on the same bets, double-paying or wrecking payouts.
    if game.roundLocked or game.state == 'rolling' then
        notify(src, 'Dice are already rolling.', 'error') return
    end

    if Config.Game.shooterMustBet and not game.bets[src] then
        notify(src, 'Put your own money down before you shoot.', 'error') return
    end
    if game.bets[src] and Config.Game.shooterBetSide and game.bets[src].side ~= Config.Game.shooterBetSide then
        notify(src, 'Shooter has to ride with their own roll.', 'error') return
    end

    local phase = game.state
    if game.state == 'betting' or game.state == 'round_over' then
        if not hasAnyBets(game) then notify(src, 'No bets placed yet.', 'error') return end
        phase = game.point and 'point' or 'comeout'
    end
    if phase ~= 'comeout' and phase ~= 'point' then notify(src, 'You cannot roll right now.', 'error') return end

    recomputeTotals(game)
    local bankCoversAction = Config.Money and Config.Money.allowNpcBankCoverage == true
    local coverShort = math.abs((game.totalWith or 0) - (game.totalAgainst or 0))
    if Config.Game.requireFadeToRoll and (game.totalAgainst or 0) <= 0 and not bankCoversAction then
        notify(src, 'Nobody faded you yet. Get your bet covered.', 'error') return
    end
    if bankCoversAction and coverShort > (game.npcBankroll or 0) then
        notify(src, ('The Bank cannot cover that much action. Short: $%s, bankroll: $%s.'):format(coverShort, game.npcBankroll or 0), 'error') return
    end
    if Config.Game.requireCoveredAction and (game.totalWith or 0) ~= (game.totalAgainst or 0) and not bankCoversAction then
        notify(src, ('Action is not covered. Riding: $%s, fading: $%s.'):format(game.totalWith or 0, game.totalAgainst or 0), 'error') return
    end

    local coords = getSrcCoords(src)
    if not coords or dist(coords, game.coords) > Config.Game.joinRadius + 2.0 then
        notify(src, 'You are too far from the dice circle.', 'error') return
    end

    local d1, d2 = math.random(1, 6), math.random(1, 6)

    -- v0.2.1: capture the phase BEFORE flipping to 'rolling' so resolveRoll knows
    -- whether to run comeout or point logic. game.state is no longer the source of truth.
    game.state = 'rolling'
    game.roundLocked = true
    game.lastActivity = os.time()
    fireHype(game, 'locked', 'Bets locked')
    syncGame(game)
    broadcastSceneNearby(game, 'rs-streetdice:client:playRoll', src, d1, d2, game.point)

    SetTimeout(Config.Dice.rollVisualMs + 350, function()
        local live = Games[game.id]
        if not live then return end
        resolveRoll(live, phase, d1, d2)
    end)
end

local function tryEndGame(src)
    local gameId = PlayerGame[src]
    local game = gameId and Games[gameId]
    if not game then notify(src, 'You are not in a dice game.', 'error') return end
    if src ~= game.host then notify(src, 'Only the host can end this dice game.', 'error') return end
    if game.pot > 0 or game.state == 'rolling' or game.state == 'payout' or not game.allBetsSettled or not game.payoutQueueEmpty then
        notify(src, 'Game cannot end until The Bank pays everyone out.', 'error')
        return
    end
    if hasAnyBets(game) then notify(src, 'Game cannot end while bets are active.', 'error') return end
    destroyGame(gameId, true)
    notify(src, 'Dice game ended.', 'primary')
end

-- ============================================================
--  Network events (called from client)
-- ============================================================
RegisterNetEvent('rs-streetdice:server:startGame', function()
    local src = source
    local coords = getSrcCoords(src)
    if not coords then return end
    createGame(src, coords)
end)

RegisterNetEvent('rs-streetdice:server:joinNearest', function() joinNearest(source) end)
RegisterNetEvent('rs-streetdice:server:placeBet', function(amount, side) placeBet(source, amount, side) end)
RegisterNetEvent('rs-streetdice:server:roll', function() rollDice(source) end)
RegisterNetEvent('rs-streetdice:server:endGame', function() tryEndGame(source) end)

RegisterNetEvent('rs-streetdice:server:leaveGame', function()
    local src = source
    local gameId = PlayerGame[src]
    local game = gameId and Games[gameId]
    if not game then return end
    if game.bets[src] then notify(src, 'You cannot leave until your bet is paid out.', 'error') return end
    game.players[src] = nil
    PlayerGame[src] = nil
    removeFromPlayerOrder(game, src)
    syncGame(game)
    notify(src, 'You left the dice circle.', 'primary')
end)

-- ============================================================
--  Commands / usable item
--  Internal framework bridge: no hard qb-core dependency. Framework command/item
--  registration is used when available; native commands are always available.
--  In the Cfx Grant build this file is protected; configure framework/money in config.lua.
-- ============================================================
RegisterCommand('streetdice', function(source)
    if source == 0 then return end
    local coords = getSrcCoords(source)
    if coords then createGame(source, coords) end
end, false)

RegisterCommand('sdjoin', function(source)
    if source == 0 then return end
    joinNearest(source)
end, false)

RegisterCommand('sdbet', function(source, args)
    if source == 0 then return end
    placeBet(source, args[1], args[2])
end, false)

RegisterCommand('sdroll', function(source)
    if source == 0 then return end
    rollDice(source)
end, false)

RegisterCommand('sdend', function(source)
    if source == 0 then return end
    tryEndGame(source)
end, false)

if Bridge.name == 'qbcore' and Bridge.core and Config.Bridge and Config.Bridge.useFrameworkItem and Config.Item.enabled then
    Bridge.core.Functions.CreateUseableItem(Config.Item.name, function(source)
        local coords = getSrcCoords(source)
        if coords then createGame(source, coords) end
    end)
elseif Bridge.name == 'qbox' and Config.Bridge and Config.Bridge.useFrameworkItem and Config.Item.enabled then
    -- qbx_inventory item use is commonly configured from the item export/inventory side.
    -- The /streetdice command remains available as a no-dependency fallback.
elseif Bridge.name == 'esx' and Bridge.core and Config.Bridge and Config.Bridge.useFrameworkItem and Config.Item.enabled then
    Bridge.core.RegisterUsableItem(Config.Item.name, function(source)
        local coords = getSrcCoords(source)
        if coords then createGame(source, coords) end
    end)
end

-- ============================================================
--  playerDropped
-- ============================================================
AddEventHandler('playerDropped', function()
    local src = source
    local gameId = PlayerGame[src]
    local game = gameId and Games[gameId]
    if not game then return end
    game.players[src] = nil
    PlayerGame[src] = nil
    removeFromPlayerOrder(game, src)

    if game.host == src then
        local newHost = next(game.players)
        if newHost then
            game.host = newHost
        else
            refundAllBets(game, 'host disconnect')
            destroyGame(game.id, true)
            return
        end
    end
    if game.shooter == src then
        game.shooter = passDiceTo(game, src)
    end
    syncGame(game)
end)

-- ============================================================
--  Background threads
-- ============================================================

-- Idle cleanup
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for gameId, game in pairs(Games) do
            local idleFor = now - (game.lastActivity or game.createdAt or now)
            if idleFor >= (Config.Game.idleCleanupSeconds or 120) then
                refundAllBets(game, 'idle')
                destroyGame(gameId, true)
            end
        end
    end
end)

-- Betting expiry warning + auto-cancel if shooter ghosts
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for _, game in pairs(Games) do
            if game.state == 'betting' and game.bettingEndsAt then
                local remaining = game.bettingEndsAt - now
                if not game.bettingWarned and remaining > 0 and remaining <= (Config.Game.bettingWarningSeconds or 5) then
                    game.bettingWarned = true
                    fireHype(game, 'warning', 'Bets closing soon')
                end
                local idleAfterDeadline = now - (game.lastActivity or now)
                if remaining <= -(Config.Game.autoCancelIfNoRollSeconds or 60)
                   and idleAfterDeadline >= (Config.Game.autoCancelIfNoRollSeconds or 60) then
                    refundAllBets(game, 'shooter timeout')
                    destroyGame(game.id, true)
                end
            end
        end
    end
end)

-- Ambient bank hype while on scene during action states
CreateThread(function()
    while true do
        Wait(1500)
        if Config.Hype.ambient and Config.Hype.ambient.enabled then
            local nowMs = GetGameTimer()
            for _, game in pairs(Games) do
                if (game.state == 'betting' or game.state == 'point') and game.bankArrived then
                    local minI = Config.Hype.ambient.minIntervalMs or 8000
                    local maxI = Config.Hype.ambient.maxIntervalMs or 14000
                    if not game.nextAmbientMs then
                        game.nextAmbientMs = nowMs + math.random(minI, maxI)
                    end
                    if nowMs >= game.nextAmbientMs then
                        fireHype(game, 'ambient', '')
                        game.nextAmbientMs = nowMs + math.random(minI, maxI)
                    end
                end
            end
        end
    end
end)

-- v0.3.14: scene presence heartbeat.
-- Late arrivals who were not within render range at creation never received the
-- one-shot createScene, so without this they would see nothing until they blindly
-- /sdjoin. Re-broadcasting the scene to nearby players keeps the circle, the Bank,
-- and the live state rendered for anyone who walks up, and stops feeding spectators
-- who leave (so the client pruner can expire their copy).
CreateThread(function()
    while true do
        Wait(Config.Game.scenePresenceMs or 3000)
        for _, game in pairs(Games) do
            broadcastSceneNearby(game, 'rs-streetdice:client:syncGame', publicGame(game))
        end
    end
end)

debugPrint('rs-streetdice v0.3.19-test server initialized')
