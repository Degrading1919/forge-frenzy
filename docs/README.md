# Documentation map

Read the **current** documents first. Where they disagree with a historical one, the current one wins. Historical documents are kept as the record of how the game got here, and for the design intent they still carry.

## Current

### Implementation and architecture

| Document | What it covers |
|---|---|
| [16 Code layout and contracts](16_CODE_LAYOUT_AND_CONTRACTS.md) | Repo ↔ Studio mapping, service shape, sync |
| [18 Client snapshot](18_CLIENT_SNAPSHOT.md) | The server-owned profile snapshot clients render |
| [22 Remediation design](22_REMEDIATION_DESIGN.md) | The v2 design: station-local workshop, world contract, systems |

### Gameplay decisions

| Document | What it covers |
|---|---|
| [21 Owner playtest remediation](21_OWNER_PLAYTEST_REMEDIATION.md) | Highest-priority owner direction (UX, world, stealing and build-out, 500 h progression) |
| [25 Review remediation](25_REVIEW_REMEDIATION.md) | Stealing rules, steal ledger, station authority and the owner decisions below |

**Accepted owner decisions (October 2026):**

- Stolen weapons keep their full resale value, whatever the thief's progress.
- Steal hold time scales with weapon value, from 2 to 8 seconds (`src/shared/Steal.luau`).
- Ordinary free automated progression targets about 500 hours to the final metal. Stealing strategies may shortcut it.
- Weapons you forged in a metal above your current one sell like your best metal until you reach it again.
- Purchases and publishing stay disabled until the owner approves them.

### Economy and balance

| Document | What it covers |
|---|---|
| [23 Economy v2](23_ECONOMY_V2.md) | Generated curve, pacing simulation, how to rerun it |
| [25 Review remediation, economy section](25_REVIEW_REMEDIATION.md#economy-after-the-fixes-900-h-cap) | Results after the review fixes, stealing and evolve-then-sell strategies |

### Verification evidence

| Document | What it covers |
|---|---|
| [25 Review remediation](25_REVIEW_REMEDIATION.md#test-evidence) | Current test counts, real Studio multiplayer, real DataStore recovery, what still needs a human |
| [24 v2 verification](24_V2_VERIFICATION.md) | The original v2 evidence |

### Assets

| Document | What it covers |
|---|---|
| [15 Tripo asset manifest](15_TRIPO_ASSET_MANIFEST.md) and [`design/tripo-asset-manifest.json`](../design/tripo-asset-manifest.json) | Every planned externally generated 3D asset: priority, reuse, triangle budget, prompt |
| [08 Assets and tooling](08_ASSETS_AND_TOOLING.md) | Asset pipeline and reuse policy |

## Historical (design phase and v1)

These are kept for intent and history. Their numbers and mechanics are superseded wherever the current documents differ.

| Document | Superseded by |
|---|---|
| [01 Vision and core loop](01_VISION_AND_CORE_LOOP.md) | Still the pitch; mechanics in 21/22 |
| [02 Forging and RNG](02_FORGING_AND_RNG.md) | `ForgeMath`, `Config/Balance`, 22 |
| [03 Materials and production](03_MATERIALS_AND_PRODUCTION.md) | Ore lines and stations in 22; curve in 23 |
| [04 Workshop and gear](04_WORKSHOP_AND_GEAR.md) | Build pads and stations in 22 |
| [05 Companions and collection](05_COMPANIONS_AND_COLLECTION.md) | Pet merging in 22 |
| [06 Evolution and leaderboards](06_EVOLUTION_AND_LEADERBOARDS.md) | `Config/Evolution`, 22, 23 |
| [07 Monetization](07_MONETIZATION.md) | Still the policy; `MonetizationService` keeps purchases off |
| [09 Architecture and orchestration](09_ARCHITECTURE_AND_ORCHESTRATION.md) | 16; the multi-agent phase is over |
| [10 Build and acceptance](10_BUILD_AND_ACCEPTANCE.md) | Acceptance practice continues in 24/25 |
| [11 Decisions and open questions](11_DECISIONS_AND_OPEN_QUESTIONS.md) | 21, 25 |
| [12 Economy and balance](12_ECONOMY_AND_BALANCE.md), [13 Playtest balance v0](13_PLAYTEST_BALANCE_V0.md), [`design/balance-v0.json`](../design/balance-v0.json) | 23 |
| [14 Claude build mission](14_CLAUDE_BUILD_MISSION.md) | The original orchestration prompt |
| [17 Core economy implementation](17_CORE_ECONOMY_IMPLEMENTATION.md) | `src/shared/Economy.luau`, 22 |
| [19 1.0 playtest evidence](19_PLAYTEST_EVIDENCE.md), [20 Balance playtest](20_BALANCE_PLAYTEST.md) | 23, 24, 25 |

`artifacts/ForgeFrenzy-1.0-playtest.rbxm` (+ metadata) is the 1.0 service-container recovery snapshot, produced by `tools/export-playtest.luau` and `tools/assemble-playtest.py`. Keep it.
