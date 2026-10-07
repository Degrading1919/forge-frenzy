# Claude guidance — Forge Frenzy

You are working on **Forge Frenzy**, a Roblox incremental blacksmithing simulator. This repository is currently the source of truth for design; **do not assume any gameplay code, Roblox place or asset exists** until inspected.

## Project mission

Build a fun, complete, playable, visually polished *blacksmithing-first* incremental experience. Automatic machines supply selectable materials; players actively forge chosen weapon types through a click-speed/luck minigame; randomized quality/rarity/design/traits create valuable collectible weapons; money improves production/gear/pets; evolution and social leaderboards provide long-term goals. Scope must remain narrow with deep progression; do not turn this into a combat RPG or a large engineering framework.

Read [README.md](README.md), then [docs/01_VISION_AND_CORE_LOOP.md](docs/01_VISION_AND_CORE_LOOP.md) through [docs/12_ECONOMY_AND_BALANCE.md), especially [docs/11_DECISIONS_AND_OPEN_QUESTIONS.md](docs/11_DECISIONS_AND_OPEN_QUESTIONS.md). The last linked reference is [docs/12_ECONOMY_AND_BALANCE.md](docs/12_ECONOMY_AND_BALANCE.md).

## Autonomy and tasking

- User intends to use Claude Desktop projects/threads with an orchestrating agent, possibly for one long initiating development session. **Do not artificially stop at scaffolds, TODOs, plans, or milestones**; continue toward an integrated playable game when an execution environment and permission exist.
- Keep a compact mission prompt. Durable context belongs here and in the docs; do not re-read/restate everything every turn.
- **LOCKED** means an agreed direction. **PLANNED** means a desired feature with unapproved specifics. **PROPOSED** means tentative numbers/designs. **OPEN** means requires judgment, test, or owner decision. Honor locked direction; make reversible engineering decisions where possible. Escalate only real blockers, irreversible changes, and money/publication decisions.
- Optimize **accepted playable features per Claude usage**, not the number of agents/messages. Model routing is provisional: Opus-class high reasoning for design/integration/review; Sonnet-class for bounded production work; inexpensive search/explore agents for discovery. Check which models/effort options are actually available in the installed Claude product.
- Separate independent work across branches or isolated file sets. A **single integration owner** controls shared Studio instance / shared game hierarchy, Git integration and authoritative service contracts.
- Record implemented features and verification evidence. Never claim an unfinished system is complete.

## Reuse-first workflow

Before building common infrastructure, inspect official Roblox capabilities, Creator Store/DevForum, Wally/Pesde, and actively maintained/licensed GitHub components; see [docs/08_ASSETS_AND_TOOLING.md](docs/08_ASSETS_AND_TOOLING.md). Prefer narrowly fitting, secure, versioned libraries over reinventing data persistence, networking, testing or command utilities. Never import untrusted asset scripts blindly; audit and remove suspicious scripts.

Use Roblox Studio's supported **native MCP** for live scene editing/inspection, playtesting and visual screenshots, alongside reliable version-controlled source sync (e.g. Rojo where appropriate). Verify MCP/tool availability and configuration before promising automation. Source files and Studio hierarchy should not become divergent, competing sources of gameplay authority.

Tripo3D is available for distinctive meshes. Standard weapons share mesh models across **32 material skins**. Only Legendary/Mythic families require dedicated unique assets; premium machines/pets may justify exceptional meshes. New 3D assets require import, validation, performance/animation checks.

## Critical gameplay rules

1. Server owns RNG rolls, inventories, currency, purchases, rate validation, pet bonuses and rebirth.
2. Materials establish finished-weapon **min/max value potential**. Player picks weapon class and metal; RNG generates quality, rarity, variant and trait.
3. Click/tap speed affects **luck** rather than directly multiplying final sell price: common manual ~2.5x, rare best ~5x, free auto 1.5x, paid auto 4x. Actual odds and device-friendly thresholds still require design/test.
4. Premium must be powerful but nonessential: all 32 metal progression and all rarities attainable free. Check Roblox paid-random-item policy and regional eligibility for monetized luck/eggs.
5. Standard weapons share meshes across material skins. Legendary and Mythic use dedicated distinctive assets, with skin reuse allowed.
6. Production is automated to supply forging. Do **not** make early full auto-forging replace the core interaction.
7. Rebirth/evolution retains permanent collection/pet/entitlement progress; exact reset list is not yet finalized; paid protected evolutions must not allow immediate rebirth loops.
8. Physically visible leaderboard hall plus persistent global counters. Persist server-side accurately.

## Verification

Run deterministic economy/RNG tests, Luau type/lint checks, save/reload and multi-client playtests. Verify forged weapon values remain in the chosen material range; rate limit spoofed client clicks; receipts and evolution are idempotent; assets and UI work on mobile. Measure and inspect real screenshots/interaction, not just green unit tests. Do not perform live Robux transactions, publish a commercial experience, or incur paid Tripo generation without explicit authorization.

Read [docs/10_BUILD_AND_ACCEPTANCE.md](docs/10_BUILD_AND_ACCEPTANCE.md) before reporting completion.
