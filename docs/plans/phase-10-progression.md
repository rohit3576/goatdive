# 🐐 Phase 10 — Progression: Execution Plan

> Expands `README.md` → *Phase 10 — Progression* into concrete, executable
> steps. The mission: **turn individual mountain runs into an addictive,
> persistent racing campaign** — trick scores and coins feed persistent XP
> and currency, bankable upgrades tangibly boost goat athleticism, horn/coat
> skins personalize the first-person view, and 5 distinct alpine mountains
> test mastery across snow, ice, and sheer canyon walls.
>
> ⚠️ **Scope fence:** 
> - **Persistence**: Local client-side storage via `user://progression.cfg`
>   (100% web/IndexedDB export compatible). Server backend / leaderboards
>   belong to Phase 16.
> - **Physics integrity**: Upgrades apply as bounded percentage multipliers
>   on the verified Phase 3–9 physics substrate (`Config` base constants).
>   Physics logic is never rewritten. AI herd baseline remains constant so
>   upgrades feel earned and visibly rewarding.
> - **UI scope**: Functional pre-race garage / mountain picker and post-race
>   progression tally. Full responsive HUD and visual overhaul belong to
>   Phase 11.
> - **Audio / Polish**: Level-up audio stings and mountain ambience belong
>   to Phase 12.

---

## Goal & Progression Loop

```text
                     🏔️ SELECT MOUNTAIN (1 of 5)
                               ↓
                 🐐 UPGRADE STATS & EQUIP SKINS
                               ↓
                     🏁 4-GOAT DOWNHILL RACE
             (Tricks · Combos · Coins · Position · Time)
                               ↓
                     📊 POST-RACE INTAKE
            ┌──────────────────┴──────────────────┐
            ↓                                     ↓
     🪙 COINS BANKED                       ⭐ XP EARNED
  (Course pickups + Podium)              (Trick pts + Clean race)
            ↓                                     ↓
     UPGRADE SHOP                         LEVEL PROGRESSION
  • Top Speed   (+4%/tier)                • Unlocks Mountains 1–5
  • Jump Height (+4%/tier)                • Unlocks Goat Skins
  • Surface Grip (+5%/tier)
  • Slam Stamina (+6%/tier)
            └──────────────────┬──────────────────┘
                               ↓
                    CAMPAIGN PROGRESSION 🚀
```

**Definition of Done:**
1. **Persistent State**: Progress (coins, XP, level, upgrades, unlocked mountains/skins) automatically saves to `user://progression.cfg` and survives game restarts.
2. **Upgrades that Feel Great**: Purchasing Speed, Jump, Grip, or Stamina visibly alters downhill speed, jump apex, corner carving, and landing slam tolerance.
3. **First-Person Skins**: Equipping skins updates the horns in the camera POV and the goat coat/snout in the world.
4. **5 Unique Mountains**: Player can select and race across all 5 distinct procedural environments (Alpine Valley, Rocky Ridge, Snow Mountain, Canyon, Extreme Summit), each with custom terrain noise, snow lines, and hazards.
5. **Headless Verification**: Complete automated smoke battery (`smoke_phase10.gd`) proving save serialization, upgrade math, mountain generation across all 5 seeds, and a 4-goat gauntlet run (`gauntlet_phase10.gd`) on multiple mountains with 0 errors.

---

## Decisions Locked in Phase 10

