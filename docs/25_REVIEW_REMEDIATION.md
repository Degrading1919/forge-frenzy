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
- **Durable transfer (steal ledger).** Two profiles cannot be written atomically, so delivery is two confirmed steps:
  1. The weapon leaves the victim's backpack into `victim.outbox[id]` (with the thief's UserId), and the victim's save is confirmed. If that save fails while the victim is still here, the weapon goes back on its podium.
  2. The thief receives it, with the id recorded in `thief.xferIn` in the same profile. Once the thief's save is confirmed, the outbox entry is acknowledged. If the thief is not on this server, the delivery is queued into their saved profile with `ProfileStore:MessageAsync` and applied by a `MessageHandler` when they load.

  After any crash the weapon is in exactly one place: the victim's saved backpack, the victim's saved outbox, or the thief's saved backpack. Outboxes are re-delivered when the victim's profile loads and every 30 s while loaded. `xferIn` makes every re-delivery a no-op. This is a recoverable two-step transfer, not an atomic DataStore transaction.

## Stolen weapons keep their full value (owner decision)

A first version capped what a stolen weapon sold for at the thief's progression. The owner rejected that because it removes the reason to steal, so **stolen weapons sell and display for their full value**. They are marked `st` so the card shows "stolen from …", and they do not raise the "best weapon forged" stat.

`Economy.usableValue` still caps one case: **a weapon the player forged in a metal above their current one**, which in practice is a trophy kept through an evolution. It sells for what the same weapon would be worth in the player's best metal now, at their own evolution bonus. Its card keeps the full value, and the full value returns once the player reaches that metal again. This closes the "evolve, then sell every old trophy" shortcut (407 h to the final metal before the fix).

- **Display income:** unchanged rule. Every weapon, stolen or not, earns on its value capped at the current tier's best roll.
- **Weapon card:** shows the real income, plus "Sells for $X until you unlock <metal>" for capped trophies.
- **Sell booth:** the preview totals what the booth will really pay.

## Test evidence

| Check | Result |
|---|---|
| Lune suite (`tools/lune/run-tests.luau`) | **233 passed, 0 failed** (was 221) |
| Studio spec runner (`RunSpecs`) | **224 passed, 0 failed** |
| Two real Studio clients (`ExecuteMultiplayerTestAsync(2, {forgeFrenzyAcceptance = true})`, StudioPersistent isolated store) | **Passed, 15 checks, 51.4 s** (rerun after the owner decision) |

New Lune regression specs:

- **Hold table and monotonicity.**
- **Server-enforced 7.5 s hold:** a spoofed 2.5 s commit is refused.
- **Swap, replace or remove mid-hold:** nothing is stolen.
- **Hold cancellation:** letting go, walking off, dying and the owner locking each cancel the hold.
- **Teleport and speed-hop rejection:** lag-spike tolerance is tested too.
- **Lock reset on hand-over.**
- **Failed victim save restores the weapon.**
- **Crash at each transfer stage:** one durable copy, re-delivery ignored, the message path applies once.
- **Victim released mid-save:** the outbox is delivered once on rejoin.
- **Selling value:** stolen weapons sell in full; own trophies above the current metal are capped until it is reached again.
- **DataService message handler and `sendMessage`.**

The two real clients covered:

- isolated profiles and workshops;
- pads and upgrades;
- a timed manual forge;
- free Auto Forge;
- booth-only selling;
- display income;
- a 2.5 s value-based hold, a carry walked home and a durable delivery (victim save, thief save, outbox cleared);
- a teleport home rejected with the weapon back on its podium;
- a mid-hold swap cancelled;
- a tier-20 stolen weapon selling for its full $48.7B to a tier-3 thief;
- tag-back;
- the Forge Lock: lasers, eject, refusals and no reuse;
- forge, ore, upgrade, hatch and evolve refused from the hub, with Auto Forge kept running after walking away;
- an owner leaving mid-lock, with the lock and cooldown cleared for the next owner;
- the departure cleanup.

In a solo Play session, `ForgeConfigure` from the hub returned "Walk back to the station first" and succeeded at the forge. The forge panel opened with E, and no client errors were logged. Automated mouse clicks on the panel did not register in Studio, so the OFF / AUTO / PREMIUM switching was not clicked through. Its server path (`ForgeStop`, `ForgeBegin` replacing the loop) is covered by the specs above.

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

- **Undelivered outbox.** If a server crashes after the victim's save but before delivery, and the victim never plays again, the weapon waits in their saved outbox. It is never lost or duplicated, but the thief does not get it until the victim's profile loads.
- **Delayed message delivery.** A message to a thief who is on another server is applied on that server's next ProfileStore update cycle, not instantly.
- **Short hops.** The movement check allows about 40 studs of instant movement (lag tolerance) and 1.5× running speed. Neighbouring workshops are close, so the 2 s minimum carry and tagging remain the main counterplay there.
- **Hold release.** The server cannot see a key being released. A client that never sends `StealCancel` still has to stand at the podium and keep the pinned weapon unchanged for the full hold.
- **Station range.** It is lenient (26 studs) to avoid false refusals on lag and large models, and should be tuned with real players.
- **Stealing pays in full.** High-value steals can shortcut progression a lot when rich victims are around, and an alt account can steal from a main to skip the climb. The owner chose this deliberately.
- **Human checks.** Hold times for younger players, the "Sells for … until you unlock …" wording on old trophies, and the Auto mode buttons clicked by a person.
