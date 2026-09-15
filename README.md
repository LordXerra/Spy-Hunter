# Spy Hunter

A macOS remake of the 1983 arcade classic, written in Swift with SpriteKit.

**Version V0.99** · Developed by Tony Brice · Free, including the source code.

---

## The arcade game

*Spy Hunter* was released by Bally Midway in 1983. You drive the G-6155
Interceptor, a spy car loaded with weapons, up an endless scrolling road full
of enemy agents. The cabinet had a steering yoke, a gear shift and an
accelerator pedal. Its looping "Peter Gunn" theme is one of the best-known
pieces of music in arcade history.

What made it stand out:

- **You choose how to deal with each enemy.** Machine guns handle most agents,
  but some are bulletproof and have to be rammed off the road. The helicopter
  can only be brought down with missiles.
- **Weapons vans.** A red lorry drives up the road with its ramp down. Drive
  into the back of it and you come out armed with oil slicks, smoke screens or
  missiles.
- **Innocent traffic.** Civilian cars share the road. Destroy one and your
  score freezes for a moment, so you have to shoot carefully.
- **Boathouses.** The road sometimes forks into a boathouse. Drive through it
  and your car turns into a speedboat for a stretch of river combat.
- **The opening timer.** Every game starts with a countdown during which you
  have unlimited cars. Score well enough before it runs out and you bank extra
  lives for the rest of the game.

## This version

This remake tries to play as close to the arcade original as possible, with
some modern upgrades:

- Arcade enemy line-up, kill rules, weapons van, boathouses, water sections,
  fog and ice, the opening timer and the bonus-car system
- Arcade point values for every enemy, and the arcade's score-freeze penalty
  for destroying friendlies
- Layered explosions, flying debris, sparks, screen shake and controller rumble
- Full PS4 (DualShock 4) and PS5 (DualSense) controller support, as well as
  keyboard
- A new track is generated for every game: straights, bends, narrow sections,
  forks, bridges and causeways
- Three difficulty levels: Novice, Normal and Expert
- A top-10 high-score table with 3-letter initials, saved between sessions
- Windowed or fullscreen play, remembered between launches
- A pause and options menu with music and sound-effect toggles

### Differences from the arcade

- **Distance points are scaled up.** Published sources give 15 points per screen
  on the road and 25 on water. At those rates the documented 18,000-point bonus
  is almost impossible to reach inside the opening timer, so this version pays
  180 per screen on the road and 300 on water. The road-to-water ratio is kept.
- **Missiles fire automatically at the helicopter.** When a Mad Bomber is
  overhead and you are carrying missiles, the fire button launches a missile
  instead of the guns.
- **The boat always has missiles.** On water, the rear-weapon button fires a
  missile, and boat missiles never run out.

---

## How to play

Drive as far as you can and destroy enemy agents without harming civilians.
You score for distance and for every agent you destroy. The game ends when you
run out of cars.

### Controls

#### In game

| Action | Keyboard | PS4 / PS5 controller |
|---|---|---|
| Steer | **A / D** or **← / →** | Left stick or D-pad left/right |
| Accelerate | **W** or **↑** | Left stick or D-pad up |
| Brake | **S** or **↓** | Left stick or D-pad down |
| Fire machine guns (or missiles at a helicopter) | **Shift** | **R2** or **R1** |
| Drop rear weapon (oil / smoke) or fire a missile from the boat | **Space** | **L2**, **L1** or **Square** |
| Pause / options menu | **Esc** or **P** | **Options** or **Circle** |
| Fullscreen / windowed | **F1** or **⌘F** | — |
| Quit | **⌘Q** | — |

With no throttle input the car settles back to cruising speed. On a controller
the left stick is analogue, so a small push steers gently.

#### Title screen

| Action | Keyboard | Controller |
|---|---|---|
| Start game | **Shift**, **Space** or **Return** | **Cross**, **R2** or **L2** |
| Change difficulty | **← / →** or **↑ / ↓** | D-pad |
| Options menu | **Esc** or **P** | **Options** or **Circle** |

If left alone, the title screen cycles through the title art, the high-score
table and the credits.

#### Pause / options menu

Move with **↑ / ↓** (stick or D-pad on a controller). Select with **Return**,
**Space** or **Shift** (**Cross** or **R2**). Close it with **Esc** or **P**
(**Options** or **Circle**). The menu lets you:

