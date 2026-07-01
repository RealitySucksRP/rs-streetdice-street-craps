# rs-streetdice v0.3.19-test Standard Build

Mobile street craps for FiveM with editable buyer customization files.
Any player can drop a dice circle almost anywhere on the map. The Bank NPC walks in, takes locked pot bets,
the shooter rolls server-authoritative dice, and the Bank pays out through the internal framework bridge.

This build keeps the important server-owner files editable:

- `config.lua`
- `html/index.html`
- `html/style.css`
- `html/app.js`
- `sounds/*.ogg`
- `install/items.lua`
- `install/streetdice.png`
- `README.md`


--------------------------------------------------------------

## v0.3.19-test notes

This build keeps solo/small-game Bank coverage on by default:

```lua
Config.Money.allowNpcBankCoverage = true
```

When only one player bets RIDE/WITH, The Bank can cover the FADE/AGAINST side from its configured bankroll so the shooter can roll during testing or small scenes. Server owners who want strict player-vs-player street dice can set it to `false`.

The Bank spawn path was also tightened so he should spawn on ground and walk in naturally instead of starting under the map. The UI ledger shows a visible `THE BANK` row when The Bank is covering the short side.

The roll path is now animation-first. Pressing ROLL triggers the shooter turn/throw animation and the on-screen dice tumble even if a world dice prop model cannot load on that FiveM build. Physical dice props still spawn when a configured dice model is available.

--------------------------------------------------------------

## Install

1. Add the resource to your server resources folder.
2. Add this to `server.cfg`:

```cfg
ensure rs-streetdice
```

3. If using QBCore/Qbox inventory, add the item from `install/items.lua` to your item list.
   For QBCore, paste only the item entry into `qb-core/shared/items.lua`.

```lua
streetdice = {
    name = 'streetdice',
    label = 'Street Dice',
    weight = 100,
    type = 'item',
    image = 'streetdice.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'A pair of dice used to start a street dice game.'
},
```

4. Drop `install/streetdice.png` into your inventory image folder
   (`qb-inventory/html/images/` or wherever your inventory pulls item icons from).
5. Optional: replace the empty placeholder `.ogg` files in `sounds/` with real recordings,
   then set `Config.Sounds.enabled = true`.
6. Restart the server. Use the item, or `/streetdice`, anywhere in the world to start a game.

--------------------------------------------------------------

## Editable Files

Common customization files:

- `config.lua`
- `html/`
- `sounds/*.ogg`
- `install/`
- `README.md`

The manifest intentionally does **not** hard-depend on `qb-core` because the internal bridge can detect QBCore, Qbox, ESX, or standalone test mode.

--------------------------------------------------------------

## Paid license / terms

This resource is a paid Reality Sucks RP / William Brito product.
Purchase grants the buyer permission to use the resource on their own FiveM server(s) according to the product terms on the purchase page.
Redistribution, resale, leaking, reuploading, sharing paid files, or claiming this work as your own is not allowed.
Editable files are provided only for server configuration, UI customization, item setup, and sound replacement.

This resource is designed only for fictional roleplay gameplay using in-game currency.
It is not intended for real-life gambling, real-money betting, cryptocurrency wagering, or illegal gambling activity.
Server owners are responsible for following FiveM, Cfx.re, local law, and community rules.

--------------------------------------------------------------

## Bridge / money flow

`Config.Framework = 'auto'` detects frameworks in this order:

1. `qb-core`
2. `qbx_core`
3. `es_extended`
4. standalone fallback

The betting money flow is server-side only:

1. Player places a RIDE/WITH or FADE/AGAINST bet.
2. Server checks distance, game state, bet limits, and player money.
3. Server removes money immediately through the bridge.
4. Removed money is stored in the round pot.
5. Shooter rolls server-side dice.
6. Server pays winners/refunds pushes through the bridge.
7. Game cannot end while pot money, payout, or active bets are pending.

Standalone mode is included for testing only. Live economy servers should
use QBCore, Qbox, or ESX.

--------------------------------------------------------------

## Commands

```
/streetdice        Start a dice circle at your current position
/sdjoin            Join the nearest active circle (within joinRadius)
/sdbet [amt] [side] Place a bet. side = with or against
/sdroll            Shooter rolls
/sdend             Host ends the game (only after all bets settled)
/sdmenu            Reopen the dice panel UI
```

