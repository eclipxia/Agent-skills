---
name: minecraft-utility-mod
description: >-
  Build and extend a client-side Minecraft utility mod (a "utility client")
  on Fabric in the style of the Magnum / manateehack project: toggleable
  modules with settings, an event bus, a Click GUI, HUD elements, chat
  commands, saved configs and a changelog. Use whenever the user wants to add
  a module, setting, HUD element, command, event, or config feature to a
  utility mod, start a new one, or asks how the Magnum codebase is organized,
  even if they just say "add a feature to my mod" or "make a module that...".
  Works together with the fabric-mod skill (Fabric API first) and the
  fabric-mixin skill (the hooks that feed the event bus). Not for server
  plugins, Forge/NeoForge, or RusherHack plugins.
---

# Minecraft utility mod (Magnum style)

A utility mod is a client-side Fabric mod made of many small, independently
toggleable **modules**. The reference implementation is the user's project at
`~/git/magnum` (GitHub `qe7/Magnum`, mod id `mhack`, package `me.shae`,
Minecraft 26.3, Java 25, Mojang names, Lombok). When it is available locally,
read the closest existing module before writing a new one, and copy its
conventions instead of inventing new ones.

This skill is about **structure**: how a feature plugs into the framework so
it appears in the GUI, saves in configs, gets a settings command, and cleans up
after itself. For how to hook into Minecraft, use the other skills:

- `fabric-mod`: Fabric API first, client-only discipline, the mixin ladder.
- `fabric-mixin`: writing the mixin when no API hook exists.

## The shape of the framework

Everything hangs off one class, `Mhack`, holding static singletons: the event
manager, `MODULE_MANAGER`, `COMMAND_MANAGER`, `CONFIG_MANAGER`,
`HUD_MANAGER`, restriction/relation/waypoint managers, and shared
"components" (rotation, actions, trackers). Read
`references/architecture.md` for the full map. The ideas that matter:

1. **Modules** extend `AbstractModule(name, category)`. Enabling a module
   calls `onEnable()`; disabling calls `onDisable()`. A module is a `Handler`,
   and its event listeners only fire while it is enabled and not locked.
2. **Events** are small records/classes implementing `Event`. A listener is a
   field annotated `@Subscriber` of type `Listener<SomeEvent>`. The event
   manager finds these by reflection when the module is registered.
3. **Mixins only post events or call small static hooks.** Game classes are
   patched once (`GameTickEvent` from `Minecraft.runTick`, `PacketEvent` from
   the connection...), and modules react through the bus. This is the "fire
   your own event" pattern from `fabric-mod`, so modules never need their own
   mixin for common hooks.
4. **Settings** are fields created with `addSetting(...)`. Because they are
   registered on the module, the Click GUI, the saved config, the per-module
   chat command (`.<module> <setting> <value>`) and the changelog markers all
   pick them up with no extra code.
5. **HUD elements** are modules in the `HUD` category (`AbstractElement` /
   `AbstractTextElement`), registered in the same manager.
6. **Commands** are Brigadier commands on a client-side dispatcher,
   intercepted from chat by a prefix (default `.`).

## Adding a feature: pick the recipe

`references/recipes.md` has step-by-step checklists with code skeletons:

- New module (the common case), plus adding a setting to an existing one.
- New HUD element.
- New chat command.
- New event, plus the mixin that posts it.
- Shared behavior across modules (a "controller" component with a
  `SettingGroup`).
- The changelog entry every user-visible change needs.
- Tests for pure logic.

Do the cheapest thing that fits. A tick-driven feature is a module with a
`GameTickEvent` listener. Drawing in the world is a `Render3DEvent` listener,
and drawing on screen is a HUD element. Reach for a new mixin only after
checking the existing events and Fabric API, following `fabric-mod`.

## Conventions to follow

- **Match the codebase.** Same package layout
  (`features/modules/impl/<category>/XModule.java`), same naming
  (`XModule`, `XElement`, `XCommand`, `XEvent`), `final` classes, Lombok
  where the neighbors use it, Mojang-style names.
- **Describe everything.** Each module sets `this.description`; each setting
  takes a user-facing description. The GUI and `.help` show them, and they
  should say what the thing does in plain words.
- **Comments say why, not what**, in plain sentences, the way the existing
  code does.
- **Safe, ordinary defaults.** New settings start at values that behave like
  a normal player where they can; users raise them on purpose. Keep any
  server-specific limits in the restriction system (`ServerRestriction`,
  `ServerExclusive`) instead of scattering host checks through modules.
- **Own your state.** Reset everything in `onDisable()` (held keys,
  rotations, queued actions) so toggling off always leaves the game as the
  player had it. Guard `mc.player` / `mc.level` for null at the top of tick
  listeners.
- **Register it.** A module or HUD element that is not added to the
  `ModuleManager` constructor does not exist. Order there is GUI order.
- **Small commits**, conventional style, and update the changelog with the
  change (see the recipe).

## Verify

```bash
./gradlew build        # compiles and runs the JUnit tests
./gradlew runClient    # launch the dev client and use the feature
```

A green build does not prove a module works: open the Click GUI, toggle it,
change each setting, check `.help`/`.<module>`, and confirm disabling restores
normal behavior. If the game can't be launched, say so and list what the user
should test.

## References

- `references/architecture.md`: package map, lifecycle, event flow, the
  settings and config model, restrictions, components.
- `references/recipes.md`: checklists and code skeletons for each kind of
  change.
