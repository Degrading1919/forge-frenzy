# Owner playtest remediation: design and status (v2)

**Date:** October 8, 2026. **Implements:** [docs/21_OWNER_PLAYTEST_REMEDIATION.md](21_OWNER_PLAYTEST_REMEDIATION.md), which overrides older docs where they conflict. **Economy evidence:** [docs/23_ECONOMY_V2.md](23_ECONOMY_V2.md). **Branch:** `studio-integration` ([PR #5](https://github.com/Degrading1919/forge-frenzy/pull/5)).

This pass rebuilt the player-facing game around a physical, station-local workshop while keeping the proven backbone: server authority, ProfileStore sessions, receipt handling, leaderboards, paid-random gates and the forge RNG.

## Design principles taken from current Roblox hits

These come from studying tycoon, simulator, pet and "steal" games. Only the patterns were borrowed; no assets or exact layouts were copied.

- **Big and few.** Currency sits top-center and is the largest HUD element. A short column of chunky icon buttons sits on one side. Actions happen at world stations.
- **Thick outlines and saturated gradients.** Every button has a dark outline, a gloss band and a bottom lip, squishes on press and wiggles when it is disabled.
- **Celebrate everything.** Centered reveals use a sunburst, a burst of confetti, a big headline and one AWESOME button. Cash pops up, the cash counter rolls up, and there are announcement banners. Motion is slow and gentle, never a fast strobe.
- **Steal games build their tension** from visible loot, a slowed carrier with a marker, owner alerts, a one-touch return, and a timed laser lock.
- **Tycoons teach** with glowing pads that show their price, physically build what they name, and steadily transform your base.

## What changed, finding by finding

| Owner finding (docs/21 §17) | Resolution |
|---|---|
| Left-side UI clipping, forge clipping, poor button sizing | The whole UI was rewritten (`src/client/UI/Theme`, `Panels`, `Kit`). It is designed in "design pixels", device-scaled, and fits to the safe area. Checked on desktop and on an iPhone 17 Pro in landscape. |
| Remove persistent Forge button and Materials/Workshop from the left | Removed. The HUD is now the cash pill, an income chip, and BAG / PETS / SHOP / SET. |
| Station-local interaction | Prompts sit on forges, drills, smelters, the vault, the tool rack, podiums, pads, the collector, the lock button, the booth, eggs, the altar and the shop. Panels close when you walk away. The server enforces distance for manual forging, selling, pads, the collector, lock and steal. |
| Vertical simplified forge menu | `UIForgeStation` runs top to bottom: 1 MATERIAL, 2 WEAPON, ODDS, 3 AUTO FORGE, 4 AUTO SELL (only while an auto mode is chosen), then BEGIN. Nothing starts until BEGIN. |
| Labeled Auto Forge timer | The forge billboard and the panel footer say "🔥 Heating 1.2s", "🔨 Hammering 3.1s", "💧 Cooling" or "⏳ Waiting for ingots". A big red STOP button is shown. |
| Auto Sell moved into Auto Forge setup | The options are SELL ALL, KEEP RARE+, KEEP EPIC+ and KEEP LEGEND+, saved per forge. |
| Config change answered "forge busy" | `ForgeService.configure` stops that forge's auto loop cleanly and the forge in progress is abandoned at no cost. Only a manual forge still being hammered is protected. |
| Auto Forge covered the tutorial | The tutorial banner sits under the cash pill. It hides while any panel or reveal is open. The HUD hides during the minigame and reveals. |
| Centered currency with $ everywhere | Every amount goes through `Theme.money` / `moneyRate` ("$1.23K", "+$4/min"). |
| Direct material purchase; remove circles/rank; Steel "Rank" | Every ore-station tile is a material. Tap an owned one to mine it, or tap the next one to buy it at the price shown. Later ones show their price and a lock. Rank dots are gone. |
| Lower weapon previews over anvil | The `WeaponSpot` is 1.1 studs above the anvil face, and results float about 1.5 studs above it. |
| Clearer upgrade effects | Each row shows the per-level effect and "now → next" ("2.0/s → 2.3/s", "25 each → 35 each", "1.4s heat → 1.3s heat"). |
| Storage looked like a bookcase | It is now a blue diamond-plate vault with a hopper funnel, a glass window, a fill bar and a bin board. |
| Furnace and smelter were redundant | The smelter belongs to an ore line. Heat and quench upgrades belong to the forge, and the furnace is part of each forge station. |
| Conveyor flow | Drill, then a raised belt (ore visibly rides up and drops into the smelter hopper), then the smelter, then the output belt (glowing ingots), then the vault. Ore gems take the line's metal color. |
| Faster early game | Tin takes about 12 s, Bronze about 2 min, Iron about 10 min and Steel about 25 min for a free player. The second forge is affordable around 2.5 min (docs/23). |
| Walk speed | 28 (the default is 16). |
| Forge sign faces the hub | The owner sign text is on the face toward the hub and reads "Name's Forge ★rank". |
| Compact map and invisible boundary | Workshops are about 52 studs from the plaza instead of 93. There is an invisible wall ring at 132 studs plus a hedge ring and a ceiling. Hub stations sit between workshop paths. |
| Centered pet popup and button | `UI/Reveal` is centered with the pet name and rarity, and AWESOME sits directly under the model. Multi-hatch uses a grid. |
| Simplified evolution UI | A big "3 → 4", "CASH x2.5 → x3.0 FOREVER", two requirement bars, short KEEP/RESET lists, and one EVOLVE button that needs a second tap to confirm. |
| Evolution and displays | This was decided on purpose: **displays and weapons are kept**. Display income is capped at the most a weapon of the player's *current* tier could be worth, so old trophies cannot shortcut the climb. The KEEP list says "Weapons & displays". |
| Forge odds on unrelated UI | Removed from shop and hatch. Odds appear only in the forge flow. Eggs show their own pet odds. |
| Weapon-size recipe costs | Dagger 1 ingot, Sword 2, Axe 3, Hammer 4, Greatsword 5. Value multipliers are 1.2 / 2.3 / 3.25 / 4.15 / 5.0, so small weapons earn more per ingot and big weapons more per forge. |
| ~500 h to final material | Free automated play reaches Primordium in 494–496 h across 3 seeds; manual play takes 531 h and premium 162 h (docs/23). |
| Pet merging | Three of the same pet at the same level merge into one level higher, up to ★5, with multipliers 1 / 1.6 / 2.5 / 4 / 6.5. MERGE ALL and per-pet MERGE are available. Premium pets cannot merge. |
| Build pads / multiple stations | There are 12 pads: 3 pairs of podiums (up to 8), Forge #2 and #3, Ore Line #2 and #3, and 5 decorations. You step on a pad or press E. Built objects appear; unbuilt ones are parked server-side. Pads survive evolution. |
| Passive display income | Each podium earns 6% of the weapon's value per minute (capped by current tier) into the cash collector. The collector holds up to 1 hour of income, you step on it to collect, and it fills at 50% while you are offline. Cash Magnet (pass) auto-collects. |
| Sword stealing | Hold E for 2.5 s on another workshop's podium. The thief carries the weapon slowed to 70% with a "THIEF!" marker, and the owner gets an alert. Tagging the thief, the thief dying or leaving, or 40 s passing all return it. Ownership transfers only on reaching the thief's own workshop. Safeguards: a new-player shield (under 25 forges), a 20 s personal cooldown, a 90 s podium cooldown, and a carried weapon cannot be sold or moved. |
| 30 s laser Forge Lock | The owner presses LOCK at the gate. Red lasers flicker on the gate and wall tops, intruders are pushed out, and steal attempts are refused. After the 30 s lock ends there is a 60 s recharge. The HUD and the billboard show the timers. |
| Central sell booth | A big green booth with a merchant and a spinning $ sits in the center of the hub. SELL ALL / KEEP X+ show the exact payout. The server refuses a sale more than 24 studs away. Auto Sell remains the automation exception. |

Smaller additions made along the way:

- Auto forges remember their mode and resume after a rejoin.
- An auto forge that runs out of ingots waits instead of stopping.
- Each metal has its own storage bin, so old ingots never block a new metal.
- The backpack shows cards with a 3D close-up.
- Saves and leaderboards moved to fresh v2 stores.

## Architecture (what to read in the code)

- **Shared rules:**
  - `src/shared/Economy.luau` (schema v2): lines, stations, pads, bins, displays, bank, selling.
  - `Config/Balance.luau`: recipes, timing, display income, upgrade tracks.
  - `Config/Materials.luau`: the generated curve.
  - `Config/BuildPads.luau` and `Config/Evolution.luau`.
- **Services:**
  - `ForgeService`: one session per forge station, wait/resume, configure, stop and resume after a rejoin.
  - `WorkshopService` (new): pads, display income, collector, Forge Lock, stealing.
  - `CompanionService`: adds merging.
  - `EvolutionService`: literal tier goal, cash multiplier, refit of lines and forges to kept pads.
- **World glue:**
  - `Net/Plots.luau`: assignment, pad visibility, public visual state, and the geometry hooks for distance checks.
  - `Net/Remotes.luau`: v2 actions, snapshot, and friendly error text. The weapon list is only re-sent when it changes.
- **World:** `src/build/WorldBuilder.luau` (v2). `build()` moves the previous World into `ServerStorage.Backups` instead of destroying it.
- **Client:**
  - UI kit: `UI/Theme`, `Panels`, `Kit`, `Reveal`, `ForgeGame`, `Toast`.
  - Station panels: `UIForgeStation`, `UIOreStation`, `UIMachines` (vault and tools), `UIWeapons` (backpack, podium picker, sell booth), `UIPets` (pets, merge, hatch), `UIMeta` (evolution, shop, settings), `UIHud`.
  - World presentation: `WorldPrompts`, `WorldMachines` (belts, lasers, billboards), `WorldShowcase` (podiums and carried loot), `WorldForge`, `WorldOnboarding`, `WorldPets`.

## World contract (names the runtime reads)

**`Workspace.World`:**

- `Hub` contains:
  - `SellBooth` with `Window/PromptPoint` on four sides.
  - `Hatchery/Egg_<id>`.
  - `EvolutionAltar`.
  - `MerchantStall`.
  - `HallOfBlacksmiths/Board_*`.
- `Plots/Plot<i>`, with attributes `PlotIndex`, `OwnerUserId`, `VisualState` JSON, `LockedUntil` and `NextLockAt`, and these children:
  - `Bounds` (inside-workshop check), `EjectPoint`, `Lasers/*`, `LockButton`, `Collector`, `SignBoard/OwnerGui`, `PlotSpawn`.
  - `Machines/Line<i>`, attribute `LineIndex`, plus `PadId` for lines 2 and 3. Each has `Drill`, `OreBelt`, `Smelter` and `OutBelt`.
  - `Machines/Storage`, `Machines/Forge<i>` (attribute `ForgeIndex`; `Anvil/WeaponSpot`) and `Machines/ToolRack`.
  - `Showcase/Pedestal<slot>` (`Slot`, `PadId`).
  - `BuildPads/Pad_<padId>` and `Decor/Decor_<padId>`.
  - `ShowcaseData` JSON: `{ slots, unlocked, shield }`.
- `Boundary`.

## Known limitations and next owner checks

- **Feel to be judged in the owner playtest:** onboarding pace, the 2.5 s steal hold, the 40 s carry and the 60 s lock recharge. These values are in `WorkshopService.Logic` and are easy to retune.
- **Stealing between alt accounts can move weapons from one account to another.** No cash is ever created by a steal, so there is no money loop.
- **Visuals are procedural parts.** No paid Tripo generation was used. Weapon and pet models are the existing shared meshes and parts.
- **Two-client acceptance drives the server directly** with real clients, characters and timers. Client prompt input for stealing was checked by inspection in one client, not by two humans.
- **Purchases are still disabled.** Products are unchanged apart from descriptions; Collection Magnet was renamed Cash Magnet. Set MaxPlayers to 6 before any publish.