--------------------------------------------------------------

## How a round plays

1. Host runs `/streetdice` or uses the `streetdice` item.
2. Bank NPC spawns at `bankSpawnDistance` and walks in via
   navmesh. State = `waiting_for_bank`.
3. After `bankArriveDelaySeconds`, state flips to `betting`.
   Players in the circle place bets `with`/ride or `against`/fade the
   shooter. Bets are removed from cash on placement and held in the round pot.
4. Bank fires hype lines (and .ogg sounds if configured) on
   state changes, plus random ambient yelling during action.
5. Shooter must have money riding with their own roll. If
   `requireFadeToRoll` and `requireCoveredAction` are enabled, the
   ride/fade totals must be matched before dice can fly.
6. Shooter rolls. State -> `comeout` then either resolves
   immediately (natural / craps) or sets `point` and goes to
   the `point` phase. Additional side action can be placed during
   the point phase until the next roll. Subsequent rolls continue
   until the point is hit (with side wins) or seven-out (against
   side wins).
7. Dice stay with the shooter after wins and pass to the next joined
   player after seven-out or come-out craps when enabled.
8. After payout the round is over. Players can place new bets
   to start the next round, or the host can `/sdend`.

--------------------------------------------------------------

## Street Rules Modeled

Street craps varies block to block, so this resource models the common
player-vs-player version instead of casino table craps:

- The Bank is a money holder, not a casino house. By default NPC Bank
  coverage is off for authentic player-vs-player action.
- Shooter rides with their own roll. Other players fade the shooter.
- Come-out 7 or 11 wins for the shooter side. Come-out 2, 3, or 12
  craps out and the fade side wins.
- Any other come-out total becomes the point. The shooter keeps rolling
  until the point is made or seven-out/missout happens.
- Dice pass in joined-player order after seven-out. By default, dice
  also pass after a come-out craps loss.
- Ride/fade money must be covered before dice fly. Players can add to
  their same-side bet while betting is open, but cannot switch sides
  mid-round.

--------------------------------------------------------------

## v0.3.16 changelog

- Tightened the in-world dice pickup sequence so the shooter turns to
  the dice, plays `pickup_object` / `pickup_low`, attaches the dice to
  the hand during the pickup motion, then cleans them up after the
  animation finishes.
- Added `Config.Dice.pickupGrabDelayMs` for tuning when the ground dice
  are lifted into the hand during the pickup animation.
- Added optional physical dice SFX placeholders:
  `dice_throw.ogg`, `dice_land.ogg`, and `dice_pickup.ogg`.

## v0.3.15 changelog

- Rechecked street-craps rules/slang against external references.
- Set `Config.Money.allowNpcBankCoverage = false` by default so the
  release starts as player-vs-player street dice, not house-backed dice.
- Added `Config.Game.passDiceOnComeoutCraps = true`; when the shooter
  craps out on the come-out roll, dice pass to the next shooter.
- Left NPC Bank coverage available as an optional server setting for
  solo/small-group testing.

## v0.3.14 changelog

- Fixed scene sync for nearby non-member spectators.
- Late arrivals now receive scene heartbeat updates, so they can see the Bank, chalk circle, and E-to-join prompt without blind `/sdjoin`.
- Bank arrival, live state, hype, roll visuals, payout result, and cleanup now broadcast to nearby spectators as well as joined players.
- Added client-side spectator stale cleanup so Bank/crowd/marker entities do not leak when a spectator leaves render range.
- Added `Config.Game.sceneRenderDistance`, `scenePresenceMs`, and `sceneStaleMs`.

## v0.3.13 changelog

- Added optional NPC Bank coverage for solo/small-group testing.
- Added UI text for Bank coverage state.
- Added draggable NUI positioning with local saved position.
- Switched throw animation to `anim@mp_snowball` / `throw_snowball`.
- Disabled clipboard scenario by default to prevent dropped clipboard/notepad props.

## v0.3.9 changelog

- Restored buyer update flow.
- Kept the internal framework bridge; no hard `qb-core` dependency.
- Main gameplay brain remains protected while `config.lua`, UI, sounds, install files, and README are editable.
- README and license language updated for paid distribution.

## v0.3.6 changelog

