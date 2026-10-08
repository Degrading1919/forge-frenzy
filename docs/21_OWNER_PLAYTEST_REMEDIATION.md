# Owner Playtest Remediation Brief

**Date:** October 7, 2026  
**Authority:** Owner playtest findings. This document supersedes earlier design assumptions wherever they conflict.  
**Status:** REQUIRED REMEDIATION before the next owner playtest.

The current build is technically functional, but the owner playtest found that the experience still feels like a developer-facing simulator UI rather than a polished Roblox game for younger players. The next pass should preserve proven backend authority/persistence logic where useful, while substantially redesigning the player-facing UI, world interaction model, social loop, progression pacing, and economy.

The target experience should be simple enough that an eight-year-old can understand it with minimal reading. It should be bright, flashy, high-energy, tactile, and spatially interactive rather than a collection of remote-management menus.

---

## 1. Core UX direction

Forge Frenzy should be a physical workshop game. Players should walk to stations and interact with them instead of managing the forge from global menus.

Required changes:

- Remove Materials and Workshop from the persistent left-side UI.
- Remove the persistent bottom Forge button.
- Material selection/unlocking should happen at the ore/extractor station.
- Workshop upgrades should happen at the relevant machine or build pad.
- Forging should happen at the forge/anvil station.
- Selling should happen at a central booth in the hub.
- Pet purchase/hatching should happen at the hatch station.
- Evolution should happen at the evolution station.
- The player should physically move through the loop rather than operate the workshop from afar.
- Make every interaction answer: what can I do, what does it cost, what do I get, and what should I do next?

---

## 2. Full UI redesign

The existing UI reads too much like AI-generated productivity software and not enough like a Roblox simulator. It is too restrained, text-heavy, horizontal, and desktop-oriented.

New direction:

- large chunky buttons;
- saturated colors;
- bold outlines;
- strong glows;
- animated highlights;
- obvious rarity colors;
- celebratory reward reveals;
- very short labels;
- centered modals;
- mobile-first layout;
- large touch targets;
- strong visual hierarchy;
- readable large-number abbreviations such as K, M, B, T and beyond.

Use high-energy arcade/casino-inspired salience, anticipation, sound and celebration without deceptive purchase UX or unsafe rapid strobing.

Known defects to fix:

- left-side buttons clipped off the screen;
- forge buttons clipped;
- buttons generally sized incorrectly;
- Auto Forge UI overlaps tutorial text;
- currency badly positioned;
- pet reveal popup poorly positioned;
- evolution page overly verbose;
- UI feels optimized for computers rather than players.

Currency must be centered in its HUD element, and every coin/currency value should display a dollar sign, including shops, material unlocks, sale values, build pads, eggs, evolution requirements, and money leaderboards.

---

## 3. Forge flow redesign

The forge UI should become a simple vertical setup flow:

1. Choose Material
2. Choose Weapon Type
3. Automatically show Forge Odds
4. Auto Forge options
5. Auto Sell options when Auto Forge is enabled
6. Large BEGIN button

The minigame should not begin merely because a setting was selected. The player configures the forge, then presses BEGIN.

Auto Forge requirements:

- switching material, weapon type or mode should automatically stop the current auto-forge cycle cleanly;
- do not respond with "forge busy" when the player is trying to change configuration;
- every auto mode must have an obvious stop control;
- replace the unexplained progress bar with a labeled countdown/time tracker;
- Auto Sell should not be hidden in Settings; put it directly in Auto Forge setup;
- preserve the existing 1.5x free auto, 4x premium auto and 5x manual maximum unless changed later.

Forge odds should only appear in relevant forge contexts. They should not appear in unrelated surfaces such as Multi-Hatch/store purchase UI.

Hovering weapon previews above the anvil should be lowered to sit just above the anvil itself.

---

## 4. Weapon recipe costs

Weapon classes should require different ingot amounts based primarily on physical size.

Initial ordering:

- Dagger: cheapest
- Sword: low-medium
- Axe: medium
- Hammer: medium-high
- Greatsword: highest

Do not leave every weapon at one ingot. Rebalance output value and forging economics so larger recipes justify their higher material cost without creating one obviously dominant class.

---

## 5. Materials UI and terminology

Current circle/rank indicators on materials are confusing and largely meaningless.

Required:

