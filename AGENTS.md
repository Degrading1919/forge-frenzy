# Cross-agent project instructions

Repository: **Degrading1919/forge-frenzy**. Status at documentation bootstrap: design only. Read `README.md`, `CLAUDE.md` and relevant docs before tasking.

## Authority boundaries
- Game behavior: authoritative server services/config; clients only request actions and render.
- Durable implementation truth: checked-in repository, not chat memory; live Studio must be reconciled with source.
- Design authority: documented **LOCKED** requirements override individual speculative additions.
- Production owner approval: commercial publishing, real purchases and external paid-asset expenditure.
- Preserve game scope. No Adventurer's Rise code or architecture imported unless inspected, licensed/owned and demonstrably helpful.

## Agent responsibilities
- **Orchestrator:** read scope, prioritize vertical slice, partition bounded work, resolve interfaces, own integration and acceptance.
- **Code workers:** implement independently testable modules following agreed contracts; small files/commits, avoid overlapping edits.
- **Asset/Studio worker:** ensure visual implementation, import, optimize and test assets, with one writer controlling Studio at a time.
- **Independent reviewer:** test duplication exploits, cross-service state, bad chance math, performance, mobile and purchase policies.
- **Human:** aesthetic direction, game feel, actual playtesting and irreversible approvals.

## Reuse and efficiency
First search current official docs/registries/repositories for mature solutions. Verify licenses and dependency health. Avoid mixing multiple overlapping all-in-one frameworks; reuse primitives intentionally. Keep long-term instructions stable, minimize always-on MCPs, avoid wasteful subagent fanout, and record test evidence.

## Deliverable discipline
For every changed feature report: files/commit, game-visible behavior, acceptance test and playtest evidence, known limitations. Do not invent assets, repository paths, player metrics, proof of Studio validation or completion claims.
