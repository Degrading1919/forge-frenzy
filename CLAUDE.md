# Claude guidance — Forge Frenzy

You are working on **Forge Frenzy**, a playable Roblox incremental blacksmithing game. **`main` is the authoritative branch.** Branch from it for new work and merge back through PRs. Continue the existing architecture and game rather than rebuilding it.

Source is the durable implementation truth. The live Studio place is synchronized from source with `tools/devsync.py` and `ServerStorage.Build.DevSync`. Inspect and back up live Studio content before replacing objects, and never run `WorldBuilder.build()` blindly; it backs the World up to `ServerStorage.Backups`, but the hand-placed world is the authority.

**Status:** v2, ready for owner playtests, with purchases and publishing disabled.

Start with [README.md](README.md) and [docs/README.md](docs/README.md), which separates current documents from historical ones. The current direction is in:

- [docs/21](docs/21_OWNER_PLAYTEST_REMEDIATION.md): owner direction;
- [docs/22](docs/22_REMEDIATION_DESIGN.md): design and world contract;
- [docs/23](docs/23_ECONOMY_V2.md): the economy curve;
- [docs/25](docs/25_REVIEW_REMEDIATION.md): the stealing rules, steal ledger, station authority, current verification and remaining human checks.

## Accepted owner decisions (do not reopen)

- Stolen weapons keep their **full resale value**, whatever the thief's progress.
- Steal hold time follows weapon value: **2–8 s** on the shared log curve in `src/shared/Steal.luau`, enforced by the server.
- About **500 hours** of ordinary free automated progression reach the final metal. Stealing strategies may shortcut it.
- Weapons you forged above your current metal sell like your best metal until you reach it again. This stops the evolve-then-sell shortcut.
- Keep workshop expansion, stealing, Forge Lock, passive display income and the monetization safeguards.
- No real purchases, no publishing and no paid asset generation without the owner's explicit approval.

## Project mission

Build a fun, complete, playable, visually polished *blacksmithing-first* incremental experience. Automatic machines supply selectable materials; players actively forge chosen weapon types through a click-speed/luck minigame; randomized quality/rarity/design/traits create valuable collectible weapons; money improves production/gear/pets; evolution and social leaderboards provide long-term goals. Scope must remain narrow with deep progression; do not turn this into a combat RPG or a large engineering framework.

## Autonomy and tasking

- **Do not artificially stop at scaffolds, TODOs, plans, or milestones.** Carry work through to an integrated, verified change when an execution environment and permission exist.
- Keep a compact mission prompt. Durable context belongs here and in the docs; do not re-read/restate everything every turn.
- **LOCKED** means an agreed direction. **PLANNED** means a desired feature with unapproved specifics. **PROPOSED** means tentative numbers/designs. **OPEN** means requires judgment, test, or owner decision. Honor locked direction; make reversible engineering decisions where possible. Escalate only real blockers, irreversible changes, and money/publication decisions.
- Optimize **accepted playable features per Claude usage**, not the number of agents/messages. Model routing is provisional: Opus-class high reasoning for design/integration/review; Sonnet-class for bounded production work; inexpensive search/explore agents for discovery. Check which models/effort options are actually available in the installed Claude product.
- One integration owner controls the shared Studio place and merges into `main`. Keep feature branches short-lived and delete them after merging.
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

Run `lune run tools/lune/run-tests.luau`; a CI workflow is ready at `tools/ci/lune.yml`. For Studio work, also run `RunSpecs`, `TestPersistence`, `TestStealRecovery` and the two-client acceptance; the commands are in README. Check save/reload and multi-client behavior. Verify forged weapon values remain in the chosen material range; rate limit spoofed client clicks; receipts and evolution are idempotent; assets and UI work on mobile. Measure and inspect real screenshots/interaction, not just green unit tests. Do not perform live Robux transactions, publish a commercial experience, or incur paid Tripo generation without explicit authorization.

Record evidence the way [docs/25](docs/25_REVIEW_REMEDIATION.md) does. Separate what was verified in real Studio, what was mocked or simulated, and what still needs a human.
