# 🐐 Mountain Goat Racing — Complete Build Plan

### Final concept

**First-person 3D goat racing game** inspired by the mountain-goat POV references:

* Realistic alpine mountains
* First-person goat POV
* Goat horns visible
* Other goats racing ahead
* Natural rocky terrain — **no paved racing track**
* Steep cliffs and narrow ledges
* Downhill acceleration
* Jumping, climbing, sliding and falling
* Multiple mountain environments
* Browser playable
* Eventually deployable on Vercel

---

## Phase 1 — Project Foundation

**Stack**

```text
GLM-5.2 / ZCode
        ↓
     Godot 4
        ↓
      GDScript
        ↓
     Web Export
        ↓
      GitHub
        ↓
      Vercel
```

Set up:

* Git repository
* Godot project
* Modular folder structure
* Game configuration
* Input system
* Basic scene system

---

## Phase 2 — First 3D Prototype

Build only:

```text
Mountain
   +
Goat
   +
Camera
   +
Physics
```

Features:

* 3D terrain
* Placeholder goat
* First-person camera
* Goat horns/head visible
* Basic movement
* Gravity
* Jump
* Collision
* Downhill acceleration
* Restart

**Goal:** You can run a goat down a basic mountain.

---

# Phase 3 — Goat Physics

Make the goat feel like an actual mountain animal.

Implement:

* acceleration
* momentum
* slope detection
* surface grip
* downhill speed
* jumping
* air control
* landing
* sliding
* climbing
* falling
* collision response
* ragdoll

Surface behavior:

```text
Rock   → high grip
Grass  → normal
Snow   → slippery
Ice    → very slippery
Steep  → sliding
```

---

# Phase 4 — First-Person POV

Build the signature camera.

```text
       MOUNTAIN
          ↓

    🏔️       🏔️
       🐐 AI
          ↓

    ┌───────────┐
    │  HORNS    │
    │     🐐    │
    └───────────┘
       PLAYER
```

Camera behavior:

* head movement
* running bob
* turning
* slope tilt
* jumping
* landing
* falling
* speed effect
* collision shake

---

# Phase 5 — Realistic Mountain

Replace prototype terrain with a large alpine environment.

### Terrain

* mountains
* cliffs
* rock faces
* narrow ledges
* valleys
* slopes
* elevation changes

### Environment

* pine trees
* grass
* rocks
* snow
* streams
* fog
* clouds
* distant peaks

The mountain should look like your uploaded references.

---

# Phase 6 — Race System

Create the actual racing loop.

```text
START
 ↓
🐐 🐐 🐐 🐐
 ↓
Mountain
 ↓
Checkpoint
 ↓
Mountain
 ↓
Checkpoint
 ↓
FINISH
```

Implement:

* countdown
* race start
* checkpoints
* distance
* timer
* player position
* finishing order
* restart
* race results

---

# Phase 7 — AI Goats

Start with 3 AI opponents.

```text
YOU
🐐

AI 1
🐐

AI 2
🐐

AI 3
🐐
```

First version:

* waypoint-based racing
* downhill movement
* obstacle avoidance
* basic overtaking

Later:

* route selection
* shortcuts
* different personalities
* difficulty levels
* mistakes/crashes

---

# Phase 8 — Mountain Gameplay

Add things that make the mountain itself the challenge.

### Obstacles

* rocks
* fallen trees
* cliffs
* gaps
* snow patches
* ice
* narrow paths

### Terrain challenges

* steep slopes
* jumps
* wall sections
* sharp turns
* falling rocks
* unstable terrain

### Routes

```text
             🐐
              ↓
         ┌────┴────┐
         ↓         ↓
       SAFE      DANGER
         ↓         ↓
      slower    shortcut
         └────┬────┘
              ↓
            FINISH
```

---

# Phase 9 — Tricks & Scoring

Add skill-based gameplay.

### Tricks

* front flip
* back flip
* 360°
* long jump
* cliff jump
* near miss

### Score

```text
Distance
Speed
Coins
Tricks
Near misses
Race position
```

---

# Phase 10 — Progression

Create multiple mountains.

```text
Mountain 1
Alpine Valley
      ↓
Mountain 2
Rocky Ridge
      ↓
Mountain 3
Snow Mountain
      ↓
Mountain 4
Canyon
      ↓
Mountain 5
Extreme Summit
```

Add:

* XP
* coins
* goat upgrades
* speed
* jump
* grip
* stamina
* goat skins

---

# Phase 11 — UI

Create:

### In-game HUD

```text
┌────────────────────────────┐
│ PAUSE       1,250m    🪙 48 │
│                            │
│                            │
│          🐐 AI             │
│                            │
│                            │
│                            │
│   ◀                       ▶ │
│              JUMP          │
└────────────────────────────┘
```

Include:

* distance
* speed
* timer
* position
* coins
* pause
* restart
* race results

---

# Phase 12 — Audio & Effects

Add:

* goat footsteps
* goat sounds
* breathing
* rocks
* wind
* snow
* jumps
* impacts
* falling
* mountain ambience
* music

Visual effects:

* dust
* snow particles
* rocks
* motion effects
* camera shake
* landing effects

---

# Phase 13 — Optimization

Before deployment:

```text
3D Models
   ↓
LOD
   ↓
Instancing
   ↓
Compressed textures
   ↓
Optimized collisions
   ↓
Lighting optimization
   ↓
Browser performance
```

Target:

* desktop Chrome first
* 60 FPS target
* then mobile optimization

---

# Phase 14 — Web Build

Export Godot project for Web.

```text
Godot
  ↓
Web Export
  ↓
HTML / WASM / game files
```

Test:

* Chrome
* Edge
* Safari
* different screen sizes
* keyboard
* mouse
* mobile controls later

---

# Phase 15 — Vercel Deployment

```text
Godot
 ↓
Web Build
 ↓
GitHub
 ↓
Vercel
 ↓
your-game.vercel.app
```

Then add custom domain later.

---

# Phase 16 — Backend

**Only after the game is fun.**

Add:

```text
Game
 ↓
Backend
 ↓
PostgreSQL
```

For:

* accounts
* player profiles
* saved progress
* scores
* leaderboards
* achievements

---

# Phase 17 — Multiplayer

Last.

Possible architecture:

```text
Player 1 ─┐
Player 2 ─┼──→ Game Server
Player 3 ─┤
Player 4 ─┘
              ↓
          Race State
              ↓
          Leaderboard
```

Don't build this until the single-player game is solid.

---

# Development order

The actual order should be:

```text
1. Project setup
       ↓
2. 3D terrain
       ↓
3. Goat
       ↓
4. Goat physics
       ↓
5. First-person camera
       ↓
6. Downhill movement
       ↓
7. Realistic mountain
       ↓
8. One complete race
       ↓
9. AI goats
       ↓
10. Obstacles
       ↓
11. Tricks / scoring
       ↓
12. Multiple mountains
       ↓
13. Progression
       ↓
14. UI / audio / effects
       ↓
15. Optimization
       ↓
16. Web export
       ↓
17. Vercel
       ↓
18. Backend / leaderboard
       ↓
19. Multiplayer
```

## 🎯 MVP target

The **first playable milestone** is deliberately small:

> **One realistic 3D mountain + one goat + first-person horn POV + downhill physics + jumping + falling + one finish line.**

Once **that feels fun**, we build everything else around it.
