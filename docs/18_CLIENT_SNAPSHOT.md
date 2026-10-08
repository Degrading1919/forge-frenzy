# Client profile snapshot (Push "Profile")

**Status: IMPLEMENTATION CONTRACT.** The server (`src/server/Net`) sends this table to the owning client after any change (throttled ~4 Hz). The client never mutates it; it calls `Net.call(Protocol.Actions.X, ...)` instead (see `src/shared/Protocol.luau`).

```lua
{
  coins: number, lifetimeCoins: number, weaponsForged: number, highestWeaponValue: number,
  selectedMaterial: number,        -- 1..32
  unlockedTier: number,            -- highest extractor tier unlocked (materials 1..unlockedTier selectable)
  ore: { number },                 -- array of 32 raw ore counts
  ingots: { number },              -- array of 32 ingot counts (forging spends 1 ingot of the chosen material)
  levels: { [track]: number },     -- ExtractorOutput, SmelterSpeed, StorageCapacity, FurnaceHeat, AnvilFinish
  gear: { [track]: number },       -- Hammer, Gloves, Apron
  costs: { upgrades: { [track]: number | false }, unlockNext: number | false }, -- false = maxed
  weapons: { Weapon },             -- kept weapons (array)
  pending: Weapon?,                -- forged but not yet sold/kept
  showcase: { string },            -- 6 slots of weapon ids ("" = empty)
  journal: { number },             -- 32 rarity bitmasks (bit r-1 set = rarity r discovered for that material)
  pets: { { id: string, kind: string } },  -- kind = key in Shared.Config.Companions
  equipped: { string },            -- equipped pet ids
  petSlots: number,
  evolutionRank: number, forgedSinceEvolve: number, highestTierSinceEvolve: number,
  entitlements: { [productKey]: boolean },
  settings: { autoSellBelow: number, music: boolean, sfx: boolean, vfx: boolean },
  tutorial: number,                -- onboarding step reached (0 = new player)
  rates: { orePerSec: number, ingotPerSec: number, capacity: number, heatSec: number, windowSec: number, revealSec: number },
  autoMode: "off" | "free" | "premium",
  plotIndex: number,               -- Workspace.World.Plots["Plot" .. plotIndex]
  isStudio: boolean, productsLive: boolean, paidRandomAllowed: boolean,
}
```

`Weapon = { id, m (material index), c (class index 1..5), q (craftsmanship 1..5), r (rarity 1..6), d (design id), t (trait or nil), v (sale value), ts }`.

Names: classes Sword, Greatsword, Axe, Dagger, Hammer; craftsmanship Crude, Standard, Fine, Masterwork, Perfect; rarity Common, Uncommon, Rare, Epic, Legendary, Mythic. Display name: `"<Craftsmanship> <Trait?> <Material> <Class>"`, e.g. "Masterwork Frozen Iron Greatsword".

Players also carry attributes for other clients to render: `PlotIndex` (number) and `EquippedPets` (comma-separated companion kinds).

Shared config the client may read (owned by the logic threads, may land later; code defensively with `pcall(require, ...)` and fallbacks): `Shared.Config.Materials` (32 rows: id, name, index, era, priceMin, priceMax, unlockCost, color, material, accent, glow), `Shared.Config.Balance`, `Shared.Config.Companions` (kind → { name, rarity, bonus = { extract?, smelt?, prep?, storage? }, color, modelKind }), `Shared.Config.Eggs` (array of { id, name, cost, unlockTier?, kinds = { { kind, weight } } }), `Shared.Config.Products` (key → { name, kind: "pass"|"product", id, price?, description }, plus `LIVE`).