- remove meaningless circle/rank indicators;
- each material tile should be clickable;
- locked materials should show their purchase price directly;
- clicking a purchasable locked material should purchase/unlock it;
- clearly show unmet requirements;
- make the selected material visually obvious;
- "Unlock Next" should not be the only material progression action;
- remove or rename the "Rank" label on Steel unless it represents an actual player-facing mechanic.

---

## 6. Economy and progression overhaul

Current values feel too small and progression is far too short.

Owner observations:

- Iron, the highest Basic Metal, should not be able to produce weapons worth only about $68.
- The rarest material should be worth far more than approximately $94.3B.
- Bigger numbers are desirable in this simulator and large-number abbreviations are acceptable.

**New major pacing target:** reaching the final material should take approximately **500 hours of automated free gameplay without purchases**.

This supersedes the current several-hour curve.

Do not merely multiply every value by one constant. Rebuild the progression curve coherently across:

- material sell-value ranges;
- material unlock prices;
- extraction rates;
- smelting rates;
- storage;
- weapon-size ingot requirements;
- machine upgrade costs/effects;
- evolution bonuses;
- Auto Forge;
- offline progression;
- premium acceleration.

The first session should be much faster and more rewarding than it is now, while the curve stretches increasingly aggressively later. Early progression should hook the player quickly; final-material progression should be a long-term objective.

Simulate realistic free Auto Forge progression and verify the approximate 500-hour target.

---

## 7. Production machines and workshop visuals

The smelter and furnace currently feel redundant because they expose effectively the same shop logic. Simplify their responsibilities.

The physical production chain should read visually as:

**Ore Station / Conveyor -> Smelter -> Output Conveyor -> Storage -> Forge**

Required:

- raise the ore conveyor so ore appears to drop into the smelter;
- add a conveyor from the smelter into storage;
- storage must not look like a bookcase;
- redesign storage as an industrial/fantasy bin, vault, hopper, crate system, or similar;
- visible ore/material motion should communicate production;
- upgrade descriptions must clearly state the actual effect, e.g. "+20% Ore Speed", "+10 Storage", "-0.5 sec Heat";
- show current -> next values where practical.

---

## 8. Physical build-out progression

Add purchase/build pads the player can run over or interact with to physically expand the workshop.

Direction:

- player begins with a smaller forge;
- build pads add machinery and functionality;
- purchases should visibly construct/reveal new objects;
- progression should eventually allow multiple forges and multiple ore/production stations;
- the workshop should physically transform as the player advances.

This adds a familiar Roblox tycoon/buildout loop while keeping forging as the core identity.

---

## 9. New social mechanic: stealing displayed swords

**This supersedes earlier "no stealing at launch" assumptions.**

Players should be able to steal displayed weapons from other players' podiums.

Displayed weapons should therefore also generate passive income for their owner. Higher-value weapons should generally generate more passive income, creating a visible risk/reward decision.

Design stealing so it is playful and recoverable rather than permanently devastating.

The system must define and test:

- ownership transfer;
- passive income;
- display state;
- persistence;
- disconnects;
- exploit protection;
- stealing interaction time/rules;
- onboarding;
- multiplayer behavior.

---

## 10. Lock Forge protection

Add a **LOCK FORGE** interaction.

Expected behavior:

- blocks other players from entering the protected forge/display area;
- activates obvious laser barriers;
- lasts 30 seconds;
- clearly shows remaining lock time;
- communicates why entry is blocked.

Determine an appropriate cooldown or reuse rule through playtesting.

Stealing, passive display income and forge locking should be designed as one coherent social loop.

---

## 11. Selling

Ordinary manual selling should happen at a physical central sell booth/merchant in the hub rather than from anywhere.

Auto Forge/Auto Sell may remain an automation exception.

The central booth should create movement and player concentration in the hub.

---

## 12. Pets

Add pet merging/upgrading.

Players should be able to combine duplicate/lower-level pets into a stronger version. Keep this system simple.

Define:

- merge requirement;
- upgraded tier/star/level;
- stat increase;
- max level;
- visual feedback;
- handling of premium pets.

Pet purchase/reveal UI should be redesigned:

- popup centered on screen;
- pet model/name/rarity immediately readable;
- large AWESOME button directly beneath the result;
- Multi-Hatch remains readable and celebratory.

