# Naval IO (Godot 4.x, Compatibility renderer)

Open `project.godot` in Godot 4 and press F5.

**Requires Godot 4.3+ (tested with 4.4).**

## Files
| file | purpose |
|---|---|
| `data.gd` | **All content**: 10 tiers, 47 ships (carriers, 5 submarines, super-battleships), 20 weapons, aircraft, abilities, XP levels and competitive ranks. Add ships/weapons here. |
| `main.gd` | World, warzone border, ramming, ship renderer, weapon mounts, squadrons, projectiles, fire/flood, detection, AI, effects |
| `ui.gd` | Multi-page main menu (PORT / PROFILE / FLEET / BATTLE PASS / SETTINGS), password login screen, rank badges, logo, fleet browser with full ship profiles, battle-pass page, battle report screen with animated rank math, HUD, promotion / respawn pop-ups |
| `audio.gd` | Procedural layered sound synthesis (no audio files needed) |
| `settings.gd` | All options + key bindings + meta progression + password accounts (20-day seasons), saved to `user://naval_io_settings.cfg` and `user://naval_io_accounts.cfg` |
| `water.gdshader` | Ocean shader (3 quality levels) |

## What's new in this version
* **10 tiers, 47 ships** with steep stat spreads: a Tier I PT boat has 110 HP, Super Yamato (A-150) 18,000.
  A small ship has no realistic chance against a max-tier battleship.
* **Every carrier is unique** (Casablanca, Independence, Essex, Shinano battle-carrier, CVN-10 supercarrier...)
  and Yamato-class ships are far larger than everything else.
* **Aircraft squadrons**: carriers launch a 3-plane squadron that moves and shoots as one when you fly it,
  plus a second AI-controlled squadron. Idle aircraft patrol near your ship, pick the nearest enemy they can
  spot inside their leash and go on attack runs on their own (bombs, torpedoes, rockets, missiles) - they
  always come back to refit when their weapons are empty.
* **Auto secondaries**: big ships fire their medium/small secondary guns at close enemies automatically.
* **Ramming**: ships collide and grind each other; damage scales with relative speed and the other
  ship's size, so a heavy battleship crushes a patrol boat.
* **Warzone border**: an irregular polygon, not a square. You can sail out but take escalating
  damage that kills in roughly 10 seconds at the edge and gets worse the longer you stay.
* **Submarines** (Type VII, Kilo, Foxtrot with cruise missiles, Oscar II, Seawolf) with an
  Emergency Dive ability that breaks missile locks and hides you.
* **Progression**: account XP levels (1-30), competitive ranks (Rookie, Bronze, Silver, Gold, Platinum,
  Diamond, Master, Elite, Legend, PLUTONIUM), ranked mode toggle in the menu, and stronger ships
  locked behind account levels. Earn XP/RP by sinking ships.
* **Full-screen main menu** with a profile card (nick, level, XP bar, rank), ranked toggle, FLEET browser page (all 47 ships across tiers I-X with level locks), CONTROLS page and settings; every battle starts at Tier I and you promote in-battle by earning score.
* **More realistic sound**: guns and explosions are layered (crack + boom + rumble + echoes), sinking
  ships gurgle and groan.

