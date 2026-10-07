# Evolution, rebirth, persistence and leaderboards

## Evolution — PLANNED

Long-term rebirth/evolve mechanic, working label **Blacksmith Evolution / Reforging** (name not final). Normal evolution grants permanent workshop bonuses in exchange for resetting a defined subset of temporary progress.

**Planned permanent retention:** owned/displayed weapon collections, discovery records, companions, permanent unlocks, Robux entitlements and prior evolution rewards. **Reset candidates:** spendable cash, stored materials and nonpermanent production machine levels.

Specific reset/keep fields must be reconciled before coding to prevent contradictory state.

Earlier *illustrative* first evolution: 500 weapons forged and $1M lifetime sales, granting +50% production and +10% forge speed. **These numbers are not final.** Requirements should rise across evolutions.

Evolving should feel genuinely rewarding and restore previous speed quickly, rather than imposing a lengthy frustration wall.

## Paid protected evolution — PLANNED

A paid option preserves coins, stockpiles and/or machine levels that normal evolution would reset, while still awarding the evolution bonus. Exact protection scope, price, entitlement type and safeguards are **OPEN**.

**Anti-loop requirement:** qualifying for the next evolution cannot depend solely on retained currency/equipment. Track fresh production/progression since last evolution, increasing goals, or unique milestone flags, so paying once does not allow infinite immediate evolutions.

Do not delete permanent items or purchased advantages on any evolution path. Present a confirmation preview precisely listing items kept/reset. Run persistence tests for all three paths: no purchase, owned protection product, and interrupted evolution.

## Leaderboards — PLANNED for launch

Physical **Hall of Blacksmiths** boards near shared hub and useful server/player-list rankings.

Four proposed leaderboard metrics:
1. **Lifetime wealth generated** (earned from forging/sales, not current coins).
2. **Total weapons forged**.
3. **Total evolutions**.
4. **Highest sale/value for a single weapon forged**.

Provide global rankings and relevant current-server comparisons. Show player avatar/display identity, rank, amount and timestamps only as suitable. Handle moderation/name fallback and players with no records. Top values should survive server restarts.

Technical approach: ordered stores or currently supported Roblox leaderboard features; verify real limitations in official docs before choosing. Update at controlled intervals and use safe data-store budgets; never write global boards on each click.

## Saving and anti-exploits

Server-authoritative profile: currencies, ores, station levels, selected material, permanent inventory, equipped pets, unique weapon records, evolution state, entitlements, lifetime counters and personal-best record. Durable transactions should not duplicate weapons or pay sales twice after disconnect/retry. Do not rely exclusively on clients for purchases, rolls, click rates, pet bonuses or leaderboard claims.

Evolution transaction must be effectively atomic/idempotent. If a player disconnects during it, the game must restore a consistent completed-or-not-completed state.

Avoid costly scanning of the full weapon collection for leaderboard updates; maintain derived aggregate stats safely.
