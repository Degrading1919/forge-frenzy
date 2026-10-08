# Forge Frenzy 1.0 playtest evidence

**Status: 1.0 ready for the owner's full playtest; purchases and publishing disabled.**
**Evidence checkpoint: October 7, 2026.** Integration branch: `studio-integration`, [PR #5](https://github.com/Degrading1919/forge-frenzy/pull/5). This records observed Studio results; older design/bootstrap status labels describe earlier checkpoints. Commercial launch remains unapproved.

## Preservation and implemented changes

Before editing, all 69 live scripts matched the existing `a15e664` checkout byte for byte. The cloneable World and service/script content were backed up to `.local/backups/ForgeFrenzy-before-Codex.rbxm` (202,994 bytes); Git history was preserved in `.local/backups/pre-codex-a15e664.bundle`. No WorldBuilder regeneration was invoked. Place `80574227639803`, universe `10769806075`.

The existing production, forging, upgrades, inventory/showcases, companions, evolution and UI were retained. Changes include complete Multi-Forge settlement/reveal behavior, server-side entitlement and paid-random gates, receipt durability/idempotency, mobile panel/forge layouts, companion serial safety, and persistence/leaderboard lifecycle fixes. Multi-Forge charges each actual roll separately, preserves the primary reveal, and filters automatic extras according to the keep threshold.

Production profile names remain `ForgeFrenzy_Player_v1` / `Player_<UserId>`. Studio uses `ForgeFrenzy_Player_v1_StudioPlaytest` and separate ordered boards; unavailable APIs use explicitly reported session Mock mode. Storage failures cannot silently replace a production save with a fresh memory profile. Immediate saves wait for confirmed revisions; departure/shutdown snapshots avoid callback-order races. Ordered writes use monotonic `UpdateAsync`, retry transient failures and retain cached rankings.

## Observed verification

| Area | Evidence at this checkpoint |
|---|---|
| Automated checks | Final full suites: Studio **149 passed, 0 failed**; Lune **153 passed, 0 failed**, including the departure-retry regression. |
| Persistent save/rejoin | Actual Studio API **Access**, persistent isolated helper run `b772b3f3-0b56-4d32-8bfe-53ed2cfd4d40`: confirmed manual/final saves, reacquired session, economy, materials, weapons, pets/equips, entitlements, evolution and receipt marker restored. A subsequent real play session restored its pending weapon. |
| Global boards | Real isolated ordered stores, run `b242e6d4-a2b5-4b5a-b098-e8591d5bb28c`: four writes and cached ranked reads, stale-server monotonic writes, player-name lookup and recovery from an injected prewrite transient failure passed. Production board records were unchanged. |
| Multiplayer | Actual two-client acceptance passed in **19.03 seconds**: distinct profiles/plots, isolated upgrade/hatch/equip/forge mutations, foreign weapon/pet/strike rejection, timed manual forging and actual kicked-client plot/showcase cleanup. |
| Desktop forging | Actual UI input: **31 valid strikes, 2.55x luck**; Multi-Forge spent two ingots and produced independent values **20 and 22**. Premium auto **4x** and free auto **1.5x** start/stop paths exercised. |
| Companions and premium test mode | Hearth hatch spent **1,200 coins**; Equip Best added **4% extraction**; release was confirmed. All ten Studio DevGrant products succeeded with purchases disabled. Five-egg Multi-Hatch added five pets and spent **6,000 coins**. |
| Evolution | Protected UI path rank **0→1** retained coins/tier, consumed protection and unlocked slot three; immediate repeat remained ineligible. Normal path rank **1→2** reset coins to zero/tier to one and retained weapons/pets. |
| Audio | Actual `ContentProvider` preload: **15 sounds loaded, 0 failed**. |
| Mobile visuals | iPhone 14 portrait inspected: scrollable five-egg results, forge picker/reveal, inventory detail, materials, companions and workshop. Landscape evolution has a scrollable body and fixed confirmation overlay. Actual input automation used desktop coordinates; these establish layout evidence, not a completed touch-input playtest. |
| Workshop appearance | Normal single-client Play: owned Copper gem matches material color. A client-only public-state fixture on an empty second plot rendered Tin, gold Titan housing, UpgradeGlow and four upgrade orbs correctly, then was cleared. Authoritative player data was unchanged by this visual fixture. |

Temporary fixture resources were restored through DevBridge with a confirmed durable save and deep comparison of the original core/collection fields: **19 coins, rank 0, two weapons forged**, kept weapon `w2`, receipts, pets/equips and showcase. Fixture resources are **not earned progression evidence**. Native Studio MCP was used for the recorded Studio work; no computer-use operations followed the owner's restriction. Production player data was untouched. No real purchases, paid generation or publishing operations were performed.

An additional automated multiplayer renderer probe failed and was removed after the appearance issue did not reproduce in normal Play. The successful 19.03-second two-client gameplay run remains valid; the later public-state appearance check used one client. No seven-client test completion is claimed. The experience currently permits 60 joins against six workshop plots; code rejects an overflow player with a clear full-server message. **Set the experience's MaxPlayers to 6 before publishing.** No further high-memory multiplayer sessions are required for tonight's playtest.

## Synchronized build and recovery

Final Edit-mode reconciliation found **75 scripts across 88 source items, zero source/class mismatches or unmanaged scripts**. The existing World still contains **1,489 descendants**; no regeneration was used. Studio is left in Edit mode ready to press Play. The final solo save was confirmed persistent at `1791425350`: 19 coins, rank zero, two weapons forged, purchases disabled.

[ForgeFrenzy-1.0-playtest.rbxm](../artifacts/ForgeFrenzy-1.0-playtest.rbxm) is a **318,633-byte service-container model**, verified through an unparented serialize/deserialize round-trip with exact script sources and hierarchy counts. SHA256: `f9045088b06a9801a6ea6828989735590ecdf18ee05d73f9df31fe2dae20ec50`. [Metadata](../artifacts/ForgeFrenzy-1.0-playtest.metadata.json) records selected service settings. This is a recoverable snapshot, **not a full .rbxl**: Terrain, Camera, cloud settings and player data are excluded. For recovery in a separate place, move each container's children into its corresponding service; StarterPlayerScripts/StarterCharacterScripts are Folder wrappers whose children belong in those existing built-in containers. Do not import over the current place merely to start a playtest.

Implementation commits: `41ed8b1` (save/leaderboard lifecycle), `043ec1b` (Multi-Forge, economy and premium settlement), `e4a162f` (mobile UI and public workshop presentation). Tooling, this evidence, balance simulation and the model accompany the final handoff commit on PR #5.

## Reproduce checks

From the repository root:

```powershell
.local/bin/lune-0.10.5/lune.exe run tools/lune/run-tests.luau
.local/bin/lune-0.10.5/lune.exe run tools/lune/simulate-economy.luau
```

For sustained free progression, see [the separate simulation evidence](20_BALANCE_PLAYTEST.md); it describes its assumptions and does not substitute for a human pacing session.

After source is synchronized, use Studio's existing MCP/plugin execution context:

```lua
return require(game.ServerStorage.Build.RunSpecs)()
return require(game.ServerStorage.Build.TestPersistence)()
return require(game.ServerStorage.Build.TestLeaderboards)(POSITIVE_CURRENT_USER_ID)
return game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(2, {
    forgeFrenzyAcceptance = true,
})
```

Run these as separate calls. `TestPersistence(true)` forces Mock and cannot establish cross-play durability. Persistent helpers require the already-enabled API setting and create isolated acceptance keys/stores; they do not alter API settings or original stores. Multiplayer acceptance requires synthetic Studio players, restores their backed-up profiles, and ends through `StudioTestService:EndTest` with structured evidence. Ordinary play and published servers do not activate its driver.

## Tonight's playtest

- Press Play in the current Studio place. Start free: forge/sell/keep/showcase, upgrade/unlock, hatch/equip, evolve and rejoin; assess pacing and reveal feel across a sustained session. Studio saves use an isolated persistent namespace, and the HUD reports the storage mode.
- Use Shop's Studio test grants to exercise premium auto, Multi-Forge, Multi-Hatch, cosmetics and protected evolution without Robux. Pass overlays end with the session; granted test items/coins belong only to the isolated Studio profile.
- Mobile: test real touch input, small-screen scrolling, modal close actions and orientation changes. Inspect simultaneous players and populated plots for performance and visibility.
- Commercial launch remains unapproved. Actual Robux purchase paths stay disabled; configured product IDs, live receipt/policy behavior and production-scale datastore/platform failures are not established by these isolated tests. Existing reusable visuals remain functional; no claim is made that every Tripo-manifest asset was generated/imported.