| # | Decision | Choice | Why |
|---|---|---|---|
| **D1** | Local Persistence | `ConfigFile` at `user://progression.cfg` | Native Godot format, schema-flexible, automatic key-value mapping, zero external dependencies, seamless HTML5 IndexedDB compatibility. |
| **D2** | Dual Economy | **Coins** = spendable currency (stats & cosmetic skins); **XP** = non-spendable rank (unlocks mountains & skins) | Separates player capability upgrades (economic choice) from campaign milestones (skill & persistence). |
| **D3** | Bounded Multipliers | Upgrades modify base physics via bounded linear steps (+4% to +6% per tier, max Tier 5) | Prevents broken game physics or out-of-bounds speed while delivering clear, tactile sense of progression (Tier 5 goat is ~20% faster and leaps ~20% higher). |
| **D4** | Herd Stays Baseline | AI goat profiles (CAUTIOUS, BOLD, RECKLESS) stay at baseline tuning | Player upgrades directly improve overtaking ability against the benchmark herd, transforming early-game nail-biters into decisive victories. |
| **D5** | 5 Procedural Mountains | Data-driven procedural configs driving existing `TerrainGenerator`, `Obstacles`, and `CourseBuilder` | Maximizes content variety without hand-modeling or asset bloat; seed + terrain noise parameters produce drastically different downhill challenges. |
| **D6** | First-Person Skins | Skins change Horn material (albedo, roughness, metallic) and Body/Snout albedo | Horns sit directly in the first-person camera view; skins are immediately visible every second of gameplay. |
| **D7** | Post-Race Intake Flow | Results screen calculates XP and Coins live with animated counters, then hands off to Garage or Retry | Clear feedback loop connects trick score and race performance to campaign growth. |
| **D8** | Pre-Race Garage Overlay | Modular UI canvas (`Garage`) for mountain selection, upgrade purchases, and skin preview | Keeps menus fast, clean, and easily maintainable before Phase 11's dedicated UI art pass. |
| **D9** | Seed-Safe Course Corridors | Each mountain seed defines unique gate placements and fallen log distributions via `CourseBuilder` | Guarantees every mountain has a verified descent path, valid check gates, and jumpable obstacles. |
| **D10** | Config Centralization | All progression pricing, upgrade curves, and mountain metadata reside in `Config.gd` | All balance tuning lives in one single file, preserving project discipline. |

---

## The 5 Mountains Catalog

Every mountain modifies the terrain parameters, vegetation distribution, and surface friction:

| Mountain | Theme | Seed | Peak (m) | Snow Line (m) | Terrain Character | Hazard Profile |
|:---|:---|:---:|:---:|:---:|:---|:---|
| **1. Alpine Valley** | Rolling green alpine meadows | `1337` | 260 | 170 | Wide grassy fall lines, gentle rock ridges | Standard corridor boulders, 2 fallen logs |
| **2. Rocky Ridge** | Jagged granite ledges | `2048` | 290 | 190 | Sharp domain warping (`warp: 85m`), steep cliff bands | Dense boulder fields, narrow ledge tracks |
| **3. Snow Mountain** | Glaciated frozen descent | `4096` | 275 | 90 | Low snow line, expansive ice fields (`grip: 0.15`) | Low-friction slide zones, high-speed jumps |
| **4. Canyon Run** | Deep cut gorges and drop-offs | `8192` | 310 | 220 | Massive domain warp (`warp: 110m`), steep chutes | Sheer cliff drops, high fallen-log arcs |
| **5. Extreme Summit** | The ultimate technical ridge | `9999` | 340 | 140 | Maximum elevation, rapid grade changes | Tight boulder choke points, blind crests |

---

## Goat Upgrades System

Each stat has 5 upgrade tiers (Tier 0 = stock, Tier 5 = maxed):

| Stat | In-Game Effect | Base Value | Tier 5 Value | Scaling Step | Cost Curve (Coins) |
|:---|:---|:---:|:---:|:---:|:---:|
| **Speed** | Top downhill speed & flat acceleration | $12.0\text{ m/s}$ / $38\text{ max}$ | $14.4\text{ m/s}$ / $45.6\text{ max}$ | $+4\%$ per tier | 100, 250, 500, 1000, 2000 |
| **Jump** | Vertical takeoff velocity & air authority | $9.5\text{ m/s}$ / $0.35\text{ air}$ | $11.4\text{ m/s}$ / $0.42\text{ air}$ | $+4\%$ per tier | 100, 250, 500, 1000, 2000 |
| **Grip** | Turn carving sharpness & low-friction traction | $6.28\text{ rad/s}$ | $7.85\text{ rad/s}$ ($+25\%$) | $+5\%$ per tier | 100, 250, 500, 1000, 2000 |
| **Stamina** | Landing slam absorption & stumble recovery | $10.0\text{ impact}$ / $0.5\text{s}$ | $13.0\text{ impact}$ / $0.35\text{s}$ | $+6\%$ per tier | 100, 250, 500, 1000, 2000 |

