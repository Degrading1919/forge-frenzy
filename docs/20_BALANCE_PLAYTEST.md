# Progression simulation evidence — 1.0 playtest candidate

> **Historical record (pre-v2).** Superseded by the current documents listed in [docs/README.md](README.md). The v1 simulators and runners it mentions (`simulate-economy.luau`, `simulate-progression.luau`, `run-specs.luau`, `tools/sync.luau`) were removed during the October 2026 consolidation. They are still in git history before that cleanup. Current equivalents: `tools/lune/simulate-v2.luau`, `tools/lune/run-tests.luau` and `ServerStorage.Build.DevSync`.


Recorded October 7, 2026. **Simulation evidence, not earned Studio progression or human playtest evidence.** Balance constants remain PROPOSED; this investigation changed no gameplay curves.

## Reproduce

Run from the repository root with Lune 0.10.5:

```powershell
& '.local/bin/lune-0.10.5/lune.exe' run tools/lune/simulate-progression.luau 720 all .local/progression-results.json
```

The runner prints CSV snapshots at 10, 30, 60, 360 and 720 minutes for seeds 1, 2 and 3. The optional JSON output retains unrounded timestamps, coins, lifetime earnings, retained weapons, pet spending and individual first-tier times. A numeric second argument runs one seed; the default duration is 360 minutes. The script and the existing Lune Roblox shim are checked in; the generated JSON is local evidence.

## Model and decisions

The simulation calls the checked-in `Economy` rules and the real `CompanionService.Logic` and `EvolutionService.Logic`. It grants no passes, purchases, currency, pets or evolution eligibility. Production runs during heat, strikes, reveal and any material wait. Manual cycles include the server's 0.35-second strike latency grace. A forge pays its material at the roll; checkpoints stop at the exact requested time.

Three active-player strategies are compared:

| Strategy | Luck | Weapon decision |
|---|---:|---|
| `free-auto-collector` | 1.5x | Actual free-auto default: keep Epic+ and sell lower rarities |
| `free-auto-seller` | 1.5x | Set the free automatic keep threshold to 7, selling all results |
| `manual-seller` | 2.5x | A consistent five valid strikes/second; manually sell every result |

All strategies choose the highest unlocked material with available ingots, switch recipes after unlocks, buy the next material as soon as affordable, and buy machine/gear upgrades whose next cost is at most 20% of the next material's unlock price. Companion spending stays within a cumulative budget of 20% of lifetime earned coins. The simulated player hatches one newest unlocked egg per forge cycle, seeks at most six rolls per egg family, and calls `equipBest`. This bound is a simulated purchase decision, not a gameplay hatch limit. If a companion inventory ever fills, the strategy releases its weakest companion; if kept weapons fill, it sells its cheapest kept weapon. Neither capacity fallback was needed before reaching tier 32 in these runs.

The player takes the **first normal evolution** immediately upon eligibility, then progresses without further evolutions. Gear and companions survive through the real reset list. An evolution is therefore visible as a lower temporary tier in the 30-minute snapshot. Later ranks, protected evolution, premium acceleration, offline production, walking/menu/hatch-animation time and inconsistent manual performance are outside this model. Randomness comes from the Lune shim; exact seeded sequences are not a promise that Roblox's `Random` will produce the same sequence.

## Exact early snapshots

Entries of the form `a / b / c` correspond to **10 / 30 / 60 minutes**, respectively. Material starvation means a failed start because no unlocked material has an ingot; the simulator waits one second and checks again. All nine runs recorded **zero material-starved attempts and zero material-idle seconds**, including the long run.

| Strategy | Seed | Temporary tier 10/30/60 | Highest tier 10/30/60 | Forges 10/30/60 | Pets 10/30/60 | Evolution rank 10/30/60 |
|---|---:|---|---|---|---|---|
| Free auto collector | 1 | 3 / 2 / 6 | 3 / 4 / 6 | 64 / 196 / 400 | 0 / 2 / 6 | 0 / 1 / 1 |
| Free auto collector | 2 | 3 / 2 / 6 | 3 / 4 / 6 | 64 / 196 / 401 | 0 / 1 / 6 | 0 / 1 / 1 |
| Free auto collector | 3 | 2 / 2 / 5 | 2 / 4 / 5 | 64 / 196 / 399 | 0 / 1 / 6 | 0 / 1 / 1 |
| Free auto seller | 1 | 3 / 3 / 7 | 3 / 5 / 7 | 64 / 198 / 406 | 0 / 3 / 6 | 0 / 1 / 1 |
| Free auto seller | 2 | 3 / 3 / 7 | 3 / 5 / 7 | 64 / 197 / 406 | 0 / 2 / 6 | 0 / 1 / 1 |
| Free auto seller | 3 | 3 / 2 / 7 | 3 / 4 / 7 | 64 / 198 / 406 | 0 / 2 / 6 | 0 / 1 / 1 |
| Manual seller | 1 | 3 / 2 / 8 | 3 / 5 / 8 | 62 / 194 / 400 | 1 / 5 / 6 | 0 / 1 / 1 |
| Manual seller | 2 | 3 / 3 / 8 | 3 / 5 / 8 | 62 / 193 / 396 | 0 / 4 / 6 | 0 / 1 / 1 |
| Manual seller | 3 | 3 / 2 / 7 | 3 / 5 / 7 | 62 / 191 / 395 | 0 / 3 / 6 | 0 / 1 / 1 |

