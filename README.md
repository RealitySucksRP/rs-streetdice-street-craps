# RS StreetDice — Street Craps RP

![RS StreetDice scene](artwork/rs-streetdice-scene.png)

<p align="center">
  <a href="https://reality-sucks-rp-webstore.tebex.io/category/free-scripts"><img src="https://img.shields.io/badge/BROWSE-FREE%20SCRIPTS-ff6a00?style=for-the-badge" alt="Browse RealitySucksRP free scripts on Tebex"></a>
  <a href="https://reality-sucks-rp-webstore.tebex.io/"><img src="https://img.shields.io/badge/SHOP-FULL%20TEBEX%20STORE-111111?style=for-the-badge" alt="Browse RealitySucksRP Tebex Store"></a>
  <a href="https://discord.gg/e9V3rPHySx"><img src="https://img.shields.io/badge/JOIN-DISCORD-5865F2?style=for-the-badge" alt="Join RealitySucksRP Discord"></a>
</p>

> I build my own FiveM gameplay systems and complete server setups including shops, weapons, phones, racing, customs, garages, zombie apocalypse systems, warfare, Phantom encounters and UI.

RS StreetDice is a mobile street-craps roleplay resource for FiveM. Players can start a dice circle almost anywhere, wait for The Bank to walk in, place RIDE or FADE action, and shoot server-authoritative dice with visible animations, crowd reactions and clear UI guidance.

**This resource is for fictional roleplay using in-game currency only. It is not intended for real-life gambling, real-money betting, cryptocurrency wagering, cash-out systems or illegal gambling activity.**

## Gameplay

1. A player uses `/streetdice` or the `streetdice` item to start a circle.
2. The Bank NPC walks to the scene and acts as the round pot holder.
3. Players join through the Bank prompt or `/sdjoin`.
4. The shooter must RIDE with their own roll.
5. Other players can FADE against the shooter.
6. When action is covered, the shooter presses ROLL.
7. The shooter throws, UI dice tumble and physical dice props spawn when available.
8. The Bank calls the result, pays winners and the UI explains the outcome.

## Dice Rules

- Come-out roll 7 or 11: RIDE wins.
- Come-out roll 2, 3 or 12: FADE wins.
- Any other come-out total becomes the point.
- In point phase, RIDE wants the shooter to hit the point again.
- In point phase, FADE wants a 7 before the point.
- Seven-out can pass dice to the next joined player when enabled.
- Come-out craps can also pass dice when enabled.

Street dice varies by community, so key behavior stays configurable.

## Features

- Server-side dice rolls
- RIDE / FADE gameplay model
- Bank NPC walk-in, hype, pot handling and payout
- Optional NPC Bank coverage for solo or small scenes
- Animated NUI dice
- Player throw animation tied to ROLL
- Physical dice props with pickup animation when supported
- NPC crowd reactions
- Configurable rules and money limits
- QBCore, Qbox, ESX and standalone test bridge support

## Install

1. Add the resource to your server resources folder.
2. Add this to `server.cfg`:

```cfg
ensure rs-streetdice
```

3. If using QBCore/Qbox inventory, add the item from `install/items.lua` to your item list.
4. Drop `install/streetdice.png` into your inventory image folder.
5. Optional: replace the placeholder `.ogg` files in `sounds/` with your own recordings before enabling sound.
6. Restart the server.

## Commands

```text
/streetdice              Start a dice circle
/sdjoin                  Join the nearest active circle
/sdbet [amt] [side]      Place an in-city RP bet
/sdroll                  Shooter rolls
/sdend                   Host ends the game after action is settled
/sdmenu                  Reopen the dice panel UI
```

## Framework Support

`Config.Framework = 'auto'` detects:

1. `qb-core`
2. `qbx_core`
3. `es_extended`
4. standalone fallback

Standalone mode is intended for testing. Live economy servers should use a supported framework.

## Open Source

This resource is open source. You are encouraged to study it, fork it, improve it and build new RP features on top of it.

If you use or expand it, please credit **Reality Sucks RP / William Brito** and link back to the original repository when possible.

## More From RealitySucksRP

**Tebex:** https://reality-sucks-rp-webstore.tebex.io/

**Website:** https://realitysucksrp.github.io/

**Discord:** https://discord.gg/e9V3rPHySx