- **Resume** the game
- Switch the **screen** between fullscreen and windowed
- Turn **music** on or off
- Turn **sound** effects on or off
- **Exit to title**
- **Exit game**

#### Entering your initials

| Action | Keyboard | Controller |
|---|---|---|
| Change letter | **↑ / ↓** | Stick or D-pad up/down |
| Move between letters | **← / →** | D-pad left/right |
| Set letter | **Shift**, **Space** or **Return** | **Cross** or **R2** |
| Back one letter | **Esc** | **Circle** |

The entry saves automatically after 30 seconds with no input.

### The screen

- **Top left:** your score
- **Top right:** the current high score
- **Bottom right:** the opening timer, counting down from 999
- **Bottom centre:** weapons you are carrying (`MSL`, `OIL`, `SMK`, with
  counts)
- **Bottom left:** spare cars, shown once the opening timer has run out

### Starting a game and lives

Each life begins with the Interceptor backing out of a weapons van.

1. **The opening timer.** The counter at the bottom right runs from 999 down to
   0 over about 90 seconds. Until it reaches zero you have **unlimited cars**:
   crash as often as you like.
2. **Bonus cars.** When the timer runs out you get **2 spare cars** if your score
   has reached **18,000**, otherwise **1**.
3. **Extra cars.** After that you earn another car every:
   - **10,000 points** on Novice
   - **15,000 points** on Normal
   - **20,000 points** on Expert
4. When you lose a car with no spares left, the game is over. A top-10 score
   lets you enter your initials.

You lose a car by:

- Running too far off the road, or off a bridge into the water
- Hitting roadside trees or fence posts
- Being caught by a bomb, torpedo or floating charge
- Taking any hit while in the boat

In the car, a shot from the Enforcer only **spins you out**, and bumping into
another vehicle just shoves it aside. Switchblade's slashers **blow your
tyres**, and you lose steering for a few seconds.

### Weapons

| Weapon | How to get it | What it does |
|---|---|---|
| **Machine guns** | Always fitted, unlimited | Destroys most agents after a few hits. Useless against the Road Lord's armour and cannot reach the helicopter. |
| **Oil slick** | Weapons van (5 per load) | Dropped behind you. Any agent that drives over it spins out and crashes. |
| **Smoke screen** | Weapons van (5 per load) | Dropped behind you. Any agent that drives into it spins out and crashes. |
| **Missiles** | Weapons van (6 per load); unlimited on the boat | The only way to down the Mad Bomber. Destroys any unarmoured target in one hit. |

If you carry more than one rear weapon, the rear-weapon button uses oil first,
then smoke, then missiles.

### The weapons van

The red weapons van runs up the road ahead of you with its beacon flashing. As
you close in behind it, the rear ramp drops and you can see what it carries:
missiles, oil or smoke. **Drive straight into the back** to go aboard. You ride
inside while it loads, then roll out armed. Clipping the side of the van only
bumps it.

Don't shoot the van. It counts as a friendly, and destroying one freezes your
score. If an enemy bomb destroys it while you are inside, you are thrown clear
without the weapons.

### Enemy agents

#### On the road

| Agent | Nickname | How it attacks | How to beat it | Points |
|---|---|---|---|---|
| **Switchblade** | "Never To Be Trusted" | Pulls alongside and extends tyre slashers | Guns, oil, smoke, or ram it off the road while its blades are in | 150 |
| **Road Lord** | "Bulletproof Bully" | Armoured car that sits ahead and blocks you | **Ram it off the road**, or use oil or smoke. Guns and missiles bounce off. | 150 |
| **Enforcer** | "Double Barrel Action" | Limousine with a gunman firing back at you | Guns, oil, smoke, or ram it off the road | 500 |
| **Mad Bomber** | "Master Of The Sky" | Helicopter dropping bombs on the road | **Missiles only**. It flies off after a while if you have none. | 700 |

#### On the water

| Agent | How it attacks | How to beat it | Points |
|---|---|---|---|
| **Barrel Dumper** | Drops floating charges in your path | Guns or missiles | 150 |
| **Doctor Torpedo** | Fires torpedoes back down the river | Guns or missiles | 500 |
| **Mad Bomber** | Follows you over the river too | Missiles (the boat always has them) | 700 |

**Ramming** works on anything on the road. Keep pushing sideways and the target
goes over the edge. Lightweight vehicles fly further. Heavy ones barely move
and cost you most of your speed.

### Friendlies and penalties

