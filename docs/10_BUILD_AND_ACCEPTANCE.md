# Build acceptance criteria and scope

## Target

A playable Roblox game with an obviously satisfying forging core, data-driven production, strong collectible reveal moments, long-term progression, and monetization systems that do not compromise free progression. Current repo at this document's creation holds *design only*; completion must be established through implementation and tests.

## MVP vertical slice — must work before broad content

1. Player joins a compact workshop and sees usable furnace/anvil/extractor.
2. Server chooses/unlocks default ore and awards production reliably.
3. Player selects an allowed weapon type + sufficient available material.
4. Timed click/tap forging works with visual/audio strike feedback, sane input validation and resulting **bounded 1–5x luck**.
5. Server rolls quality/rarity/variant/trait, creates owned persistent weapon and value **inside chosen metal's min/max range**.
6. Player sells weapon exactly once or keeps it and sees it in inventory/showcase.
7. Player buys an upgrade, sees rate/time/visual change, and enjoys faster forging/progress.
8. Save/rejoin restores balances, ore, collection and upgrades.

## Complete playable version — planned target

- All 32 candidate metal configs and extractor-selection/unlock path.
- Production: mine, smelter, storage, furnace/anvil; optional quench system if justified.
- Personal blacksmith gear progression (hammer, gloves, apron).
- 5 candidate weapon classes; reusable standard meshes with ore skins; distinct Legendary/Mythic visuals.
- Craftsmanship/rarity/design/trait roll system and compelling reveal.
- Forge Companions, a small egg system, equip bonuses, free/paid multi-hatch paths as allowed.
- Free 1.5x and premium 4x auto forge, balanced manual performance ~2.5x typical, max 5x; safe paid feature gating/disclosure.
- Personal masterpiece showcase and server social hub.
- Evolution / rebirth and optional protected evolution path without loop exploit.
- Four global/physical leaderboard concepts and useful live-server rankings.
- VIP/premium machinery and product entitlements, with working free equivalents and reliable receipts.
- Responsive desktop/mobile UI and reasonable controller input path.
- Performance-tested shared server with multiple players.

These are **planned content goals**, not claims any part is already complete or mandatory to rush at quality's expense.

## Tests that should fail if a defect exists

- All 32 material price ranges valid; roll values never escape chosen material bounds.
- Locked ore cannot be selected or produced through client remotes.
- Forging cannot go negative material, double-pay, double-grant, or apply rolled luck from client.
- Click spam/replay events outside window do not change server outcome beyond cap.
- Free auto yields capped 1.5x, premium auto capped 4x, max valid manual capped 5x; products do not unlock 6x.
- Rarity distribution statistically plausible across seeded simulations; no unreachable or inadvertently guaranteed high tier.
- Disconnected/retried forge, sale, hatching, and evolution produce consistent transactional outcomes.
- Pet equip count and bonuses enforced on server; protected evolve only for eligible paid purchases.
- Rebirth keeps pets/permanent gallery/purchases and resets precisely the declared temporary fields.
- Payment receipt idempotency and region-policy restrictions/odds disclosures validated.
- Server leaderboards show authoritative counters and remain durable after restart.
- A user can achieve multiple unlocks as a free account in a representative play session.
- UI hit targets and effects work on typical phone layouts; forge isn't solely usable with mouse.

## Performance/quality

Measure instance counts, duplicated materials/textures, particle load, script cost, DataStore budget and asset loading. Simulate several player plots and simultaneous forging. Check muted audio/limited VFX modes. Have a path for incomplete Tripo meshes: fall back to simple visually coherent placeholder rather than blocking the working game.

## Definition of done for the orchestrator

Evidence, not declarations: commits, scripts/classes present, place hierarchy integrated, reproducible Studio playtests, actual checks run/passed/failed, screenshots or owner-accessible observations and clearly disclosed omissions. Human acceptance and Roblox policy review before commercial launch.