---

## Goat Skins Catalog

Skins apply immediate custom materials to both the player's horns (in-camera) and character body:

| Skin ID | Name | Fleece Tint | Horn Material | Unlock Condition |
|:---|:---|:---:|:---|:---|
| `classic` | **Alpine Classic** | Natural Brown-White | Natural Keratin Bone ($R=0.55$) | Default (Unlocked) |
| `snow_phantom` | **Snow Phantom** | Frost White | Crystalline Glacial Cyan ($M=0.2, R=0.15$) | Reach Level 3 |
| `obsidian_ram` | **Obsidian Ram** | Charcoal Black | Polished Obsidian Jet ($M=0.8, R=0.2$) | Reach Level 5 or 800 Coins |
| `golden_capra` | **Golden Capra** | Royal Cream | Metallic Polished Gold ($M=0.95, R=0.1$) | Reach Level 8 or 2500 Coins |

---

## Step-by-Step Implementation Plan

### Step 1 — Progression System & Local Persistence
**Files:** `scripts/game/progression.gd` (Autoload / State Manager), `scripts/game/config.gd`
* Implement `Progression` manager tracking:
  - `coins: int`, `xp: int`, `level: int`
  - `upgrades: Dictionary` (`{"speed": 0, "jump": 0, "grip": 0, "stamina": 0}`)
  - `unlocked_mountains: Array[String]`, `current_mountain: String`
  - `unlocked_skins: Array[String]`, `current_skin: String`
* Local I/O methods: `save_to_disk()`, `load_from_disk()`, `reset_progression()`
* XP leveling formula: $\text{Level} = 1 + \lfloor\sqrt{\text{XP} / 300}\rfloor$
* Unit verification: headless save, modify, reload, and verify integrity.

### Step 2 — Stat Upgrades & Physics Wiring
**Files:** `scripts/player/goat_controller.gd`, `scripts/game/config.gd`
* Read upgrade tiers from `Progression` at spawn.
* Compute effective player stats:
  - `effective_speed = Config.MOVE_SPEED * (1.0 + speed_tier * 0.04)`
  - `effective_max_downhill = Config.MAX_DOWNHILL_SPEED * (1.0 + speed_tier * 0.04)`
  - `effective_jump_vel = Config.JUMP_VELOCITY * (1.0 + jump_tier * 0.04)`
  - `effective_turn_rate = Config.TURN_RATE * (1.0 + grip_tier * 0.05)`
  - `effective_stumble_impact = Config.STUMBLE_IMPACT * (1.0 + stamina_tier * 0.06)`
* Ensure AI goats continue using unscaled `Config` baseline.

### Step 3 — First-Person Horn & Fleece Skins
**Files:** `scripts/player/horns.gd`, `scenes/goat/goat.tscn`, `scripts/player/goat_controller.gd`
* Expose skin application method `apply_skin(skin_id: String)`.
* Update `horns.gd` to instantiate and apply horn materials dynamically based on selected skin.
* Update `Torso` and `Snout` mesh instances with skin fleece material overrides.

### Step 4 — Multi-Mountain Catalog & Generation Parameters
**Files:** `scripts/terrain/mountain_catalog.gd`, `scenes/terrain/mountain_level.gd`, `scripts/terrain/terrain_generator.gd`
* Create `MountainCatalog` containing procedural presets for all 5 mountains.
* Parameterize `MountainLevel` to accept `mountain_id` (via `Progression.current_mountain` or scene argument) and configure:
  - Terrain seed, peak height, snow line, warp strength, cliff bands
  - Course generation seed and gate layout
  - Obstacle and fallen tree distributions

