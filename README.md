# Ships of War (Godot 4.2)

A 2D top-down naval combat game built with Godot 4.2. No external assets required — every ship, cannonball, and explosion is drawn with engine primitives, and the ocean is a `gdshader`.

## How to run

1. Install [Godot 4.2](https://godotengine.org/download) (standard or .NET build, GL Compatibility renderer is used).
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** (Run Project).

## Controls

| Input | Action |
| --- | --- |
| `W` / `↑` | Sail forward |
| `S` / `↓` | Reverse |
| `A` / `←`, `D` / `→` | Turn port / starboard |
| `Space` / Left click | Fire broadside (both sides) |
| `R` / `Enter` | Restart (after game over) |

## Gameplay

- Endless waves of enemy warships spawn around you; each wave is bigger than the last.
- Small enemy Sloops are fast and take 3 hits. From wave 2 onward, armored Men-of-War can appear — slow, tanky, and they fire 6-ball volleys.
- Enemy ships hold distance and fire broadsides of their own. Position yourself so your broadside faces the enemy, and keep moving to dodge cannonballs.
- Score points for every kill. When you sink, press `R` to try again.

## Project layout

```
project.godot          # Godot 4.2 project, input map, GL Compatibility renderer
icon.svg
scenes/
  main.tscn            # World, water background, wave manager, HUD
  player_ship.tscn     # Player warship + camera
  enemy_ship.tscn      # Enemy warship (scaled up via is_big)
  bullet.tscn          # Cannonball
  explosion.tscn       # Particle explosion + flash
scripts/
  main.gd              # Wave spawning, score, game over/restart
  player_ship.gd       # Movement, broadside firing, health
  enemy_ship.gd        # Chase AI + broadside firing
  bullet.gd            # Cannonball movement, damage on hit
  explosion.gd, hud.gd
shaders/
  water.gdshader       # Animated procedural ocean (world-anchored waves)
```

## Tuning

All ship stats are `@export`ed on the scene scripts (speeds, damage, fire cooldowns, ranges) — tweak them in the Godot inspector on `player_ship.tscn` / `enemy_ship.tscn`.
