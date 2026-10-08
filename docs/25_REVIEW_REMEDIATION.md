# Review remediation: stealing, station authority and selling kept weapons

Recorded October 8, 2026, on `studio-integration` (PR #5). This answers an outside review of the v2 build. Each finding was checked against the code before anything was changed. All of them reproduced.

## Findings

| Finding | Verdict | Evidence before the fix |
|---|---|---|
| Fixed 2.5 s steal hold | Replaced by design | `STEAL_HOLD_SEC = 2.5` for every weapon |
| Forge Lock survives a workshop changing hands | **Confirmed** | `locks[plot]` was never cleared in `Plots.assign`/`release`, so a new owner inherited the old lock and cooldown |
| Station actions trust the client's open panel | **Confirmed** | `ForgeConfigure`, `ForgeBegin` (auto), `LineMaterial`, `UnlockMaterial`, `BuyUpgrade`, `Hatch` and `Evolve` had no server position check |
| Cross-profile steal persistence | **Confirmed** | Two independent `saveNow` calls after an in-memory move: a crash between them could duplicate or lose the weapon |
| Teleport-assisted delivery | **Confirmed** | Delivery fired the moment the thief's root part was inside their own workshop, wherever it came from |
| Cross-tier steal cash-out | **Confirmed; kept by owner decision** | Stealing an endgame weapon every 2 minutes and selling it reaches the final metal in 40.8 h. The owner decided stolen weapons keep their full value (see below) |
| Auto Forge mode buttons | **Confirmed** | OFF / AUTO / PREMIUM only changed a local variable while Auto Forge ran |
| Weapon card income uncapped | **Confirmed** | `UIWeapons` showed `v × 0.1%/s`; the server pays the tier-capped amount |
| (found while testing) Evolve then sell | **Confirmed** | Selling kept weapons right after each evolution reached the final metal in 407 h instead of ~500 h |
| (found while testing) Swapping the podium mid-hold | **Confirmed** | The hold pinned the podium slot, not the weapon, so a swap stole whatever was there at commit |
| (found while testing) Per-podium cooldown | **Confirmed** | Its key used `typeof(victim) == "Instance"` at write but `victim.UserId` at read; consistent now |

## Value-based steal hold

One shared rule, `src/shared/Steal.luau`, used by the prompt (client) and enforced by the server:

```
hold = clamp(round_to_0.5( 2 + 6 × clamp((log10(value) − 3) / 13, 0, 1) ), 2, 8) seconds
```

| Weapon value | Hold | Typical weapon |
|---|---|---|
| up to $1K | 2.0 s | starter daggers and swords |
| $30K | 2.5 s | a Gold greatsword |
| $1M | 3.5 s | mid game |
| $100M | 4.5 s | Adamantite |
| $100B | 5.5 s | late game |
| $1T | 6.0 s | late game |
| $1Qa | 7.5 s | Primordium |
| $10Qa and up | 8.0 s | the best endgame weapons |

Value, not rarity, decides it; rarity raises value, so it counts naturally.

The server:

- pins the exact weapon (id, value, timestamp, material, rarity) at `StealBegin` and returns the hold time;
- refuses a commit sooner than the hold minus 0.3 s of latency, so a client cannot shorten it;
- cancels the hold every heartbeat if the thief leaves the podium, dies or disconnects, the owner locks the forge, the workshop changes hands, or the pinned weapon moves, is replaced or is sold;
- refuses the commit (`Moved`) if the podium shows anything other than the pinned weapon.

The prompt shows "Worth $X · hold Ns" and never changes its hold time while it is being held. The owner is alerted when the hold starts ("X is stealing your …! Lock your forge or chase them!") and again when the weapon is grabbed.

## Security and persistence fixes

- **Forge Lock hand-over.** `WorkshopService.resetPlot` runs whenever `Plots` assigns or releases a workshop. It clears the lock and its cooldown, cancels holds on that plot, and publishes zeros to the plot attributes.
- **Station authority.** `Plots.nearPlace` checks the player stands within 26 studs (flat) of the prompt that opens the panel. The client closes panels at 22 studs.
  - `ForgeConfigure` and starting Auto Forge need that forge.
  - `LineMaterial` and `UnlockMaterial` need that ore line's drill or smelter.
  - `BuyUpgrade` needs the track's station: Ore, Storage, Forge or Tools.
  - `Hatch` needs that egg's stand, and `Evolve` needs the altar.
  - `ForgeStop` works anywhere: stopping is always safe. Running automation keeps going after the player walks away.
- **Teleport check.** A carry keeps a movement allowance: it refills at 30 studs/s, a carrier walks at 19.6, and it can bank up to 30 studs. That absorbs about 1.5 s of lag catching up at once. Spending more than 10 studs past the allowance ends the carry, and the weapon flies home. A server eject resets the baseline. No delivery happens within 2 s of the grab, even between neighbouring workshops.
- **Durable transfer (steal ledger).** Two profiles cannot be written atomically, so delivery is three confirmed steps. Neither player has to come back for the thief to get the weapon.
  0. The thief's profile records `xferPending[id] = { from = victim, wid, at }`, and that save is confirmed first. Until then the weapon stays in the victim's backpack, protected like a carried weapon: it cannot be sold or moved, and it earns nothing.
  1. The weapon leaves the victim's backpack into `victim.outbox[id]`, and the victim's save is confirmed. If that save fails while the victim is still here, the weapon goes back on its podium.
  2. The thief receives it, with the id moved from `xferPending` to `xferIn` in the same profile. Once the thief's save is confirmed, the outbox entry is acknowledged. If the thief is not on this server, the delivery is queued into their saved profile with `ProfileStore:MessageAsync` and applied by a `MessageHandler` when they load.

  Recovery runs from both sides:
  - **Victim side:** the victim's profile re-sends its outbox when it loads and every 30 s while loaded.
  - **Thief side:** the thief's profile checks each pending id when it loads and every 5 minutes while online. It reads the victim's saved profile read-only (`ProfileStore:GetAsync`) and takes the weapon from the victim's outbox, so a victim who never plays again cannot hold up delivery.
  - **Expiry:** a pending id whose victim never committed expires after 30 minutes. That is far longer than any save in flight.

  After any crash the weapon is in exactly one durable place: the victim's saved backpack, the victim's saved outbox, or the thief's saved backpack. `xferIn` makes every re-delivery a no-op. This is a recoverable multi-step transfer, not an atomic DataStore transaction.
- **Prompt completion race (found by the real-client test).** A real ProximityPrompt fires its hold-ended event, which sends StealCancel, the moment a hold completes. That arrives just before Triggered (StealCommit). The server cleared the hold on that cancel, so the commit always failed with `NoIntent`: **through the real prompt, no steal could ever succeed.** Earlier tests called the server directly and missed it. A cancel now only counts while the hold is still short of its full time.

## Stolen weapons keep their full value (owner decision)

A first version capped what a stolen weapon sold for at the thief's progression. The owner rejected that because it removes the reason to steal, so **stolen weapons sell and display for their full value**. They are marked `st` so the card shows "stolen from …", and they do not raise the "best weapon forged" stat.

`Economy.usableValue` still caps one case: **a weapon the player forged in a metal above their current one**, which in practice is a trophy kept through an evolution. It sells for what the same weapon would be worth in the player's best metal now, at their own evolution bonus. Its card keeps the full value, and the full value returns once the player reaches that metal again. This closes the "evolve, then sell every old trophy" shortcut (407 h to the final metal before the fix).

- **Display income:** unchanged rule. Every weapon, stolen or not, earns on its value capped at the current tier's best roll.
- **Weapon card:** shows the real income, plus "Sells for $X until you unlock <metal>" for capped trophies.
- **Sell booth:** the preview totals what the booth will really pay.

## Test evidence

### Automated (Lune, mocked Roblox and storage)

`tools/lune/run-tests.luau`: **238 passed, 0 failed.** These run the real game modules with fake players, positions and saves. They cover:

- **Holds:** the hold table, server enforcement, and early release vs completion.
- **Mid-hold changes:** swap, replace or remove the weapon; walk-off, death and lock.
- **Movement:** teleports and speed hops are rejected.
- **Ownership:** the lock resets on hand-over.
- **Every ledger stage:** a failed thief save, a failed victim save, a victim released mid-save, a crash before delivery, thief-side recovery when the victim never returns, and expiry when the victim never committed.
- **Repeats and timing:** re-delivery and message idempotency, and protection while saving.
- **Selling values:** stolen weapons and trophies.
- **Messages:** DataService message handler and `sendMessage`.

These prove the logic, not Roblox's services.

### Studio, real ProfileStore and DataStores (one Studio process)

| Check | Result |
|---|---|
| Studio spec runner (`RunSpecs`) | **229 passed, 0 failed** |
| `TestPersistence`: isolated real save, release and re-acquire | **Passed (StudioPersistent)** |
| `TestStealRecovery`: steal ledger on real profiles, isolated store `ForgeFrenzy_StealRecovery_v1` | **Passed, 4 cases** |

`TestStealRecovery` cases:

- **A:** the victim's save holds the outbox and the thief's save only the pending record; both sessions end (a crash). The victim never returns. The thief's next session collects the weapon from the victim's saved profile, exactly once, and it survives a further restart.
- **B:** the same delivery message is sent twice to an offline thief's key. The thief's session applies it once, and the processed messages are not offered again after a restart.
- **C:** a message reaches a thief whose session is active in this server.
- **D:** after a crash, the victim restarts first and re-sends, then the thief's queued message and pending record both arrive. One copy results.

Ending a session and starting a new one on the same key is what moving between servers looks like to ProfileStore: the session lock is released and re-acquired. **Two live servers at the same time were not exercised.**

### Real Studio multiplayer (two clients, one Studio server)

`ExecuteMultiplayerTestAsync(2, {forgeFrenzyAcceptance = true})`, StudioPersistent isolated store: **passed, 20 checks, 72 s.**

The thief's and owner's clients use the actual world prompts through `src/client/AcceptanceDriver.client.luau`. It calls `ProximityPrompt:InputHoldBegin/InputHoldEnd`, walks with `Humanoid:MoveTo`, and reads the client's own toasts and HUD. The driver exists only in Studio and only while the acceptance run creates its remote.

Observed:

- **Prompt for a $1Qa weapon:** "STEAL / Worth $1Qa · hold 7.5s". Hold 7.5 s, keys E and ButtonX, tap-and-hold enabled for touch.
- **Early release:** after 3 of 7.5 s nothing was stolen, and the owner's client received "… is stealing your …".
- **Full 7.5 s hold:** the carry started. The thief's screen showed "RUN HOME WITH THE LOOT! 40s" and the carry marker.
- **Walking home:** at carrier speed 19.6 the walk was accepted. The weapon was delivered, the ledger settled, and the weapon is in the thief's *saved* profile, which is what a rejoin loads.
- **Lock mid-hold:** the owner's client tapped LOCK 2 s into a 6 s hold. Nothing was stolen, and the thief's client was told the forge locked.
- **Server-driven checks (unchanged):** the 2.5 s hold and durable delivery, teleport rejection, the mid-hold swap, the stolen $48.7B weapon selling in full, tag-back, Forge Lock, station authority with Auto Forge still running, the lock cleared when the owner leaves, and departure cleanup.

## Verified, simulated, and still to check

| Status | What |
|---|---|
| **Verified in real Studio multiplayer** | Real steal prompt holds (2.5, 6 and 7.5 s), early release, completion, alerts, carry banner and marker, walking delivery, lock mid-hold, teleport rejection, Forge Lock, station authority, ownership hand-over |
| **Verified against real DataStores (one process)** | Save, release and re-acquire; steal ledger recovery when the victim never returns; duplicate and live messages; restart and re-send |
| **Automated with mocks only** | Every crash and failure ordering of the ledger, expiry, movement budget edges, hold timing tolerance |
| **Simulated** | Economy pacing (below) |
| **Needs a human playtest** | Touch tap-and-hold on a phone, gamepad ButtonX on a controller, how 7–8 s holds feel to younger players, the Auto mode buttons clicked by a person, the "Sells for … until you unlock …" wording on old trophies |
| **Cannot be tested locally** | Two live servers at once (cross-server messaging and GetAsync timing under real load), real network latency and packet loss, production DataStore throttling |

## Economy after the fixes (900 h cap)

Run: `lune run tools/lune/simulate-v2.luau <scenario> 900 <seed>`. Simulation evidence, not a human playtest. Stealing scenarios are a worst case: every steal is a top-roll Mythic Primordium greatsword from a rank-13 player.

| Scenario | Final metal | Before these fixes |
|---|---|---|
| Free auto, seeds 1 / 2 / 3 | **512.0 h / 508.8 h / 515.1 h** | 493.9 h / 496.4 h / 496.0 h |
| Manual forge 1 + free auto | 543.8 h | 530.9 h |
| Premium | 182.1 h | 161.6 h |
| Steal an endgame weapon every 2 min, all game | **40.8 h** (full value, owner decision) | 40.8 h |
| Steal an endgame weapon every 15 min, all game | **86.5 h** (full value, owner decision) | — |
| Sell kept weapons after every evolution (seeds 1 / 2) | **520.3 h / 516.0 h** | **407.1 h** |

Readout:

- **Free baseline.** It moved from ~495 h to ~512 h, still about the 500 h target. The old simulated player already sold the trophies that a newer weapon pushed off its podiums after an evolution, at full value. The trophy cap removes that small cash-out, so no curve parameters were changed. A control run of the same simulated player with the cap switched off (`free-uncapped`) reaches the final metal in 498.9 h, so the cap accounts for about 13 h. The rest comes from the simulated player now choosing displays by actual income.
- **Stealing.** With full-value steals, a player who could steal a top endgame weapon every 15 minutes for the whole game would finish in about 86 h. That is a worst case: it assumes a rank-13 Primordium victim is always online, unlocked and not shielded. Real stealing depends on who is in the server, the 20 s personal and 90 s podium cooldowns, Forge Lock and tagging. A related case is an alt account stealing from a main to skip the climb. That is now an accepted part of the design and worth watching in live play.
- **Evolve-then-sell.** No longer a shortcut.

## Remaining risks

- **Cross-server timing.** Thief-side recovery and delivery messages rely on ProfileStore's GetAsync and MessageAsync. Their behaviour across two live servers, and under DataStore throttling, is untested here. Recovery checks run when the thief joins and every 5 minutes, so a stuck delivery could take that long to appear.
- **Pending expiry.** If a victim's commit save reaches the DataStore more than 30 minutes after the thief's pending record (not expected; saves time out in seconds), the thief-side path would have expired. The victim's next session would still re-send it.
- **Short hops.** The movement check allows about 40 studs of instant movement (lag tolerance) and 1.5× running speed. Neighbouring workshops are close, so the 2 s minimum carry and tagging remain the main counterplay there.
- **Hold release.** The server cannot see a key being released. A client that never sends `StealCancel` still has to stand at the podium and keep the pinned weapon unchanged for the full hold.
- **Station range.** It is lenient (26 studs) to avoid false refusals on lag and large models, and should be tuned with real players.
- **Stealing pays in full.** This is the owner's decision. High-value steals can shortcut progression a lot when rich victims are around, and an alt account can steal from a main to skip the climb. The ~500 h target applies to ordinary free automated progression.
