# Code layout and module contracts

**Status: IMPLEMENTATION CONTRACT (integration owner: Studio build thread).** Parallel threads write plain Luau against this layout so their PRs drop straight into the place. Keep modules pure where possible; the Studio thread owns remotes, UI, world, VFX and audio.

## Layout (Rojo-compatible, see `default.project.json`)

| Repo path | Studio location | Owner |
|---|---|---|
| `src/shared/Config/*.luau` | `ReplicatedStorage.Shared.Config` | config owners below |
| `src/shared/*.luau` | `ReplicatedStorage.Shared` | pure shared logic (e.g. `ForgeMath`) |
| `src/server/Services/*.luau` | `ServerScriptService.Server.Services` | service owners below |
| `src/server/Tests/*.spec.luau` | `ServerScriptService.Server.Tests` | each owner tests its own modules |
| `src/server/Main.server.luau`, `src/server/Net/*` | `ServerScriptService.Server` | Studio thread (bootstrap + remotes) |
| `src/client/**` | `StarterPlayer.StarterPlayerScripts.Client` | Studio thread |
| `src/build/**` | `ServerStorage.Build` (edit-time world builder) | Studio thread |

File conventions: `Foo.luau` = ModuleScript, `Foo.server.luau` = Script, `Foo.client.luau` = LocalScript. Use `--!strict` where practical. No external packages without recording license and version.

Sync: `python tools/devsync.py` then run `tools/sync.luau` in Studio (Rojo can replace this later; layout is identical).

## Service shape

Every `src/server/Services/X.luau` returns a table with optional `init()` (no yields, wire references) and `start()` (may spawn loops). `Main.server.luau` requires every module in `Services`, calls all `init`, then all `start`. Services require each other directly: `require(script.Parent.DataService)`.

Services **never create RemoteEvents or UI**. They expose functions returning `(ok: boolean, resultOrError)` and mutate the profile through `DataService`. The Studio thread maps remotes onto these functions and replicates profile snapshots to clients.

## Core forging and economy thread

- `Config/Materials.luau`: array of 32 `{ id, name, index, era, priceMin, priceMax, unlockCost, color: Color3, material: string (Enum.Material name), accent: Color3?, glow: boolean }` from `design/balance-v0.json`. Appearance fields drive weapon/ore skins.
- `Config/Balance.luau`: forge timings, luck constants, rarity/craftsmanship/trait tables, production rates, upgrade tracks (`ExtractorOutput`, `SmelterSpeed`, `StorageCapacity`, `FurnaceHeat`, `AnvilFinish`) with cost and effect functions, gear tracks (`Hammer`, `Gloves`, `Apron`), weapon classes (Sword, Greatsword, Axe, Dagger, Hammer) with 3 standard design ids each plus Legendary/Mythic design ids.
- `ForgeMath.luau` (pure, deterministic given a `Random`): `luckFromStrikes(validStrikes, windowSec) -> number` (clamped 1..5), `rarityChances(luck) -> {number}` (sums to 1), `rollWeapon(rng, materialIndex, classIndex, luck) -> Weapon`, `expectedValue(materialIndex, luck) -> number`.
- `Weapon` record: `{ id: string, m: number (material index), c: number (class index), q: number (craftsmanship 1..5), r: number (rarity 1..6), d: string (design id), t: string? (trait), v: number (sale value, integer, inside material band), ts: number }`.
- `Services/DataService.luau`: session-locked DataStore profiles (ProfileStore or equivalent), `get(player) -> Profile?`, `waitFor(player) -> Profile?`, `markDirty(player)`, `profileChanged: BindableEvent` (fires `(player, profile)` after any mutation), offline-production settlement on load, saves on interval/leave/BindToClose. Studio (no API access) must fall back to an in-memory profile without erroring.
- `Services/ProductionService.luau`: ticks ore → ingots for each loaded player within storage caps; `selectMaterial(player, index)`, `unlockNextMaterial(player)`, `rates(player) -> { orePerSec, ingotPerSec, capacity }`. Reads bonus multipliers from `CompanionService.bonuses(player)`, `EvolutionService.bonuses(player)` and `MonetizationService.owns(player, key)` when those modules exist (guard with `pcall(require, …)` until they land).
- `Services/ForgeService.luau`: server-owned sessions. `start(player, classIndex, materialIndex, mode: "manual"|"free"|"premium") -> (ok, { sessionId, heatSec, windowSec, revealSec })`; `strike(player, sessionId)` (rate-guarded, only counts inside the window); session completes on a server timer, rolls via `ForgeMath`, sets `profile.pending = Weapon`, fires `ForgeService.completed: BindableEvent (player, weapon, luck)`. `resolve(player, action: "sell"|"keep") -> (ok, result)`; selling is idempotent. Mode `premium` requires `MonetizationService.owns(player, "PremiumAutoForge")`. Auto modes loop until stopped or out of ingots: `stopAuto(player)`.
- `Services/UpgradeService.luau`: `buy(player, track) -> (ok, newLevel)` for machine and gear tracks.
- Profile fields owned here: `coins, lifetimeCoins, weaponsForged, highestWeaponValue, selectedMaterial, unlockedTier, ore {[index]=n}, ingots {[index]=n}, levels {[track]=n}, gear {[track]=n}, weapons {[id]=Weapon}, pending, showcase {id}, journal {[materialIndex]=rarityBitmask}, lastSeen`.

## Companions, eggs, rebirth, leaderboards and monetization thread

- `Config/Companions.luau` (kinds with name, rarity, bonus `{ extract?, smelt?, prep?, storage? }` as fractions, color, modelKind), `Config/Eggs.luau` (id, name, coin cost or unlock tier, weighted kinds), `Config/Products.luau` (game passes / dev products with `id = 0` placeholders and a `LIVE = false` switch).
- `Services/CompanionService.luau`: `hatch(player, eggId, count) -> (ok, {Pet})`, `equip(player, petId)`, `unequip(player, petId)`, `bonuses(player) -> { extract, smelt, prep, storage }` (additive per family, capped at +200%).
- `Services/EvolutionService.luau`: `status(player) -> { eligible, requirements, progress, preview = { keeps, resets } }`, `evolve(player, protected: boolean) -> (ok, newRank)`, `bonuses(player) -> { production, prep }`. One predicate for both paths; fresh-progress gate per `docs/13`.
- `Services/LeaderboardService.luau`: OrderedDataStores for the four metrics, throttled writes, `getTop(metric, n) -> {{ userId, name, value }}`, safe no-op in Studio without API access.
- `Services/MonetizationService.luau`: `owns(player, key) -> boolean`, `grantDev(player, key)` (Studio only), `ProcessReceipt` with idempotency in profile, PolicyService paid-random gate `canOfferPaidRandom(player)`. Never prompts while `Products.LIVE == false`.
- Profile fields owned here: `pets {[id]=Pet}, equipped {id}, petSlots, evolutionRank, forgedSinceEvolve, highestTierSinceEvolve, entitlements {[key]=true}, receipts {[purchaseId]=true}`.

## Tests

`src/server/Tests/X.spec.luau` returns `{ [testName] = function() ... end }` using `assert`. The Studio thread runs every spec in Studio and records results. Seed `Random.new(seed)` for distribution checks.