### Step 5 — Results Screen Progression Intake & Unlock Flow
**Files:** `scripts/race/race_manager.gd`, `scripts/race/race_hud.gd`, `scripts/game/event_bus.gd`
* In `_player_finish()`, bank collected coins into `Progression.coins`.
* Convert trick points + finish position into XP: $\text{XP} = \text{Score} / 5 + \text{PodiumBonus}$.
* Update `RaceHUD` results overlay to display:
  - Coins collected (+banking animation)
  - XP earned and XP bar progression toward next level
  - "NEW UNLOCK!" banner if new mountain or skin threshold reached

### Step 6 — Pre-Race Garage & Mountain Selection UI
**Files:** `scenes/ui/garage.tscn`, `scripts/ui/garage.gd`
* Clean staging screen presented before race start:
  - **Mountain Carousel**: Browse unlocked mountains, view terrain stats and best times.
  - **Upgrade Station**: Buy Speed, Jump, Grip, Stamina tiers with instant coin deduction.
  - **Skin Selector**: Preview and equip unlocked horn/fleece skins.
  - **Start Race Button**: Launches selected mountain level.

### Step 7 — Verification Suite & Gauntlet Regression
**Files:** `smoke_phase10.gd`, `gauntlet_phase10.gd`
* **Smoke Battery**:
  - Save/load persistence roundtrip test.
  - Upgrade math verification (speed, jump, grip, stamina scaling).
  - Skin material assignment test.
  - Generation test of all 5 mountains (height queries, valid gates, obstacle records).
* **Gauntlet Grand Prix**:
  - 4-goat race on Mountain 1 (Alpine Valley) and Mountain 3 (Snow Mountain).
  - Confirm herd finish times, obstacle avoidance, and zero crashes.
* Headless boot check (`godot --headless --quit-after 240`).

---

## Configuration Additions (`scripts/game/config.gd`)

```gdscript
# --- Phase 10: Progression & Upgrades ----------------------------------------
const SAVE_PATH := "user://progression.cfg"
const XP_BASE_DIVISOR := 300.0

const UPGRADE_MAX_TIER := 5
const UPGRADE_COSTS := [100, 250, 500, 1000, 2000]

const STAT_STEP_SPEED := 0.04     # +4% per tier
const STAT_STEP_JUMP := 0.04      # +4% per tier
const STAT_STEP_GRIP := 0.05      # +5% per tier
const STAT_STEP_STAMINA := 0.06   # +6% slam absorption per tier

# --- Mountain Catalog Seeds & Unlocks ---------------------------------------
const MOUNTAIN_UNLOCK_LEVELS := {
	"alpine_valley": 1,
	"rocky_ridge": 2,
	"snow_mountain": 4,
	"canyon_run": 6,
	"extreme_summit": 8,
}
```

---

## Risks & Mitigation Strategies

| Risk | Impact | Mitigation Strategy |
|:---|:---:|:---|
| **Save File Corruption / Missing File** | High | Provide safe fallback defaults in `Progression.gd`. If file does not exist or fails parsing, initialize a clean default profile without crashing. |
| **Overpowered Upgrades Breaking Physics** | Medium | Cap upgrades strictly at Tier 5 ($+20\%\text{ to }+30\%$ max delta). Gravity and collision capsule sizes remain untouched. |
| **New Mountain Seeds Creating Unfair Jumps** | Medium | Every mountain profile uses verified `CourseBuilder.in_gate_zone` and checks slope gradients at gates. Gauntlet test runs all 5 mountains. |
| **Ice Surface Physics Too Slippery** | Low | Grip upgrade specifically adds flat traction boost on ice, rewarding players who upgrade before tackling Snow Mountain. |

---

## Handoff → Phase 11

With Phase 10 complete:
* All 5 procedural mountains and progression economy are fully operational.
* Phase 11 (*UI Overhaul*) will replace placeholder panels with styled mobile/desktop HUD, speedometers, minimaps, pause menus, and polished garage presentation.
