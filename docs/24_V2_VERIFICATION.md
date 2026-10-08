# v2 verification (owner playtest remediation)

> **Superseded counts:** the review remediation in [docs/25](25_REVIEW_REMEDIATION.md) is the current verification record. Lune is at 238/0 and Studio specs at 229/0. The two-client acceptance now has 20 checks, including real-client steal prompts. A real-DataStore steal-recovery test was added. The figures below are the original v2 evidence.


Recorded October 8, 2026 in the live Studio place (place `80574227639803`) and with Lune. All Studio saves used the isolated `ForgeFrenzy_Player_v2_StudioPlaytest` store; production data was untouched. No purchases, paid generation or publishing were performed.

## World preservation

Before anything was rebuilt, the original 1,489-descendant World was cloned to `ServerStorage.Backups.World_pre_remediation_9d4f3ba`. The first v2 build then moved the live original into `ServerStorage.Backups.World_20261008_111517`. Both copies are kept. Only intermediate generated v2 worlds were deleted. The repository's `artifacts/ForgeFrenzy-1.0-playtest.rbxm` remains the 1.0 recovery snapshot.

## Automated checks

| Check | Result |
|---|---|
| Lune suite (`tools/lune/run-tests.luau`) | **221 passed, 0 failed** |
| Studio spec runner (`RunSpecs`) | **212 passed, 0 failed**. WorkshopService runtime specs that need a patched Players service skip in Studio; the two-client run below covers the same flows. |
| Persistent save/rejoin (`TestPersistence`, real DataStore, isolated key) | **Passed.** It verified the economy, materials, collection, permanent progress and receipt, plus pads, ore-line metal, two forge recipes with auto mode, displays, collector cash and pet merge level. |
| Two real clients (`ExecuteMultiplayerTestAsync(2, {forgeFrenzyAcceptance = true})`) | **Passed in 31.5 s.** All 10 checks are listed below. |
| Progression simulations (`simulate-v2.luau`) | Free play reaches the final metal in 493.9, 496.4 and 496.0 h; manual in 530.9 h; premium in 161.6 h. See docs/23. |

Two-client checks, all with real characters and timers:

1. The two players get distinct isolated profiles and workshops.
2. A build pad works only when stood on, and builds podiums only in the buyer's workshop.
3. A manual forge is refused from far away. At the station it completes on real timers, and foreign strikes are rejected.
4. Free Auto Forge with SELL ALL earns cash and stops on request.
5. Selling is refused away from the booth and paid at the booth.
6. A displayed weapon fills the collector.
7. A steal works: a 2.5 s hold, a carry marker, and the weapon cannot be sold while carried. Ownership transfers only when the thief reaches home.
8. The owner tagging the thief returns the weapon to its podium.
9. Forge Lock publishes a 30 s timer, pushes the intruder out and refuses steals. It cannot be reused during the timer.
10. When one client leaves, its workshop is released and the other keeps theirs.

## Played and inspected in Studio

- **Opening as a new free player (fresh v2 profile, desktop):**
  - Walked to Forge 1, pressed E, saw the vertical forge panel and pressed BEGIN.
  - The tap minigame paid out a Rare dagger worth $119 after fast tapping. The centered reveal had AWESOME and DISPLAY.
  - Forged 3 by hand, which unlocked Auto.
  - Sold at the booth ("+$361").
  - Bought Tin by tapping its tile.
  - Started Auto with Sell All. Tickers showed "+$82 Tin Dagger".
  - Stepped on a pad: a "BUILT!" reveal, and two new podiums appeared.
  - Displayed a weapon from the backpack. The podium showed its name, value and "+$/min".
  - The tutorial walked through all 7 steps in order and finished with the lock tip.
- **Panels checked by screenshot:** Forge (forge and upgrade tabs), Ore station (32 metal tiles with prices), Storage Vault (bins and storage upgrade), Backpack (cards and 3D detail), Sell booth, Hatch (pet odds), and the pet reveal. Pet merge via MERGE ALL merged 3 sets into ★2 pets. Evolution showed "0 → 1", "CASH x1.0 → x1.5 FOREVER", requirement bars, KEEP/RESET and NOT READY YET.
- **Forge Lock:** the HUD showed a "🔒 FORGE LOCKED 30s → 19s" countdown and red lasers lit across the gate and wall tops.
- **Phone (iPhone 17 Pro, landscape, 750×382 viewport):**
  - The forge panel fits with BEGIN always visible in the footer.
  - The HUD cash pill and side buttons don't overlap.
  - The evolution sheet fits.
  - Text stays readable at about 0.6 scale.
  - **Portrait was not tested.** The experience is landscape-first.
- **World:** the compact six-workshop ring, the centered booth, and hub stations between the workshop paths. Owner signs face the hub, and workshops are colored per plot.

## Not covered and still owed to the owner

- **Two humans stealing with real touch input.** The two-client run drives the server with real characters; the client prompts were checked only in one client.
- **Feel and pacing over a long session.** The steal, lock and display numbers are first values (docs/22).
- **Portrait mobile.** Not checked.
- **MaxPlayers must be set to 6 before publishing.**