- Fixed a betting-flow bug where an uncovered roll attempt could move
  the game from `betting` to `comeout` before rejecting the roll.
- Roll attempts now leave the game in its current betting state until
  all requirements pass.
- Cover hints now say whether RIDE or FADE needs more money.

## v0.3.5 changelog

- Improved betting flow so the opening timer no longer traps players
  in an uncovered, unrollable state by default.
- Added `Config.Game.enforceBettingDeadline`; leave false for street
  dice flow where coverage, not a hard timer, gates the roll.
- Added a panel action hint that tells players whether the shooter
  needs to ride, someone needs to fade, the short side needs cover, or
  the shooter can roll.
- Shooter timeout now respects recent betting activity instead of
  cancelling an actively covered circle.

## v0.3.4 changelog

- Prepared the package for paid release: debug defaults off, dev backup
  files removed, install folder cleaned, and commercial license terms
  added.
- Replaced bundled .ogg content with empty filename placeholders. Replace
  these files with real recordings before enabling sounds.
- `Config.Sounds.enabled` now defaults to false until real audio is added.

## v0.3.3 changelog

- Thrown dice no longer disappear at cleanup time. The shooter turns
  toward the dice and plays `pickup_object` / `pickup_low` before the
  props are removed.
- Added `Config.Dice.pickupAnimDict`, `pickupAnimName`, and
  `pickupAnimMs` for tuning the pickup.

## v0.3.2 changelog

- Shooter now visibly holds dice in their hand during the wind-up.
- Hand dice release into stronger tumbling ground dice when the roll
  starts, so nearby players can see the in-world roll animation.
- Added `Config.Dice.releaseDelayMs` to tune when hand dice become
  thrown dice.

## v0.3.1 changelog

- Street-action rules are stricter by default: no NPC bank coverage,
  shooter must bet with themselves, somebody must fade the shooter,
  and ride/fade totals must match before rolling.
- Dice pass around the joined player order on seven-out instead of
  picking a random next shooter.
- Betting stays open during the point phase between rolls, allowing
  the circle to add or cover action before the shooter throws again.
- Added configurable NPC crowd peds around the dice circle. They walk
  in, face the action, clap, cheer, film, and react to hype events.
- Strengthened the shooter animation timing and retriggered the NUI
  dice tumble/pulse every roll so the dice animation is visibly played.
- Preserved the UI animation fix from v0.3.1: the menu hides with
  opacity/visibility instead of `display: none`, so open/close and dice
  animations can retrigger.
- UI now labels street terms as RIDE and FADE, shows the active shooter,
  and displays whether the money is covered or short.

--------------------------------------------------------------

## v0.2.2 changelog

- Money correctness fix: when nobody bet the winning side (e.g. all
  players bet AGAINST the shooter and shooter rolled a natural 7),
  losing bets are now refunded as a push instead of being burned
  into the void.
- Result reason text now appends "push (no winners)" when this
  branch fires, so the UI result strip reflects what happened.
- Added sound-file wiring for `/sounds/`. Current release packages
  empty filename placeholders only; replace with real .ogg recordings
  and enable `Config.Sounds.enabled` when ready.

## v0.2.1 changelog

- Roll spam fix: `/sdroll` during the dice animation window is
  rejected with "Dice are already rolling." Previously the shooter
  could fire twice and resolve the same bets twice.
- Betting deadline is now hard. `placeBet` checks
  `os.time() > game.bettingEndsAt` and rejects past the deadline.
  Before, bets could slip through until the auto-cancel thread
  reaped the game.
- Joined players (not just the host) now get `MyGame` set on the
  client so `/sdmenu` reopens the panel for them.

## v0.2.0 changelog

Bug fixes from v0.1.0:
- `game.point` now clears in payout. Previously a leftover
  point could bleed into the next round.
- `math.randomseed` is called at boot so dice are not the same
  sequence after every restart.
- Bet amounts are floored, no more fractional-bet exploits in
  the proportional payout math.
- `Config.Game.idleCleanupSeconds` is now actually used: a
  background thread refunds bets and destroys games that go
  quiet.
- `Config.Hype.cooldownMs` is now actually used and enforced
  per-game on every hype broadcast.
- Server reads player coords from the engine instead of
  trusting client-supplied coordinates.
- `createScene` is broadcast only to nearby players (60m)
  instead of the whole server.
