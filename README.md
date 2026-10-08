# Forge Frenzy

**Status: 1.0 build ready for the owner's full playtest. Purchases and publishing disabled.**

**Last consolidated: October 7, 2026.**  
**Project:** Roblox incremental blacksmithing game, separate from Adventurer's Rise.

The existing implementation is on `studio-integration` ([PR #5](https://github.com/Degrading1919/forge-frenzy/pull/5)); `main` retains the original design documentation. The open Studio experience is synchronized: press Play for the free-player loop and use Shop test grants to exercise premium features without Robux. See [playtest evidence and guide](docs/19_PLAYTEST_EVIDENCE.md), [balance evidence](docs/20_BALANCE_PLAYTEST.md), and the [recoverable service-container model](artifacts/ForgeFrenzy-1.0-playtest.rbxm). Preserve this implementation and existing Studio content when continuing work.

## Pitch

Build a blacksmithing empire without turning the game into a sprawling RPG. Workshop machines automatically extract and refine a **player-selected, unlocked material**. The player personally forges weapons using a short clicking minigame, chooses the **weapon class and material**, then reveals randomized craftsmanship, rarity, design and traits. The material sets the **potential sale-price range**. Sell weapons to improve workshop output, keep rare masterpieces to show off, hatch and equip Forge Companions, evolve for long-term bonuses, and compete on physical leaderboards.

**Guiding idea:** one fun action; several ways to do it faster/better; enormous vertical progression; visible social status. Robux purchases should feel powerful without being required to play, unlock any material, or obtain Mythic weapons.

## Source of truth

| Document | Scope |
|---|---|
| [Vision and core loop](docs/01_VISION_AND_CORE_LOOP.md) | Audience, loop, scope, social experience |
| [Forging and RNG](docs/02_FORGING_AND_RNG.md) | Player choices, hammering/luck, rolls and weapon value |
| [Materials and production](docs/03_MATERIALS_AND_PRODUCTION.md) | 32 materials, one selected output, machine economy |
| [Workshop and personal gear](docs/04_WORKSHOP_AND_GEAR.md) | Machine upgrades, hammers, gloves and aprons |
| [Companions and collections](docs/05_COMPANIONS_AND_COLLECTION.md) | Pets/eggs, equipped bonuses, showcasing weapons |
| [Evolution and leaderboards](docs/06_EVOLUTION_AND_LEADERBOARDS.md) | Rebirth, persistence, rankings |
| [Monetization](docs/07_MONETIZATION.md) | Paid convenience/boosts, free access, platform safeguards |
| [Assets and reuse](docs/08_ASSETS_AND_TOOLING.md) | Tripo3D, plugins, open source, asset reuse |
| [Technical and orchestration](docs/09_ARCHITECTURE_AND_ORCHESTRATION.md) | Claude Desktop, Roblox Studio MCP, source/authority |
| [Build acceptance](docs/10_BUILD_AND_ACCEPTANCE.md) | Scope, tests, playtest and completion definition |
| [Decision log and open questions](docs/11_DECISIONS_AND_OPEN_QUESTIONS.md) | Locked versus proposed versus untested |
| [Economy and balance planning](docs/12_ECONOMY_AND_BALANCE.md) | Curve constraints, payout math, tuning milestones |
| [Prototype balance v0](docs/13_PLAYTEST_BALANCE_V0.md) | Concrete 32-material cost curve, forge odds, machine rates and evolution defaults |
| [Claude Desktop build mission](docs/14_CLAUDE_BUILD_MISSION.md) | Ready-to-paste autonomous orchestrator prompt |
| [Tripo asset manifest](docs/15_TRIPO_ASSET_MANIFEST.md) | Every externally generated 3D asset: priority, reuse, triangle budget and Tripo prompt ([JSON](design/tripo-asset-manifest.json)) |
| [Machine-readable v0 balance](design/balance-v0.json) | Prototype configurations and explicit material prices |
| [Code layout and contracts](docs/16_CODE_LAYOUT_AND_CONTRACTS.md) | Source/Studio mapping and service interfaces |
| [Core economy implementation](docs/17_CORE_ECONOMY_IMPLEMENTATION.md) | Economy and forging API notes from the initial implementation |
| [Client snapshot](docs/18_CLIENT_SNAPSHOT.md) | Server-owned profile replication contract |
| [Playtest evidence](docs/19_PLAYTEST_EVIDENCE.md) | Current implementation, Studio verification, rerun commands and remaining acceptance |
| [Progression simulation](docs/20_BALANCE_PLAYTEST.md) | Free-player pacing through 32 tiers; model assumptions and human balance checks |

Agents should read [CLAUDE.md](CLAUDE.md) and [AGENTS.md](AGENTS.md).

## Status vocabulary

- **LOCKED:** Explicitly selected or affirmed in design conversation.
- **PLANNED:** Desired feature/category agreed in principle; mechanics or numbers not yet final.
- **PROPOSED:** Suggested implementation/quantity for playtesting; not a user-approved final balance value.
- **OPEN:** Requires decision or validation.
- **IMPLEMENTED:** Only when code, Studio assets and verification actually exist.

Do not treat numbers, prices, odds, item names, art examples or a proposed feature as already implemented. They remain candidates until tested and accepted.
