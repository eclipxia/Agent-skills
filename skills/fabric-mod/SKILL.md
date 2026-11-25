---
name: fabric-mod
description: >-
  Build, extend, debug, or port client-side Minecraft mods for the Fabric mod
  loader using Fabric API first and mixins only as a last resort. Use whenever
  the user mentions Fabric, fabric.mod.json, Fabric Loom,
  ClientModInitializer, Fabric API, or wants a client-only Minecraft mod: HUD
  overlays, custom screens/GUIs, keybinds, client commands, rendering (world,
  block entity, entity renderers, particles), client networking, item/block
  assets, or datagen. Also use when they ask to add a mixin or access
  Minecraft internals from a Fabric mod, because this skill decides whether a
  mixin is really needed. Do not use for Forge/NeoForge, Paper/Bukkit plugins,
  or RusherHack plugins.
---

# Fabric client-side mod development

This skill helps you write client-side Fabric mods that lean on **Fabric API**
and the documented extension points, and treat mixins as the last resort. Fabric
API hooks are versioned, supported, and survive Minecraft updates far better
than bytecode patches. A mixin that works today is the most common thing to
break on the next Minecraft release, and mixins conflict with other mods.

The authoritative source is the Fabric developer docs:
<https://docs.fabricmc.net/develop/>. Fabric and Minecraft change fast (the docs
have a version selector, and rendering/input APIs shifted a lot in 26.x), so
treat the snippets in this skill's references as orientation, and confirm class
names and signatures against the docs page for the **project's exact Minecraft
version** before writing code. Memory of older versions is the main source of
wrong code here.

## Step 0: Identify the project before writing anything

1. Read `gradle.properties`, `build.gradle`,
   `src/main/resources/fabric.mod.json` (and `src/client/` if it exists).
   Establish:
   - **Minecraft version** and **Fabric API version**
   - **Loom plugin id**: `net.fabricmc.fabric-loom` means 26.1+ (unobfuscated,
     Mojang-style official names, Java 25); `net.fabricmc.fabric-loom-remap` or
     legacy `fabric-loom` means 1.21.11 or older (Yarn mappings, remapping, Java
     21 on 1.21.x).
   - **Source layout**: split `src/main` + `src/client`, or a single source set.
2. Pick the matching docs version in the docs site's selector and use that
   version's pages. Class names differ between Yarn (`Identifier.of`,
   `MinecraftClient`, `Text`) and Mojang-style names (`Identifier`, `Minecraft`,
   `Component`). Never mix the two in one project.
3. If the user is starting from nothing, send them to the template generator
   (<https://fabricmc.net/develop/template/>) instead of hand-writing the Gradle
   setup, and read `references/project-setup.md`.

Run `scripts/audit-client-mod.sh <project-dir>` any time to get a quick report
of project facts, mixin count, and client-class leakage into common code.

## The decision ladder (the core rule)

When the user wants behavior Fabric API doesn't obviously provide, walk down
this list and stop at the first rung that works. Say which rung you stopped at,
so the user can see why a mixin was or wasn't used.

1. **Fabric API feature**: an event, registry, or helper (HUD element registry,
   key mapping helper, client tick events, screen events, client commands,
   client networking, particle/renderer registries, item group events,
   tooltip/lifecycle events). Search `references/api-map.md` first.
2. **Data and assets, no code**: models, item definitions, blockstates, lang
   files, particle JSON, sounds.json, resource packs, tags, loot tables. Many "I
   need to change how X looks" requests end here.
3. **Vanilla public API used from your own code**: e.g. call
   `Minecraft.getInstance()` state from a tick event or HUD callback. Reading
   game state rarely needs a mixin.
4. **Class tweakers / access wideners** (docs: `class-tweakers/`) when the only
   problem is that something is private/final, or you need an interface
   injected. Cheaper and safer than a mixin.
5. **Accessor / invoker mixin** (docs: `mixins/accessors`): exposes a private
   field or method without changing behavior.
6. **Injection mixin** (`@Inject`, `@ModifyVariable`, `@WrapOperation`...),
   ideally one that **fires your own Fabric-style `Event`** so the mixin stays
   tiny and your mod logic lives outside it. Read
   `references/mixins-last-resort.md` first.
7. **`@Redirect` / `@Overwrite`**: avoid. They're the most conflict-prone;
   explain the risk to the user and pick a narrower injector if at all possible.

Once you reach rung 5 or 6, switch to the `fabric-mixin` skill for how to write
and debug it. Some things genuinely need a mixin even in current Fabric (e.g. in
26.3 the final draw call of a custom world-render pipeline is a documented mixin
because Fabric API doesn't expose the render pass). When that happens, follow
the docs' own mixin pattern and keep it small. Don't assume a mixin is needed,
check the docs page for the feature first, since new Fabric API versions
regularly replace old mixin-only workarounds.

## Client-only discipline

Dedicated servers don't contain rendering classes, so a stray client import in
common code crashes them at class-load time. This matters even for "client-only"
mods, since the mod jar might be installed server-side by mistake or tested in a
dev server.

- Put the `"client"` entrypoint in `fabric.mod.json` (`ClientModInitializer`)
  and register all renderers, screens, key mappings, HUD elements, particle
  providers, and client receivers there.
- Prefer split source sets (`src/client`) so the compiler enforces the boundary;
  if the project has one source set, keep client classes in a clearly named
  `client` package and never reference them from `ModInitializer`.
- For a purely client-side mod, set `"environment": "client"` in
  `fabric.mod.json` so the loader refuses to load it on a server, and declare
  client mixin configs with `{ "config": "...", "environment": "client" }`.
- Use the logical-side checks (`level.isClientSide()`) for gameplay logic, but
  remember they don't keep client classes out of the dedicated-server classpath.
  Only separation does.

## How to work

- **Reuse the project's conventions** (package names, mod id helper like
  `ExampleMod.id("x")`, how registration classes call an `initialize()` method).
- **Write assets alongside code.** An item/block/key binding is not done until
  its model, client item definition, texture reference, and `lang/en_us.json`
  entry exist. The checklists in `references/api-map.md` list them.
- **Build and run to verify**: `./gradlew build`, then `./gradlew runClient`. A
  green compile isn't proof a client feature works; mixin targets, missing
  assets, and registration order only fail at runtime. If you can't launch the
  game, say so and tell the user what to look for.
- **Prefer small, explainable diffs.** Explain which API you chose and why (one
  or two lines), especially when you rejected a mixin.
- **When docs and memory disagree, trust the docs** for the project's version.
  If you can't fetch the docs, say which parts of the code are from memory and
  may need adjusting.

## Where to look next

- "What API do I use for X?" (HUD, screens, keybinds, client commands,
  networking, particles, events, items, blocks, entities, datagen)
  - Read: `references/api-map.md`
- Rendering specifics: HUD, screens, widgets, world rendering, block entity and
  entity renderers, particles
  - Read: `references/rendering.md`
- New project, Gradle/Loom, `fabric.mod.json`, split sources, version bumps,
  porting 1.21.x → 26.x
  - Read: `references/project-setup.md`
- Considering a mixin, writing one, or reviewing one
  - Read: `references/mixins-last-resort.md`

Read only the file(s) the task needs.
