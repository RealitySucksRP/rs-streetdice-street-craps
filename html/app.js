(function () {
    'use strict';

    // ============================================================
    //  rs-streetdice  app.js  v0.2.0
    //  - 3D dice tumble that settles on the rolled face
    //  - Slam-in hype banner with retrigger
    //  - .ogg playback through hidden audio pool
    //  - Cash-stack pot visual
    //  - Screen shake on seven-out / craps
    // ============================================================

    var $ = function (id) { return document.getElementById(id); };

    var app          = $('app');
    var stateEl      = $('state');
    var pointEl      = $('point');
    var potEl        = $('pot');
    var withTotalEl  = $('withTotal');
    var againstEl    = $('againstTotal');
    var shooterNameEl = $('shooterName');
    var coverStatusEl = $('coverStatus');
    var flowHintEl = $('flowHint');
    var turnNoteEl   = $('turnNote');
    var ruleNoteEl   = $('ruleNote');
    var totalEl      = $('total');
    var hypeEl       = $('hype');
    var hypeTextEl   = $('hypeText');
    var resultEl     = $('result');
    var ledgerListEl = $('ledgerList');
    var cashStackEl  = $('cashStack');
    var amountInput  = $('amount');
    var die1         = $('die1');
    var die2         = $('die2');
    var bankAudio    = $('bankAudio');
    var audioPool    = bankAudio ? [bankAudio] : [];
    var maxAudioVoices = 4;
    var hideTimer = null;
    var uiConfig = { draggable: true };
    var dragState = null;
    var savedPosKey = 'rs-streetdice-ui-pos';
    var myServerId = null;                       // set from localized game state

    function openPanel() {
        if (hideTimer) {
            clearTimeout(hideTimer);
            hideTimer = null;
        }
        app.classList.remove('hidden', 'ui-closing');
        app.classList.remove('ui-open');
        void app.offsetWidth;
        app.classList.add('ui-open');
    }

    function closePanel() {
        app.classList.remove('ui-open');
        app.classList.add('ui-closing');
        if (hideTimer) clearTimeout(hideTimer);
        hideTimer = setTimeout(function () {
            app.classList.add('hidden');
            app.classList.remove('ui-closing');
            hideTimer = null;
        }, 210);
    }


    function clamp(n, min, max) {
        return Math.max(min, Math.min(max, n));
    }

    function applySavedPosition() {
        try {
            var raw = localStorage.getItem(savedPosKey);
            if (!raw) return;
            var pos = JSON.parse(raw);
            if (typeof pos.left !== 'number' || typeof pos.top !== 'number') return;
            var rect = app.getBoundingClientRect();
            var left = clamp(pos.left, 0, Math.max(0, window.innerWidth - rect.width));
            var top = clamp(pos.top, 0, Math.max(0, window.innerHeight - Math.min(rect.height, window.innerHeight)));
            app.style.left = left + 'px';
            app.style.top = top + 'px';
            app.style.right = 'auto';
        } catch (e) { /* ignore bad storage */ }
    }

    function savePosition() {
        try {
            var rect = app.getBoundingClientRect();
            localStorage.setItem(savedPosKey, JSON.stringify({ left: rect.left, top: rect.top }));
        } catch (e) { /* ignore */ }
    }

    function resetPosition() {
        try { localStorage.removeItem(savedPosKey); } catch (e) { /* ignore */ }
        app.style.left = '';
        app.style.top = '';
        app.style.right = '';
    }

    function setUiConfig(cfg) {
        uiConfig = cfg || uiConfig || {};
        if (uiConfig.defaultTop && !localStorage.getItem(savedPosKey)) app.style.top = uiConfig.defaultTop;
        if (uiConfig.defaultRight && !localStorage.getItem(savedPosKey)) app.style.right = uiConfig.defaultRight;
        applySavedPosition();
    }

    function initDrag() {
        var handle = document.querySelector('.header');
        if (!handle) return;
        handle.title = 'Drag to move menu. Double-click to reset position.';
        handle.addEventListener('mousedown', function (e) {
            if (e.button !== 0) return;
            if (e.target && (e.target.id === 'close' || e.target.closest('button'))) return;
            if (uiConfig && uiConfig.draggable === false) return;
            var rect = app.getBoundingClientRect();
            dragState = { x: e.clientX, y: e.clientY, left: rect.left, top: rect.top };
            app.classList.add('dragging');
            e.preventDefault();
        });
        handle.addEventListener('dblclick', function (e) {
            if (e.target && (e.target.id === 'close' || e.target.closest('button'))) return;
            resetPosition();
        });
        document.addEventListener('mousemove', function (e) {
            if (!dragState) return;
            var rect = app.getBoundingClientRect();
            var left = clamp(dragState.left + (e.clientX - dragState.x), 0, Math.max(0, window.innerWidth - rect.width));
            var top = clamp(dragState.top + (e.clientY - dragState.y), 0, Math.max(0, window.innerHeight - 80));
            app.style.left = left + 'px';
            app.style.top = top + 'px';
            app.style.right = 'auto';
        });
        document.addEventListener('mouseup', function () {
            if (!dragState) return;
            dragState = null;
            app.classList.remove('dragging');
            savePosition();
        });
        window.addEventListener('resize', applySavedPosition);
    }

    // Rotations needed to bring a given face to the front of the cube.
    // Faces are assembled in CSS as: 1=front, 2=back, 3=right, 4=left, 5=top, 6=bottom.
    // Extra full revolutions are added so it always feels like a real tumble before settling.
    var faceRotations = {
        1: 'rotateX(720deg) rotateY(720deg)',
        2: 'rotateX(720deg) rotateY(900deg)',
        3: 'rotateX(720deg) rotateY(630deg)',
        4: 'rotateX(720deg) rotateY(810deg)',
        5: 'rotateX(630deg) rotateY(720deg)',
        6: 'rotateX(810deg) rotateY(720deg)'
    };

    var lastPotMax = 1;

    function fmt(n) {
        n = Number(n) || 0;
        return '$' + n.toLocaleString('en-US');
    }

    function setDieFace(el, value) {
        if (!faceRotations[value]) value = 1;
        el.classList.remove('die-rolling');
        el.style.transform = faceRotations[value];
        el.setAttribute('data-face', String(value));
    }

    function spinDie(el) {
        // reset first, then add tumble class
        el.classList.remove('die-rolling');
        // force reflow so reapplying class restarts animation
        void el.offsetWidth;
        el.classList.add('die-rolling');
        el.style.transform = '';
    }

    function renderGame(g) {
        if (!g) return;

        if (g.localServerId !== undefined && g.localServerId !== null) myServerId = g.localServerId;

        stateEl.textContent  = labelState(g.state);
        pointEl.textContent  = g.point ? String(g.point) : '-';
        potEl.textContent = fmt(g.pot);
        withTotalEl.textContent    = fmt(g.totalWith);
        againstEl.textContent      = fmt(g.totalAgainst);
        shooterNameEl.textContent  = String(g.shooterName || 'Shooter').replace(/[<>&]/g, '');

        var withTotal = Number(g.totalWith) || 0;
        var fadeTotal = Number(g.totalAgainst) || 0;
        var unmatched = Math.abs(withTotal - fadeTotal);
        var bankCovers = !!g.npcBankCoverage;
        if (withTotal > 0 && fadeTotal > 0 && unmatched === 0) {
            coverStatusEl.textContent = 'covered';
            coverStatusEl.className = 'cover-status covered';
        } else if (bankCovers && (withTotal > 0 || fadeTotal > 0) && unmatched > 0) {
            coverStatusEl.textContent = bankCoverText(g, unmatched);
            coverStatusEl.className = 'cover-status bank';
        } else if (withTotal > 0 || fadeTotal > 0) {
            coverStatusEl.textContent = shortSideText(withTotal, fadeTotal, unmatched);
            coverStatusEl.className = 'cover-status short';
        } else {
            coverStatusEl.textContent = 'waiting on money';
            coverStatusEl.className = 'cover-status';
        }
        flowHintEl.textContent = nextActionText(g, withTotal, fadeTotal, unmatched, bankCovers);

        // cash stack visual: grows with pot up to a soft cap
        var pot = Number(g.pot) || 0;
        if (pot > lastPotMax) lastPotMax = pot;
        var stackHeight = 0;
        if (lastPotMax > 0) {
            stackHeight = Math.min(34, Math.round((pot / lastPotMax) * 34));
        }
        cashStackEl.style.height = (pot > 0 ? Math.max(6, stackHeight) : 0) + 'px';

        // bet ledger
        var bets = g.bets || {};
        var keys = Object.keys(bets);
        var rows = [];
        for (var i = 0; i < keys.length; i++) {
            var b = bets[keys[i]];
            var sideClass = b.side === 'with' ? 'ledger-side-with' : 'ledger-side-against';
            var sideTag   = b.side === 'with' ? 'RIDE' : 'FADE';
            var safeName  = String(b.name || 'unknown').replace(/[<>&]/g, '');
            rows.push(
                '<div class="ledger-row">' +
                    '<span class="ledger-name">' + safeName + '</span>' +
                    '<span class="ledger-amt ' + sideClass + '">' + fmt(b.amount) + ' ' + sideTag + '</span>' +
                '</div>'
            );
        }
        if (bankCovers && Number(g.npcCoverAmount || 0) > 0) {
            var bankSide = g.npcCoverSide === 'against' ? 'FADE' : 'RIDE';
            var bankClass = g.npcCoverSide === 'against' ? 'ledger-side-against' : 'ledger-side-with';
            rows.push(
                '<div class="ledger-row ledger-bank-row">' +
                    '<span class="ledger-name">THE BANK</span>' +
                    '<span class="ledger-amt ' + bankClass + '">' + fmt(g.npcCoverAmount) + ' ' + bankSide + '</span>' +
                '</div>'
            );
        }
        ledgerListEl.innerHTML = rows.length > 0 ? rows.join('') : '<div class="ledger-empty">no bets yet</div>';

        var notes = buildNotes(g, withTotal, fadeTotal, unmatched, bankCovers);
        turnNoteEl.textContent = notes.turn;
        ruleNoteEl.textContent = notes.rule;
    }


    function buildNotes(g, withTotal, fadeTotal, unmatched, bankCovers) {
        var state = g.state || '';
        var point = g.point || '-';
        var shooter = String(g.shooterName || 'the shooter').replace(/[<>&]/g, '');
        var imShooter = !!g.isMeShooter;
        var inGame = !!g.isInGame;

        if (state === 'waiting_for_bank') {
            return {
                turn: 'WAIT: THE BANK IS WALKING OVER',
                rule: 'Stay near the circle. When The Bank arrives, press E to talk and place money.'
            };
        }
        if (!inGame) {
            return {
                turn: 'WATCHING: PRESS JOIN TO GET IN',
                rule: 'Join the circle, then RIDE with the shooter or FADE against the shooter.'
            };
        }
        if (state === 'rolling') {
            return {
                turn: 'DICE OUT: BETS ARE LOCKED',
                rule: 'Nobody can change money now. Watch the dice and wait for The Bank to call it.'
            };
        }
        if (state === 'payout') {
            return {
                turn: 'PAYDAY: THE BANK IS SETTLING UP',
                rule: 'Do not end the game. The Bank must finish every payout first.'
            };
        }
        if (state === 'point') {
            if (imShooter) {
                return {
                    turn: 'YOUR TURN: POINT IS ' + point + ' - PRESS ROLL',
                    rule: 'Hit ' + point + ' again before you roll a 7. Hit the point and RIDE wins. Roll a 7 first and FADE wins, then the dice pass.'
                };
            }
            return {
                turn: 'SHOOTER: ' + shooter + ' IS TRYING TO HIT POINT ' + point,
                rule: 'RIDE wants the point. FADE wants a 7 before the point.'
            };
        }
        if (state === 'round_over') {
            if (imShooter) {
                return {
                    turn: 'ROUND OVER: YOU ARE STILL SHOOTER',
                    rule: 'Put money on RIDE for the next come-out roll, then roll when action is covered.'
                };
            }
            return {
                turn: 'ROUND OVER: WAITING ON NEXT MONEY',
                rule: 'Next round starts when the shooter puts money down and the action is covered.'
            };
        }

        // betting / comeout setup
        if (imShooter) {
            if (withTotal <= 0) {
                return {
                    turn: 'YOUR TURN: PUT MONEY ON RIDE',
                    rule: 'Shooter must ride with their own roll. Enter an amount and press RIDE.'
                };
            }
            if (bankCovers && unmatched > 0) {
                return {
                    turn: 'YOUR TURN: THE BANK COVERS THE FADE - PRESS ROLL',
                    rule: 'The Bank fades the uncovered side for you, so the action is matched. Press ROLL to throw the dice.'
                };
            }
            if (fadeTotal <= 0) {
                return {
                    turn: 'WAIT: SOMEBODY NEEDS TO FADE YOU',
                    rule: 'Another player has to bet FADE, or enable Bank coverage in config.lua.'
                };
            }
            if (unmatched > 0) {
                return {
                    turn: 'WAIT: ACTION IS NOT EVEN YET',
                    rule: shortSideText(withTotal, fadeTotal, unmatched) + '. The shooter can roll when both sides are covered.'
                };
            }
            return {
                turn: 'YOUR TURN: ACTION IS COVERED - PRESS ROLL',
                rule: 'This is the come-out roll. 7 or 11 wins for RIDE. 2, 3 or 12 wins for FADE. Any other number becomes your point.'
            };
        }

        return {
            turn: 'SHOOTER: ' + shooter,
            rule: 'Bet RIDE if you are with the shooter. Bet FADE if you are against the shooter.'
        };
    }

    function labelState(state) {
        switch (state) {
            case 'waiting_for_bank': return 'BANK WALKING';
            case 'betting': return 'GET COVER';
            case 'comeout': return 'COME OUT';
            case 'point': return 'POINT';
            case 'rolling': return 'DICE OUT';
            case 'payout': return 'PAYING';
            case 'round_over': return 'RUN IT BACK';
            default: return String(state || '-').replace(/_/g, ' ').toUpperCase();
        }
    }

    function nextActionText(g, withTotal, fadeTotal, unmatched, bankCovers) {
        var state = g.state || '';
        if (state === 'waiting_for_bank') return 'wait for the bank to step in';
        if (state === 'rolling') return 'dice are out, bets locked';
        if (state === 'payout') return 'bank is settling the money';
        if (state === 'round_over') return 'new round: shooter rides first, players fade';
        if (state === 'point') {
            if (unmatched === 0 && withTotal > 0 && fadeTotal > 0) return 'point is on, shooter can roll';
            if (bankCovers && (withTotal > 0 || fadeTotal > 0)) return 'point is on, The Bank covers the short side';
            return 'point is on, ' + shortSideText(withTotal, fadeTotal, unmatched).toLowerCase();
        }
        if (withTotal <= 0) return 'shooter needs to put money on RIDE';
        if (bankCovers && unmatched > 0 && (withTotal > 0 || fadeTotal > 0)) return 'The Bank covers the short side - shooter can roll';
        if (fadeTotal <= 0) return 'someone needs to FADE the shooter';
        if (unmatched > 0) return shortSideText(withTotal, fadeTotal, unmatched);
        return 'covered: shooter can roll';
    }

    function bankCoverText(g, unmatched) {
        var side = g.npcCoverSide === 'against' ? 'FADES' : 'RIDES';
        return 'BANK ' + side + ' ' + fmt(g.npcCoverAmount || unmatched);
    }

    function shortSideText(withTotal, fadeTotal, unmatched) {
        if (withTotal < fadeTotal) return 'RIDE needs ' + fmt(unmatched);
        if (fadeTotal < withTotal) return 'FADE needs ' + fmt(unmatched);
        return 'needs cover';
    }

    function showHype(text, bucket) {
        hypeTextEl.textContent = text || '';
        hypeEl.classList.remove('slam');
        void hypeEl.offsetWidth;
        hypeEl.classList.add('slam');

        // bucket-driven accent color shift on hype banner border
        if (bucket === 'sevenout' || bucket === 'craps' || bucket === 'warning') {
            hypeEl.style.boxShadow = '3px 3px 0 rgba(200,52,28,0.55)';
        } else if (bucket === 'natural' || bucket === 'hitpoint' || bucket === 'payout') {
            hypeEl.style.boxShadow = '3px 3px 0 rgba(45,106,58,0.55)';
        } else {
            hypeEl.style.boxShadow = '3px 3px 0 rgba(0,0,0,0.3)';
        }
    }

    function playSound(file, volume) {
        if (!file) return;
        try {
            var audio = null;
            for (var i = 0; i < audioPool.length; i++) {
                if (audioPool[i].paused || audioPool[i].ended) {
                    audio = audioPool[i];
                    break;
                }
            }
            if (!audio) {
                if (audioPool.length < maxAudioVoices) {
                    audio = new Audio();
                    audioPool.push(audio);
                } else {
                    audio = audioPool.shift();
                    audio.pause();
                    audioPool.push(audio);
                }
            }

            // reset src each time so the same file can replay
            audio.pause();
            audio.currentTime = 0;
            audio.src = '../sounds/' + file;
            audio.volume = Math.max(0, Math.min(1, Number(volume) || 0.7));
            var p = audio.play();
            if (p && p.catch) p.catch(function () { /* autoplay blocked or file missing; ignore */ });
        } catch (e) { /* ignore */ }
    }

    function playRoll(d1, d2) {
        spinDie(die1);
        spinDie(die2);
        totalEl.textContent = 'ROLLING...';
        app.classList.remove('dice-pop');
        void app.offsetWidth;
        app.classList.add('dice-pop');
        // settle dice after the same visual window the server uses (rollVisualMs)
        setTimeout(function () {
            setDieFace(die1, d1);
            setDieFace(die2, d2);
            totalEl.textContent = 'TOTAL: ' + (Number(d1) + Number(d2));
            setTimeout(function () { app.classList.remove('dice-pop'); }, 350);
        }, 2400);
    }

    // Find this player's line in the payout list so we can tell them, plainly,
    // whether THEY won or lost on this roll - not just which side won.
    function myPayout(paid) {
        if (!paid || !paid.length || myServerId === null) return null;
        for (var i = 0; i < paid.length; i++) {
            if (Number(paid[i].src) === Number(myServerId)) return paid[i];
        }
        return null;
    }

    function showResult(payload) {
        var reason = (payload && payload.reason) || '';
        var winnerSide = payload && payload.winnerSide;

        var mine = myPayout(payload && payload.paid);
        var headline, cls;
        if (mine) {
            if (mine.result === 'win') {
                headline = 'YOU WON ' + fmt(mine.amount);
                cls = 'win';
            } else if (mine.result === 'push') {
                headline = 'PUSH - BET REFUNDED';
                cls = '';
            } else if (mine.result === 'bank_win') {
                headline = 'THE BANK TOOK IT - YOU LOST ' + fmt(mine.amount);
                cls = 'lose';
            } else {
                headline = 'YOU LOST ' + fmt(mine.amount);
                cls = 'lose';
            }
        } else {
            // spectator, or no bet this round: show which side hit
            headline = (winnerSide === 'with') ? 'RIDE WINS' : 'FADE WINS';
            cls = (winnerSide === 'with') ? 'win' : 'lose';
        }

        // Keep the outcome self-contained in the result strip (it persists ~8s) so it
        // is not clobbered when the on-screen dice settle a moment later. The reason
        // string already carries the number for most outcomes ("Natural 7", "Seven out").
        var sub = String(reason || '').toUpperCase();
        resultEl.classList.remove('win', 'lose');
        resultEl.textContent = headline + (sub ? ' - ' + sub : '');
        if (cls) resultEl.classList.add(cls);

        // shake on dramatic losing rolls
        if (/seven out|craps/i.test(reason)) {
            app.classList.remove('shake');
            void app.offsetWidth;
            app.classList.add('shake');
            setTimeout(function () { app.classList.remove('shake'); }, 500);
        }

        // clear result strip after a beat
        setTimeout(function () {
            resultEl.classList.remove('win', 'lose');
            resultEl.textContent = '';
        }, 8000);
    }

    // ============================================================
    //  NUI message router
    // ============================================================
    window.addEventListener('message', function (ev) {
        var msg = ev.data || {};
        switch (msg.action) {
            case 'uiConfig':
                setUiConfig(msg.data || {});
                break;
            case 'show':
                openPanel();
                if (msg.data) renderGame(msg.data);
                break;
            case 'update':
                // v0.2.3: data-only update. Refreshes state cards / ledger / dice etc
                // but does NOT change panel visibility. Used so the panel stays hidden
                // until the player explicitly opens it by pressing E at the Bank.
                if (msg.data) renderGame(msg.data);
                break;
            case 'hide':
                closePanel();
                break;
            case 'hype':
                showHype(msg.data && msg.data.text, msg.data && msg.data.bucket);
                break;
            case 'sound':
                playSound(msg.data && msg.data.file, msg.data && msg.data.volume);
                break;
            case 'roll':
                playRoll(msg.data && msg.data.d1, msg.data && msg.data.d2);
                break;
            case 'result':
                showResult(msg.data);
                break;
            default:
                if (msg && msg.id !== undefined) renderGame(msg);
        }
    });

    // ============================================================
    //  Button bindings
    // ============================================================
    function post(endpoint, body) {
        return fetch('https://' + (window.GetParentResourceName ? GetParentResourceName() : 'rs-streetdice') + '/' + endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {})
        }).catch(function () { /* ignore fetch errors so UI never breaks */ });
    }

    $('close').addEventListener('click', function () {
        closePanel();
        post('close', {});
    });

    $('join').addEventListener('click', function () { post('join', {}); });
    $('roll').addEventListener('click', function () { post('roll', {}); });
    $('end').addEventListener('click',  function () { post('endGame', {}); });

    var betBtns = document.querySelectorAll('.bet-btn');
    for (var i = 0; i < betBtns.length; i++) {
        betBtns[i].addEventListener('click', function (e) {
            var side = e.currentTarget.getAttribute('data-side');
            var amount = parseInt(amountInput.value, 10);
            if (!amount || amount <= 0) {
                amountInput.focus();
                return;
            }
            post('bet', { amount: amount, side: side });
            amountInput.value = '';
        });
    }

    document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') {
            closePanel();
            post('close', {});
        }
    });

    initDrag();
    applySavedPosition();

    // initialize dice to face 1 cleanly
    setDieFace(die1, 1);
    setDieFace(die2, 1);
})();