- Bank ped uses `TaskGoToCoordAnyMeans` with navmesh pathing
  and a `GetClosestVehicleNodeWithHeading` spawn fallback so
  he no longer walks through walls.
- Player money access switched to `Player.Functions.GetMoney`
  for compatibility with QBCore forks.

New gameplay options:
- `Config.Game.shooterMustBet` requires the shooter to have a
  bet on the table to roll.
- `Config.Game.passDiceOnSevenOut` rotates the dice to a random
  other player after a seven-out.
- `Config.Game.maxConcurrentGames` caps simultaneous circles
  on the server.
- `Config.Game.bettingWarningSeconds` triggers a "bets closing"
  hype before the betting window closes.
- `Config.Game.autoCancelIfNoRollSeconds` refunds and ends a
  game if the shooter never rolls after betting expires.

Bank voice + ambient hype:
- New `Config.Sounds` block. Drop .ogg files in `/sounds`,
  list them per bucket, set `enabled = true`. Random file is
  picked per hype event. Distance-gated playback with linear
  volume attenuation. Plays through NUI Audio so the panel
  doesn't need to be open.
- New `Config.Hype.ambient` block. Bank randomly yells lines
  from the `ambient` bucket every 8-14 seconds (configurable)
  while on scene during betting/point states.
- New `warning` and `ambient` hype line buckets in
  `Config.Hype.lines`.

UI rebuild:
- Full visual identity overhaul: aged cardboard panel with
  masking-tape corners, fiber texture, slight rotation for a
  handmade feel.
- Stencil "STREET DICE" header in spray-paint red, stamped
  "BANK" mark.
- Real 3D CSS dice that tumble and settle on the rolled face.
- Slam-in graffiti-tag hype banner with bucket-tinted glow.
- Cash-stack pot visual that grows as bets pile up.
- Bet ledger with handwritten name list.
- Screen shake on seven-out / craps results.
- Plain ASCII throughout - no em-dashes, no smart quotes.

--------------------------------------------------------------

## Config.Sounds quick reference

See `sounds/README.txt` for the full setup walkthrough.

```lua
Config.Sounds = {
    enabled = false,          -- replace placeholder files, then set true
    volume = 0.7,             -- 0.0 to 1.0 master
    audibleRadius = 25.0,     -- meters; outside this range, silent
    files = {
        bank_arriving = {},   -- arrays of .ogg filenames per bucket
        betting       = {},
        warning       = {},
        locked        = {},
        natural       = {},
        craps         = {},
        point         = {},
        sevenout      = {},
        hitpoint      = {},
        payout        = {},
        ambient       = {}
    },
    effects = {
        throw  = 'dice_throw.ogg',
        land   = 'dice_land.ogg',
        pickup = 'dice_pickup.ogg'
    }
}
```

--------------------------------------------------------------

## Files

```
rs-streetdice/
  fxmanifest.lua
  config.lua
  README.md
  client/main.lua
  server/main.lua
  html/
    index.html
    style.css
    app.js
  sounds/
    README.txt
  install/
    items.lua
```

--------------------------------------------------------------

Author: Reality Sucks RP / William Brito

License:
This resource is licensed for use by the purchasing server/community.
Redistribution, resale, reuploading, leaking, or repackaging for sale is
not permitted without written permission from the author.


## v0.3.19-test Release Notes
- Roll feedback is tied directly to the ROLL action: shooter turn/throw animation starts immediately, NUI dice always tumble, and physical dice props spawn when a configured dice model loads.
- Dice prop loading is cached off the roll path. If no world dice prop can load, the roll still shows animation, UI dice, and outcome text instead of feeling broken.
- Solo/small-game Bank coverage is enabled by default through `Config.Money.allowNpcBankCoverage = true`; set it to `false` for strict player-vs-player street dice.
- The ledger shows `THE BANK` when NPC coverage is filling the missing RIDE/FADE side.
- Shooter pickup uses `pickup_object` / `pickup_low` against the actual thrown dice props. The dice attach into the shooter hand during pickup and clean up after the animation.
- Optional physical dice SFX placeholders are included for throw, landing, and pickup. Hype voice buckets are still enough; these are extra polish.
- Nearby spectators receive scene updates and cleanup automatically. Joined players still receive updates even if they move outside scene render range.
