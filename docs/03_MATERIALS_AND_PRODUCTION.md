# Materials, extraction and progression

## Structure — LOCKED

Plan for **32 launch materials** across eight candidate eras. The 32 names below were **proposed and agreed as the working target**, but names and order are editable during balancing. All standard weapon materials share weapon meshes; recolor/retexture/material/tint/effects rather than authoring separate weapon geometry per ore.

**Do not place 32 separate mines.** Players purchase progressively capable extractor tiers, unlocking ore selections, then set which unlocked ore that extractor produces. Machines may share models with upgraded skins/animations.

| Era | Candidate materials | Visual direction |
|---|---|---|
| 1 Basic Metals | Copper, Tin, Bronze, Iron | Warm/earthy base metals |
| 2 Refined Metals | Steel, Silver, Gold, Platinum | Clean, polished surfaces |
| 3 Industrial Metals | Cobalt, Titanium, Tungsten, Osmium | Dense, dark industrial |
| 4 Arcane Metals | Moonsteel, Mithril, Runite, Adamantite | Blue/green enchanted |
| 5 Elemental | Emberite, Frostsilver, Stormium, Obsidian | Flame, frost, storm, shadow |
| 6 Forbidden | Bloodiron, Soulsteel, Starsteel, Voidmetal | Crimson, spectral, cosmic |
| 7 Celestial | Sunmetal, Lunarite, Astralite, Etherium | Radiant gold, pearl, blue |
| 8 Ancient | Chronosteel, Nebulium, Aetherglass, Primordium | Strange ancient/otherworldly |

No claim about real-world metallurgy is implied by fantasy names.

## Per-material registry — PLANNED

Each material should specify stable identifier, display name, era/unlock tier, cost to forge (units), extractor output speed, smelting conversion rate (if applicable), storage footprint (if relevant), min/max finished-weapon selling value, appearance parameters and rarity-neutral flavor.

**Material rarity/availability is separate from weapon rarity.** A low-tier material can roll Mythic but has a low-tier price potential; advanced materials have much larger price potential. Higher tiers often take longer or more resource input so earlier choices remain economically relevant.

## Machine flow — PLANNED

Extractor generates ore → smelter converts ore to usable material → storage buffers it → personal forge spends material for an attempt. The player's main activity remains the forging interaction.

Main upgrades:
1. Extractor tier unlocks better materials and increases extraction output.
2. Smelter tier raises processing throughput and possibly yield.
3. Storage tier increases material/offline capacity.
4. Furnace/anvil/other forge upgrades improve forge processing efficiency, distinct from price bands.

Exact rates, conversion yields, machine quantities, world layout and queue behavior are **OPEN**. Do not invent dozens of factory conveyor mechanics without a game-feel rationale.

## Initial production policy — PROPOSED

- Automatic production starts very early so the player can concentrate on forging.
- One selected ore at a time per extractor to avoid unnecessary complexity.
- Switching ore must not produce duplicated/invalid resources.
- Material buffers have capacity caps, including limited offline accrual if implemented.
- A useful bottleneck (extraction versus refining) can create an understandable upgrade decision, but avoid excessive micro-management.
- Earlier material options should remain attractive for quick forging, quests/orders if added later, and completing the collection.
- Machines are purchased with earned currency from selling weapons. There is no Robux-only ore or forge rarity tier.

## Price example — ILLUSTRATIVE ONLY

Earlier discussion used approximate min/max bands for five of the dozens of ores: Iron $10–500, Steel $250–5,000, Mithril $2,500–50,000, Obsidian $25,000–500,000, Celestial $250,000–5,000,000. This was a **demonstration of scaling**, not the actual material order, named ore registry or approved economy. Note: “Celestial” in that example was a generic tier descriptor, not one of the 32 selected specific ore names. Build the final 32-material curve from scratch during balance work.

## Implementation/asset reuse

Model families: extractor, smelter, storage, furnace, anvil; upgrades change scale, tint, particles, attachments and modest meshes. Source config owns every machine/ore stat. Gameplay code should not hardcode separate scripts for all 32 ores. See [Workshop and gear](04_WORKSHOP_AND_GEAR.md).