## What's new in the feature-storm update
* **Passenger login**: on first launch you pick a password - any password becomes its own account
  (ships you've flown, XP, level, rank, battle pass). Same password on any download of the game on
  that PC = same account. Guest mode works too but progress stays on the machine.
* **Multi-page menu**: PORT (play + logo), PROFILE (rank badge, stats, hull paints, logout),
  FLEET (browser with played/locked states and a full profile panel for every one of the 47 ships),
  BATTLE PASS (20 tiers + daily missions + rank ladder), SETTINGS.
* **Ranks have drawn badges** - circles for Rookie, shields for Bronze/Silver/Gold, hexes for
  Platinum/Diamond, stars for Master/Elite, a crown for Legend and a radiation trefoil for PLUTONIUM.
* **Battle pass**: earn BP points from XP and daily missions (3 a day, chosen by date, easy/normal/hard
  targets). Spend points on 20 reward tiers: XP, ranked rating and 6 unlockable hull paints you can
  select from the Profile page. Season (rank + pass + missions) resets every 20 days.
* **Exit battle with a battle report**: Esc -> Exit Battle creates a report with animated progress
  bars for XP and rank rating, level-up and RANK-UP flares with the badge popping in.
* **Sinking theater**: capital ships (90m+) now sink for 9-16 seconds, listing to one side,
  burning and smoking, with bubbles and a final water column instead of a 2-second fade.
* **Salvo drama**: heavy gun salvos (bore 200mm+) from ANY ship near the camera shake the screen,
  with big muzzle flash, shockwave ring and smoke. Shells that miss spawn towering near-miss
  water columns.
* **Carrier aircraft buffed**: every aircraft got 40-55% more HP, air weapons hit harder across
  the board so carriers actually project power.
* **Submarines buffed**: +30% HP, +8% speed, dive has NO cooldown (dive as often as you need,
  16 s underwater per use), dived subs move 25% faster and can throttle deeper.
* **Nickname filter**: rude/18+ nicknames (including l33t-speak work-arounds) are blocked and
  renamed.
* **New logo**: drawn in-code - gold-ringed anchor emblem with the NAVAL.IO wordmark.

## Controls (rebindable in Settings -> Controls)
* W/S throttle, A/D steer, mouse aims
* LMB / RMB / Space fire the **selected** weapon; click the weapon bar or press 1-9 to select
* Q / E / R abilities, V aircraft (your ship then sails on AUTOPILOT), U promotion window
* Wheel zoom, Esc settings, F2 graphics quality, F3 FPS

## Weapons by tier
* Tier I-II: guns, torpedoes and mines only - no missiles or rockets.
* Tier III: unguided rockets / unguided missile salvos.
* Tier IV+: guided missiles in four families - light, sea-skimmer, heavy supersonic and long-range
  cruise - each with its own silhouette and colours.

## Performance design (weak GPUs such as Intel HD 4000)
* **Baking**: every ship hull, gun turret, island, reef and wreck is rendered ONCE into a texture at start-up
  (4x MSAA + mipmaps) and shown as a sprite. Same picture, but a handful of draw calls instead of hundreds.
  Start-up shows "Preparing the world..." for a few seconds while this happens.
* **Water shader** reads a pre-computed wave texture instead of evaluating ~25 trig functions per pixel.
* **CPU**: spatial grids for islands, reefs, crates and ship-vs-shot checks; AI ships only rotate the turrets of
  the weapon they use; distant idle ships are simulated every 4th frame; empty effect layers are not redrawn.
* Ships are hidden with `modulate`, never `visible` (toggling visibility forces Godot to redraw all children).
* Auto quality removes MSAA first, then lowers detail, only when FPS stays below 36.
* Auto graphics only acts while you are playing, tries one step at a time (anti-aliasing, then fast water, then
  detail) and automatically undoes any step that does not give at least 12% more FPS.

## Tactical rules
* **Fog of war**: you only see ships inside your detection range (x their stealth; small ships and
  diving submarines are harder to spot). Firing reveals you, smoke hides you, radar / aircraft /
  marking extend vision.
* **Firing**: a weapon fires from the mount CLOSEST to your cursor; barrels in that turret fire in order.
* **Secondary guns** (tagged on big ships) track the closest enemy ship on their own and fire
  automatically when it is near.
* **Missiles and homing torpedoes** lock the visible enemy closest to the direction you aimed in when
  they launch (they do not follow the cursor).
* **Anti-aircraft**: AA weapons shoot aircraft and incoming missiles on their own; you can also
  select an AA weapon to aim it manually at aircraft.
* **Fire (5% per heavy hit) and flooding (2%)**: burn / flood damage over time; flooding slows the ship.
  Damage Control puts both out.
* **Enemy aircraft**: carriers send dive bombers, torpedo bombers and jets in full squadrons,
  helicopters attack, scouts mark you for focus fire.
* AI ships pick fights near their own tier, keep their range, retreat when out-tiered and dive
  (submarines) or hide (smoke) when badly hurt.

## Multiplayer status (honest note)
An "add servers so two people on the internet can match" request is **not implemented**: this
project ships no game server, and a Godot .io clone on the public internet needs hosted servers
(a relay/dedicated server running somewhere). The account system (password login) is the
groundwork for that - but real online matchmaking needs someone to host a server, which is
outside what this repo can do today.
