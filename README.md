# Forge Frenzy

**Status: preproduction / documented design, not implemented.**  
**Last consolidated: October 7, 2026.**  
**Project:** Roblox incremental blacksmithing game, separate from Adventurer's Rise.

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

Agents should read [CLAUDE.md](CLAUDE.md) and [AGENTS.md](AGENTS.md).

## Status vocabulary

- **LOCKED:** Explicitly selected or affirmed in design conversation.
- **PLANNED:** Desired feature/category agreed in principle; mechanics or numbers not yet final.
- **PROPOSED:** Suggested implementation/quantity for playtesting; not a user-approved final balance value.
- **OPEN:** Requires decision or validation.
- **IMPLEMENTED:** Only when code, Studio assets and verification actually exist.

Do not treat numbers, prices, odds, item names, art examples or a proposed feature as already implemented. They remain candidates until tested and accepted.
