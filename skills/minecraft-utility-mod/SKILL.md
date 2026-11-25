---
name: minecraft-utility-mod
description: >-
  Create and maintain client-side Minecraft utility mods ("utility clients")
  on Fabric: a framework of toggleable modules with settings, an event bus,
  a Click GUI, HUD elements, chat commands, saved configs and a changelog.
  Use whenever the user wants to start a new utility client, add a module,
  setting, HUD element, command or event to one, update one to a new
  Minecraft version, audit or clean up its mixins and configs, or asks how a
  client like this should be organized, even if they only say "add a feature
  to my client" or "make a module that...". Works together with the fabric-mod
  skill (Fabric API first) and the fabric-mixin skill (the hooks that feed the
  event bus). Not for server plugins, Forge/NeoForge, or RusherHack plugins.
---

# Minecraft utility clients on Fabric

A utility client is a client-side Fabric mod made of many small,
independently toggleable **modules**, plus the shared machinery that makes
each one show up in a GUI, save in configs, respond to commands, and clean up
after itself. This skill is a blueprint for building a new client and for
keeping any client built this way healthy over many Minecraft versions.

The user's project at `~/git/magnum` (GitHub `qe7/Magnum`) is the reference
implementation. When it is available, look there for a worked example of any
pattern below before inventing one. It is a reference, not a template to copy
verbatim: names, packages, and the mod id belong to whichever client you are
working on. When working on an existing client, that client's own conventions
win.

For hooking into Minecraft, use the companion skills:

- `fabric-mod`: Fabric API first, client-only discipline, the mixin ladder.
- `fabric-mixin`: writing the mixin when no API hook exists.

## Decide what you are doing

1. **Starting a new client** → read `references/bootstrap.md` for the minimal
   framework to build first, then `references/framework.md` for how the parts
   fit.
2. **Adding to an existing client** (module, setting, HUD element, command,
   event) → read the client's nearest existing example, then
   `references/recipes.md`.
3. **Maintaining it** (new Minecraft version, mixin audit, config
   compatibility, releases) → read `references/maintenance.md`.

Detect which client you are in first: look for the `ModInitializer` class,
the module base class, the event manager and `fabric.mod.json`, and note the
Minecraft version, mappings and Java version from `gradle.properties` and
`build.gradle`. Use the project's names everywhere, and if it has no module
framework yet, offer to build one with `references/bootstrap.md`.

## Design principles (why the framework looks like this)

1. **One module per feature.** Each feature lives in one class that owns its
   settings and state. Features can be added, removed, or disabled without
   touching each other.
2. **Everything is registered, nothing is wired by hand.** A module added to
   the module manager automatically gets a GUI entry, a keybind, config
   saving, a settings command and a place in the module list. Adding a
   setting needs no GUI or config code. This is what keeps a client with
   hundreds of features maintainable.
3. **An event bus decouples game hooks from features.** Mixins and Fabric API
   callbacks post events; modules subscribe. Hooks are written once, and
   modules never need their own mixin for common needs. This also keeps the
   fragile part (mixins) small, which is what makes version updates cheap.
4. **Listeners only run while a module is enabled.** Disabled modules cost
   almost nothing, and enabling/disabling is the only lifecycle to reason
   about.
5. **Shared resources go through shared components.** Rotation, inventory
   clicks, held items, and target selection are owned by one component so that
   modules cooperate instead of fighting. Modules request and release.
6. **Settings are data.** Typed settings know how to read/write text and JSON
   and how to show themselves, so GUI, commands and configs share one model.
   Saved configs must survive updates (see maintenance).
7. **Hooks go through the ladder.** Fabric API first, then data/assets, then
   class tweaker or accessor, then a tiny mixin that posts an event or calls a
   static hook. See `fabric-mod` and `fabric-mixin`.

## Conventions to carry into any client

- **Describe everything.** Modules and settings take user-facing descriptions
  that say what the thing does in plain words. The GUI and help show them.
- **Safe, ordinary defaults.** New settings start at values that behave like
  a normal player where they can; users raise them on purpose. Server-specific
  limits belong in one restriction system, not scattered host checks.
- **Own your state.** Reset everything in `onDisable()` (held keys,
  rotations, queued actions, cached data) so toggling off always leaves the
  game as the player had it. Null-check player and world at the top of tick
  and render listeners.
- **Comments say why**, in plain sentences, not what the code obviously does.
- **Register it.** A module not added to the module manager does not exist.
  Registration order is GUI order.
- **Keep a changelog** with the same names the code uses, since the GUI can
  use it to mark what is new or changed.
- **Small, conventional commits** (see the user's `git-workflow` skill).

## Verify

```bash
./gradlew build        # compiles and runs unit tests
./gradlew runClient    # launch the dev client and use the feature
```

A green build does not prove a module works. Open the GUI, toggle the
feature, change each setting, try its command, and confirm that disabling
restores normal behavior. If the game cannot be launched, say so and list what
the user should test.

## References

- `references/bootstrap.md`: the minimal framework for a new client, with
  skeleton code for each core class.
- `references/framework.md`: how the parts fit; lifecycle, events, settings,
  commands, HUD, restrictions, components, configs.
- `references/recipes.md`: checklists for adding features.
- `references/maintenance.md`: version updates, mixin audits, config
  compatibility, releases.
