# Forge Frenzy

A Roblox incremental blacksmithing game. Ore lines feed your forges, and you hammer out weapons whose metal, rarity, craftsmanship and traits set their value. You display the best ones for passive cash and steal from other players' workshops. Then you expand your workshop, hatch pets, evolve, and climb about 500 hours of metals.

**Status:** the v2 build is playable and ready for owner playtests. Purchases and publishing are disabled. `main` is the authoritative branch for all development.

## What is in the game

- **A station-local workshop.** You walk to your forges, ore lines, storage vault, tool rack, podiums and lock button. Build pads expand the workshop, and selling happens at a central booth.
- **Forging.** A server-owned click minigame drives luck, with free and premium Auto Forge. Thirty-two generated metals take about 500 hours of free automated play to the final one.
- **Display, steal and Forge Lock.** Displayed weapons earn passive cash. Other players can steal them:
  - the hold takes 2–8 seconds, depending on the weapon's value;
  - the thief has to carry it home, and the owner can tag them to get it back;
  - stolen weapons keep their full value;
  - a 30-second laser Forge Lock protects the workshop.
- **Pets, evolution and leaderboards.** Eggs, merging, evolution with permanent bonuses, and physical leaderboards.
- **Saves.** ProfileStore session-locked saves, with a durable, idempotent ledger for stolen-weapon transfers.

## Repository

| Path | Studio location | Contents |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | Pure rules (`Economy`, `ForgeMath`, `Steal`) and config (`Config/*`) |
| `src/server` | `ServerScriptService.Server` | `Main`, services, `Net` (remotes, plots), specs, the Studio multiplayer acceptance |
| `src/client` | `StarterPlayerScripts.Client` | Controllers and UI, plus a Studio-only acceptance driver |
| `src/build` | `ServerStorage.Build` | Edit-time tools: `DevSync`, `RunSpecs`, `TestPersistence`, `TestStealRecovery`, `TestLeaderboards`, `WorldBuilder` |
| `tools/lune` | – | Lune harness: `run-tests.luau`, `simulate-v2.luau`, `print-curve.luau` |
| `tools` | – | `devsync.py` (repo → Studio sync server), 1.0 export/recovery tools |
| `design` | – | `tripo-asset-manifest.json` (current); `balance-v0.json` (historical) |
| `docs` | – | See [docs/README.md](docs/README.md) for current versus historical documents |
| `artifacts` | – | 1.0 recovery snapshot |

## Working on it

Install [Lune](https://lune-org.github.io) 0.10.x; locally it lives at `.local/bin/lune-0.10.5/`, which git ignores. Run the tests and simulation from the repository root:

```bash
lune run tools/lune/run-tests.luau
```

```bash
lune run tools/lune/simulate-v2.luau free 900 1
```

To sync the source into the open Studio place, start the sync server:

```bash
python tools/devsync.py
```

Then run these in Studio, from the command bar or MCP, one call at a time:

```lua
return require(game.ServerStorage.Build.DevSync)()
return require(game.ServerStorage.Build.RunSpecs)()
return require(game.ServerStorage.Build.TestPersistence)()
return require(game.ServerStorage.Build.TestStealRecovery)()
return game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(2, { forgeFrenzyAcceptance = true })
```

Studio saves go to the isolated `ForgeFrenzy_Player_v2_StudioPlaytest` store. The tests use their own isolated stores and GUID keys. Never run `WorldBuilder.build()` on the live place without a reason: it backs the World up to `ServerStorage.Backups` first, but the hand-placed world is the authority.

A ready GitHub Actions workflow for the Lune suite is at `tools/ci/lune.yml`. To enable it, copy it to `.github/workflows/`. Pushing workflow files needs a token with the `workflow` scope (`gh auth refresh -s workflow`).

Agents: read [CLAUDE.md](CLAUDE.md) and [AGENTS.md](AGENTS.md).
