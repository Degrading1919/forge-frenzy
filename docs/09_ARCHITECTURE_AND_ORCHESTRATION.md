# Technical architecture and Claude Desktop orchestration

## Delivery aim — LOCKED intent

Use **Claude Desktop Projects and threading** with a coordinating orchestrator to build a complete Roblox game as autonomously as available tooling allows in **one initiating development session**. This is the owner's intended operating style, **not a guarantee** that a single model context/window can finish publication-quality production. Continue through a vertical slice into a complete playable experience; do not deliberately stop after boilerplate or architecture documentation.

**Separation:** this project is Forge Frenzy, not Adventurer's Rise. Reuse engineering lessons and authorized components, but not old game behavior/scope.

## Model/harness routing — informed by owner lessons learned

Owner research: https://github.com/Degrading1919/lessons-learned
Particularly `cross-model/ROUTING_GUIDE.md`, `models/claude-code/README.md`, `research/harnesses/2026-09-24-token-and-window-efficiency.md`, `research/models/2026-10-04-new-model-release-update.md`.

Research is dated and model availability changes. The initial hypothesis:
- **Claude Opus 5.5 High:** lead decisions, difficult integration, code review, architecture.
- **Claude Sonnet 5.5 Medium/High:** scoped implementer and UI/iteration worker.
- **Claude Haiku 4.5 (or currently available efficient successor):** repository exploration, documentation retrieval and classifications.
- **Opus 4.8 High:** known-behavior fallback especially for Studio-MCP integration; lessons repo documents a strong Adventurer's Rise case.

Do not spend premium orchestration reasoning on deterministic formatting or routine config expansion. Avoid high-effort Max everywhere, uncontrolled parallelism and context/MCP bloat. Evaluate success by verified playable features, human corrections and usage.

## Environment and shared truth

**Roblox Studio native MCP:** preferred for game hierarchy inspection, object creation/editing, Creator Store asset search, insertion, script execution, screenshot inspection and live playtest where current Studio tools support it. Verify that the installed Studio and MCP expose the required functions; older standalone server may be archived.

**Git/GitHub + optionally Rojo:** durable code and content manifest, versioned configs, tests and reusable tooling. Have a plan for Studio assets that do not round-trip into text files. Never leave silently diverging code authored exclusively in Studio with a competing copy in the repository.

**One Studio integration writer** at a time; other workers operate in isolated source files/branches/tasks. Orchestrator resolves interface contracts before parallel work. Claude Project threads may not have automatic cross-thread conversation state; communicate through git commits, well-defined task cards/files and explicit reports, not presumed memory.

## Architecture guidelines — PLANNED

Keep implementation relatively small and data-driven:
- `Shared/Config`: materials (32), machine tiers, weapon families, rarities/traits, luck odds, companion definitions, monetization catalog, evolution targets.
- `Server`: profile persistence, authoritative economy/production, forge roll, owned weapon inventory, pet ownership/equip, purchases/entitlements, evolution, leaderboard aggregations.
- `Client`: forging minigame, world animations, rendering and responsive UI, animations/effects, local input handling, display of server-authoritative data.
- `Studio/World`: workshop plots, machines, anvil, models, egg station, collection displays, hub/leaderboards, visual effects and sound.
- `Tests`: deterministic random distribution checks, price bounds, transaction/persistence, remote validation, evolution and payments.

These are **responsibility boundaries**, not mandatory directory names or an invitation to create oversized abstraction layers. Do not create several conflicting economic authorities.

## Secure/integrated workflow

- Server computes currency balances, production over elapsed time, chosen metal eligibility, RNG, luck boundaries and receipt verification.
- Client provides intent and permissible click timing/events; server verifies forging windows, ownership, sane rate patterns, replay prevention and cooldowns.
- Keep random rolls and inventory settlement atomic or safely idempotent to prevent duplicate sales and duplication on retries/disconnect.
- Profile saving, economy handling, and evolution state must remain consistent under two players, server restarts and network lag.
- Remote payloads are constrained; never trust claimed client luck, chosen locked ores or companion-derived stats.
- Display/server-owned leaderboard data should update at efficient intervals.
- Mobile and controller UX are first-class; alternative free auto forging mitigates rapid-input accessibility concerns.

## Recommended autonomous build cycle

1. **Inspect actual environment**: empty/nonempty repo, installed Studio plugins/MCP, Roblox place, license availability; don't invent paths.
2. **Choose narrow vertical slice**: one material/extractor → forge click minigame → server roll → sell → upgrade → save/reload; playtest in Studio.
3. **Generalize via registries**: 32 materials, gear/machines, rarity/variants and value curves; avoid 32 bespoke systems.
4. **Layer features**: companions/eggs, premium entitlement stubs with safe tests, personal showcases, evolutions and leaderboards.
5. **Add visuals**: reusable base meshes, Tripo custom asset intake, effects, UI polish, hub layout.
6. **Integrate, verify, fix**: multi-client, mobile, economy progression, DataStore failure/rejoin and real Roblox Studio interactions. Review across systems.
7. **Document evidence**: commit IDs, what Studio tests ran, screenshots/known gaps and blockers. Owner signs off on gameplay feel and commercial launch.

Stages describe *work order*, not an excuse to stop and ask approval between every stage.

## Completion standard

A feature is not done because its script compiles. It must be connected to actual UI/world objects, playtestable, persist correctly if applicable, and be robust against its expected edge cases. All monetization surfaces must comply with current Roblox policies. Live publishing/financial actions remain owner-approved.