---

## 13. Map and movement

The map is far too large and contains excessive empty travel space.

Required:

- substantially shrink/recompose the playable area;
- keep workshops near the hub to encourage social interaction and stealing;
- add a reasonably placed invisible perimeter barrier;
- players should not be able to walk into empty space for minutes;
- increase player walk speed;
- make the world feel dense and active.

Forge-owner signs currently face the wrong direction. They should face the shared central area so approaching players can read them.

---

## 14. Tutorial / onboarding

The start of the game feels too slow.

Required:

- get the player forging and receiving rewards sooner;
- reduce explanation text;
- teach one concept at a time;
- use world arrows, highlights or pulses when useful;
- prevent UI from overlapping tutorial instructions;
- immediately establish a rewarding forge -> sell -> upgrade loop.

The opening minutes should be significantly more exciting than the current build.

---

## 15. Evolution

The evolution page is too verbose.

Redesign it around:

- large current evolution level;
- concise requirement progress;
- clear permanent reward;
- short KEEP / RESET summary;
- one obvious Evolve button;
- protected evolution option only where relevant.

Observed issue: evolving does not remove swords currently on display.

Resolve this intentionally. If weapons themselves are permanent, decide whether normal evolution should clear display slots while preserving owned weapons or intentionally leave displays populated. Current behavior must not remain accidental or ambiguous.

---

## 16. Visual benchmark research

Before redesigning the interface, inspect current popular Roblox simulator/tycoon experiences and extract reusable design patterns for:

- button size and hierarchy;
- mobile layout;
- saturated color use;
- rarity presentation;
- reward reveals;
- upgrade shops;
- build pads;
- pet hatch UI;
- tycoon purchase feedback;
- onboarding;
- navigation density;
- stealing/protection loops.

Do not copy proprietary artwork or exact layouts. Apply the design principles.

The objective is a loud, highly legible, high-energy Roblox simulator aesthetic that appeals to younger players and provides constant visual/audio feedback.

---

## 17. Explicit defects and changes to verify

The next remediation pass must address all of these:

- left-side UI clipping;
- forge UI clipping;
- poor button sizing;
- remove persistent Forge button;
- remove Materials and Workshop from global left UI;
- vertical simplified forge menu;
- labeled Auto Forge timer;
- Auto Sell moved into Auto Forge setup;
- configuration changes stop auto mode instead of "forge busy";
- centered currency;
- dollar sign on all currency;
- direct material purchase;
- remove confusing material circles/rank;
- unclear Steel "Rank";
- lower weapon previews over anvil;
- clearer upgrade effects;
- storage no longer resembles bookcase;
- simplify furnace/smelter roles;
- fix conveyor flow;
- Auto Forge no longer covers tutorial;
- faster early game;
- faster walk speed;
- forge sign faces hub;
- compact map and invisible boundary;
- centered pet popup and button;
- simplified evolution UI;
- resolve evolution/display behavior;
- forge odds removed from irrelevant store/hatch UI;
- weapon-size recipe costs;
- 500-hour final-material progression target;
- pet merging;
- build pads / multiple stations;
- passive display income;
- sword stealing;
- 30-second laser forge lock;
- central sell booth.

---

## 18. Acceptance standard for next owner playtest

The next version should be visibly and behaviorally different, not merely backed by more automated tests.

Owner should observe:

1. compact, colorful, energetic world;
2. faster movement and clear world boundaries;
3. station-local interactions rather than remote management;
4. fully redesigned vertical forge flow;
5. no clipped buttons on desktop or mobile;
6. consistent dollar currency formatting;
7. weapon-size-dependent ingot requirements;
8. clear conveyor -> smelter -> storage production flow;
9. direct material purchases;
10. labeled Auto Forge timing and nearby Auto Sell controls;
11. a faster, more rewarding opening session;
12. physical build pads and workshop expansion;
13. passive-income display weapons and stealing;
14. functional 30-second laser protection;
15. physical central selling booth;
16. pet merging and improved pet reveal;
17. simplified evolution;
18. coherent economy simulation targeting roughly 500 free automated hours to final material;
19. persistence/multiplayer tests for stealing, locking, build-out and evolution;
20. real mobile/layout verification.

Automated tests remain necessary, but owner playtesting is the acceptance gate.