## First milestones and late progression

Times are elapsed minutes, printed to three decimal places by the runner. Every run reached Primordium without premium features after the one normal evolution.

| Strategy | Seed | First Tin | First egg | First normal evolution | First tier 32 | Tier at 360 min | Forges at 360 min |
|---|---:|---:|---:|---:|---:|---:|---:|
| Free auto collector | 1 | 5.155 | 16.011 | 22.879 | 386.692 | 29 | 2948 |
| Free auto collector | 2 | 4.999 | 16.595 | 22.881 | 382.003 | 30 | 2963 |
| Free auto collector | 3 | 5.156 | 16.457 | 22.891 | 384.637 | 29 | 2951 |
| Free auto seller | 1 | 3.431 | 10.912 | 22.640 | 336.595 | 32 | 2989 |
| Free auto seller | 2 | 2.957 | 13.659 | 22.732 | 335.288 | 32 | 2991 |
| Free auto seller | 3 | 3.906 | 13.996 | 22.689 | 338.566 | 32 | 3013 |
| Manual seller | 1 | 3.231 | 9.127 | 23.224 | 326.992 | 32 | 2879 |
| Manual seller | 2 | 2.903 | 11.949 | 23.338 | 323.512 | 32 | 2859 |
| Manual seller | 3 | 3.730 | 13.233 | 23.559 | 303.263 | 32 | 2869 |

At 720 minutes all runs remain tier 32/rank 1. Exact final `(forges, pets, hatches)`:

| Strategy | Seed 1 | Seed 2 | Seed 3 |
|---|---|---|---|
| Free auto collector | 6106, 31, 31 | 6112, 30, 30 | 6213, 31, 31 |
| Free auto seller | 6250, 32, 32 | 6201, 32, 32 | 6204, 32, 32 |
| Manual seller | 5888, 32, 32 | 5855, 32, 32 | 5868, 32, 32 |

## Findings and next human checks

- No material deadlock or numerical failure appeared through all 32 tiers. Free production supported every attempted forge in this strategy, including the reset. No gameplay balance change was justified by starvation.
- The default free collector unlocks Tin around five minutes, slightly beyond the 2–5-minute target in two seeds. Keeping rare valuable weapons delays income. The free automatic sell-all setting reduces this to 2.957–3.906 minutes; its UI should make this tradeoff understandable.
- First companions arrive at 16.011–16.595 minutes for the default free collector and 9.127–13.996 minutes for the selling strategies. These are compatible with the 10–20-minute companion target, subject to real navigation/input time.
- First evolution arrives at 22.640–23.559 minutes, slightly earlier than the proposed 25–45-minute target. Menu/navigation/hatch time is excluded, so this does not justify raising the gate before human playtesting. The post-reset player still has gear and companions and rebuilds to tiers 5–8 within the first hour.
- With one reset, first Primordium takes approximately 5.1–5.6 hours for selling strategies and 6.4 hours for the default collector. Later evolutions intentionally extend this; reaching tier 32 is not equivalent to completing all collections or evolution ranks.
- An initial exploratory simulation spent the same 20% pet budget continuously on cheaper old eggs and released thousands of duplicates. This slowed 360-minute progress to tiers 22–24/free and 28–29/manual. The documented six-per-family decision model removes that unhelpful simulated spending behavior. Gameplay prices were not changed. Real players should be observed for repeated low-tier hatching that feels unrewarding.
- Machine supply upgrades remain optional rather than necessary in the first hour under one-roll forging. Multi-Forge, player idle habits and different purchase priorities need separate economy scenarios and actual playtests. Zero simulated starvation does not measure game feel or mobile input quality.
