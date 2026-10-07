# Assets, Studio plugins, open source and build tooling

## Visual/asset philosophy — LOCKED

Strong readable stylized models, exaggerated tiers, efficient reuse and striking Legendary/Mythic revelations. Shared **standard weapon meshes** are reskinned for all metal variants via texture, color, material properties, appearance effects and attachments; **dedicated models only for Legendary/Mythic weapon identities**, not every combination. Premium machines and companions may receive bespoke high-quality models.

Example **PROPOSED** weapon budget: Sword, Greatsword, Axe, Dagger, Hammer × 3 common-to-Epic designs = **15 reusable normal meshes**. Approximately **10** special Legendary/Mythic meshes is a candidate target. With 32 materials, 15 ordinary silhouettes imply **480 ordinary material × silhouette visual combinations** before quality/traits. These are combinatorial content variations, not 480 authored models.

## Art pipeline

- **Creator Store:** generic props, safe scenery, sound, particles and templates.
- **Roblox built-in generation:** quick blockout / simple generated meshes/materials if available through current Studio tools.
- **Tripo3D:** standout weapons, companions and machinery models where custom silhouette adds significant value.
- **Blender:** cleanup, topology/polycount, pivot and scale normalization, UV/material setup, rigging when necessary, collision proxy, and FBX/glTF/OBJ export as supported.
- **Studio:** import, apply final appearances, attach VFX, build reusable Prefabs/Model templates, inspect LOD/performance, test phone/controller/desktop.

For standard weapons, enforce compatible orientation, handles/attachment offsets, relative scale and metadata. VFX and colors should not obscure silhouettes. Avoid promising auto-rigging or production-ready geometry from raw text-to-3D.

## Known search locations — verify current maintenance/license at integration time

| Resource | URL | Purpose |
|---|---|---|
| Roblox Creator Store | https://create.roblox.com/store | Studio-ready models, plugins, audio, UI |
| DevForum Community Resources | https://devforum.roblox.com/c/resources/community-resources/74 | Roblox code/templates/community utilities |
| Roblox official Docs | https://create.roblox.com/docs | Current engine / policy references |
| Roblox templates | https://create.roblox.com/docs/resources/templates | Starter environments/systems |
| Wally | https://wally.run | Luau package registry |
| Pesde | https://pesde.dev | Alternative Luau package registry |
| GitHub Roblox topic | https://github.com/topics/roblox | Open-source libraries and projects |
| Official Roblox GitHub | https://github.com/Roblox | Official repositories and tooling |

## Candidate libraries (do not blindly install all)

- **ProfileStore:** https://github.com/MadStudioRoblox/ProfileStore — player persistence/session data.
- **Replica:** https://github.com/MadStudioRoblox/Replica — state replication.
- **RbxUtil (Comm, Trove, Signal etc.):** https://github.com/Sleitnick/RbxUtil — scoped networking/utilities.
- **Cmdr:** https://github.com/evaera/Cmdr — development/admin commands for balance QA.
- **Fusion:** https://github.com/FugLord77/Roblox-Fusion — reactive interface candidate.
- **React Luau:** https://github.com/Roblox/react-luau — alternative component interface candidate.
- **TestEZ:** https://github.com/Roblox/testez — unit/spec testing.
- **Rojo:** https://github.com/rojo-rbx/rojo — source sync with Studio.
- **Wally CLI:** https://github.com/UpliftGames/wally — dependency management.
- **Lune:** https://github.com/lune-org/lune — local Luau automation.
- **Selene / StyLua:** lint and format Luau; locate official distributions.

Choose **one** UI stack and minimize package overlap. Recheck whether a library is archived, breaking changes, licensing or API status; earlier evaluation flagged legacy Knit, ProfileService, ReplicaService and original Roact as superseded/archived candidates.

## Candidate Studio plugins (optional)

- Building Tools by F3X: https://create.roblox.com/store/asset/144950355
- Brushtool 2.1: https://create.roblox.com/store/asset/2268520847
- Archimedes: https://create.roblox.com/store/asset/144938633
- AutoScale Lite: https://create.roblox.com/store/asset/1496745047
- Moon Animator 2: https://create.roblox.com/store/asset/4725618216 (paid)
- ResizeAlign: https://create.roblox.com/store/asset/165534573
- GapFill & Extrude: https://create.roblox.com/store/asset/165687726
- RigEdit Lite: https://create.roblox.com/store/asset/1274343708

Use plugins **only if useful** after checking publisher/security/current compatibility; MCP code/Studio-native tools often supersede manual plugin operations. Creator Store models can contain dangerous scripts; inspect and remove untrusted script content, obfuscated imports and unexpected remotes.

## Workspace performance and handoff

Avoid uncontrolled parallel Roblox Studio/Blender/Tripo workloads. Share optimized art files and import notes rather than screenshots as source truth. Keep an asset inventory including origin, license, hash/ID, polycount where available, rig family, memory/performance observations and allowed variations. Decide later whether raw binary source assets belong in Git LFS or separate storage.

## Licensing safeguards

A public GitHub repo is **not** automatically licensed for reuse. Inspect each dependency's actual license, compatible attribution, publisher reputation, updates and security. Record third-party licenses before commercial use. For Creator Store assets, honor Roblox Creator Store terms and item permissions.