Civilian cars, lorries, motorbikes, tugboats, pleasure boats and weapons vans
are all friendlies. Destroying one, by shooting it or running it off the road,
doesn't subtract points. Instead your score counter **stops for a moment**,
just like the arcade:

| Destroyed | Score frozen for | About how many points you miss |
|---|---|---|
| Civilian vehicle or boat | 1 second | ~150 |
| Weapons van | 2 seconds | ~300 |
| Tugboat | 3 seconds | ~450 |

### Scoring summary

| Source | Points |
|---|---|
| Distance on the road | 180 per screen |
| Distance on water | 300 per screen |
| Switchblade, Road Lord, Barrel Dumper | 150 |
| Enforcer, Doctor Torpedo | 500 |
| Mad Bomber | 700 |

### The road ahead

The further you drive, the harder it gets:

- **Bends and narrow sections.** Stay on the tarmac: the verge slows you, and
  going too far off it wrecks the car.
- **Forks.** The road splits around an island and joins up again later.
- **Bridges and causeways.** There is water on one or both sides, and anything
  pushed over the edge sinks, including you.
- **Boathouses.** Drive through the doorway to turn into a boat. A second
  boathouse at the end of the river turns you back into a car. You are safe
  while the change happens.
- **Fog** hides what is coming up the road.
- **Ice** removes most of your grip, so the car keeps sliding after you stop
  steering.
- **Difficulty.** Agents arrive more often and the dangerous ones appear sooner.
  Normal and Expert ramp up faster than Novice, and Expert allows two Mad
  Bombers in the air at once.

### Tips

- In the opening 90 seconds you have unlimited cars, so play aggressively and
  push for 18,000 to earn the double bonus.
- Drop an oil slick or smoke screen when an agent is right behind you.
- Save missiles for the Mad Bomber, since guns cannot touch it.
- Only ram a Switchblade while its blades are retracted.
- The Enforcer sits ahead of you to shoot back down the road. Take it out
  quickly, or keep out of its line of fire.
- Look before you shoot: that car in front might be a civilian.

---

## Building and running from source

### Requirements

- macOS 13 (Ventura) or later
- Xcode 16 or later (or a Swift 6 toolchain)
- *For `build_app.sh` only:* Python 3 with [Pillow](https://pypi.org/project/pillow/)
  (`pip3 install pillow`)

### Run directly

```bash
swift run -c release
```

`swift build` then `.build/debug/SpyHunter` also works, but the debug build is
slower.

### Build a Mac app

```bash
./build_app.sh
```

This rebuilds the game resources from `Sprites/` and `Music/`, compiles a
release build, creates `Spy Hunter.app` with its icon, and installs it into
`/Applications` so it appears in Launchpad. To build into `build/` without
installing:

```bash
./build_app.sh --no-install
```

To build a universal app that also runs on Intel Macs, set
`SPYHUNTER_UNIVERSAL=1` before running the script.

### Project layout

| Path | Contents |
|---|---|
| `Sources/SpyHunter/App` | Application start-up, window and menu |
| `Sources/SpyHunter/Scenes` | Title screen, game, pause menu and initials entry |
| `Sources/SpyHunter/Entities` | Player car and boat, enemy agents, traffic, projectiles |
| `Sources/SpyHunter/Systems` | Road generation, spawning, scoring, input, audio, effects, rumble |
| `Sources/SpyHunter/Support` | Settings, high scores, sprite atlas, bitmap font, tuning constants |
| `Sources/SpyHunter/Resources` | Runtime sprite sheet, font, title art and music (generated) |
| `Sprites/`, `Music/` | Original source artwork and music |
| `Tools/` | Python asset pipeline and app-icon generator |

Gameplay tuning values (speeds, scores, timers, ammo) are in
`Sources/SpyHunter/Support/GameConfig.swift`. Difficulty settings are in
`Sources/SpyHunter/Support/Settings.swift`.

---

## Credits

- **Developed by** Tony Brice
- **Technical support by** Aaron Thorne
- **Testing by** Triona Melhuish, AJ Brice and Nailesh Sheth
- **Spy Hunter theme** remixed by Mozzaratti from the original game music by
  Peter Gunn, used with kind permission
- **Title music** by -Z64
- **Sprite sheet** ripped from the arcade original by Yawackhary

*Spy Hunter* was originally created by Bally Midway in 1983. This is a
non-commercial fan remake.

This game is free, including the source code. All images belong to their
respective creators.
