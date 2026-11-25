# How a utility client fits together

A description of the framework pattern, using the reference implementation
(`~/git/magnum`, package `me.shae`, main class `Mhack`) for concrete names.
Another client will use its own names for the same roles, so map them: "main
class" means that client's `ModInitializer`, "module manager" its registry of
features, and so on. Verify against the actual project before relying on a
detail.

## Contents
- Package map
- Startup and singletons
- Modules: lifecycle and gating
- Event bus
- Hooks: mixins that feed modules
- Settings and persistence
- Commands
- HUD elements
- Restrictions
- Components (shared controllers)
- Build, resources, and metadata

## Package map

- `Mhack.java`: mod class (`ModInitializer`), holds static singletons.
- `events/`: the bus (`Event`, `EventManager`, `Handler`, `Listener`,
  `Subscriber`, `Priority`) and `events/impl/<area>/` event types: `client`
  (module toggle), `game` (tick, packet, chat, entity spawn, block update,
  player list, entity status), `input` (keyboard, mouse), `player` (tick,
  attack), `render/screen` (HUD render), `render/world` (3D render, world
  render, entity submit).
- `features/modules/`: `AbstractModule`, `ModuleCategory`, `ModuleManager`;
  implementations in `impl/{combat,movement,player,visual,misc,core}`.
- `features/settings/`: `AbstractSetting`, `SettingGroup`, and `impl/` with
  the concrete types.
- `features/hud/`: `AbstractElement`, `AbstractTextElement`, `ElementManager`
  (layout, anchors), and `impl/` elements.
- `features/commands/`: `AbstractCommand`, `CommandManager`, `impl/`.
- `features/configs/`: `ConfigManager`, `ProfileManager`.
- `features/components/`: shared controllers and trackers (rotation, action,
  inventory, target, render, entity filter, fall/combat trackers, walker,
  elytra controllers...).
- `features/restrictions/`, `features/relations/`, `features/waypoints/`,
  `features/macros/`, `features/changelog/`, `features/cloud/`.
- `uis/`: Click GUI, HUD editor, changelog screens, theme.
- `utils/`: stateless helpers (chat, color, placement, hole finding, render
  helpers, fonts, pathfinding, ...), with pure ones unit tested.
- `mixins/`: one mixin per patched vanilla class, organized by Mojang
  package (`client/renderer/...`, `world/entity/...`), with `*Accessor`
  interfaces for private members.
- `src/main/resources/`: `fabric.mod.json`, `mhack.mixins.json` (plus an
  optional-dependency mixin config such as Sodium), `assets/mhack/`
  (`changelog.json`, textures, shaders). `src/test/java/` holds tests.

## Startup and singletons

`Mhack` declares `public static final` managers and components. Constructors
register things (`ModuleManager` registers every module and HUD element, then
registers itself on the event bus; `CommandManager` registers commands, then
one settings command per module). `onInitialize()` is empty: construction
order of the static fields is the startup order. `fabric.mod.json` has
`"environment": "client"` and only a `main` entrypoint, because the whole mod
is client-only and is loaded from client contexts.

Modules fetch each other with
`Mhack.MODULE_MANAGER.getModule(SomeModule.class)`.

## Modules: lifecycle and gating

`AbstractModule` provides: `name`, `category`, `description`, `persistent`
(whether configs save the enabled state), a keybind with `TOGGLE` or `HOLD`
mode, a `Drawn` setting (shown in the module list), the settings list, and
`getSuffix()` (text shown next to the name in the module list).

- `setEnabled(boolean)` checks the restriction manager (locked or blocked
  modules refuse), then calls `onEnable()` / `onDisable()` on changes.
- `listening()` is `enabled && !locked`. The event manager skips listeners of
  handlers that are not listening, so disabled modules cost almost nothing.
- Defaults: set `this.setEnabled(true)` in the constructor for modules on by
  default; `getBindMode().setValue(BindMode.HOLD)` for hold-to-use.

## Event bus

```java
@Subscriber                       // optionally @Subscriber(Priority.HIGH)
private final Listener<GameTickEvent> gameTickEventListener = event -> {
    if (event.phase() != GameTickEvent.Phase.START || mc.player == null) return;
    // ...
};
```

- `EventManager.register(handler)` scans the class and its superclasses for
  `@Subscriber` fields of type `Listener<E>`, so listener fields declared in a
  base class (a shared `SearchModule`, say) also work.
- `post(event)` calls listeners from highest to lowest priority; equal
  priority keeps registration order. Events are looked up by exact class.
- Cancellable events carry a `cancelled` flag (see `PacketEvent`); the posting
  mixin reads it afterwards.
- Add an event only when more than one consumer needs the hook or a mixin
  would otherwise be duplicated. A single consumer can use a static module
  method called from the mixin (see below).

## Hooks: mixins that feed modules

Two patterns exist side by side:

1. **Post an event** from a mixin: `Minecraft.runTick` posts
   `GameTickEvent(START/END)`. Modules subscribe. Prefer this for anything
   several modules might use.
2. **Static module hook**: a mixin asks a module a question through a static
   method, such as `ZoomModule.getFovDivisor()` (from a camera mixin) or
   `SprintModule.omniDirectional()`. The static method looks the module up,
   returns the vanilla answer when the module is off, and reads settings
   otherwise. Use this when a mixin needs a value or veto from one specific
   module, not a broadcast.

Mixins wrap or modify at the narrowest point (`@WrapOperation`,
`@WrapWithCondition`, `@Inject` at a boundary) and delegate straight away.
Writing them follows the `fabric-mixin` skill, and the config uses
`defaultRequire: 1` and a `client` list. Before adding a mixin, check
whether Fabric API already offers the hook (`fabric-mod`).

## Settings and persistence

`AbstractSetting<T>` holds the value, default, name, description, an optional
`visibleIf(...)` condition, and a lock (set by server restrictions; the user's
own value is kept and saved while locked). Subclasses implement
`setFromText` (chat/GUI input), `toJson` and `fromJson` (config files, which
clamp to bounds and ignore unknown values).

Concrete types in `features/settings/impl/`: Boolean, Int, Long, Float,
Double (with min/max/step), String, Choice, Mode (enum cycling), Bind, Color,
and list types (Block, Item, SoundList, MobEffect, generic Registry).

Config files live under `.minecraft/mhack/` (`configs/<name>.json`, plus
`client.json`). `ConfigManager` serializes every module's enabled state,
bind, settings and HUD positions through the settings' JSON methods, so a new
setting is saved automatically. Renaming or removing a setting is a
compatibility change for saved configs; `fromJson` should tolerate missing
and unknown values.

`SettingGroup` bundles settings several modules share. A module adds a whole
group with `addSettings(group)`; the GUI shows it under the group's name while
configs and commands treat the settings as the module's own.

## Commands

`AbstractCommand(name)` builds a Brigadier literal on a
`CommandDispatcher<ClientSuggestionProvider>`. `ChatScreenMixin` intercepts
chat that starts with the prefix; `CommandSuggestionsMixin` gives the
vanilla-style suggestions. Every module automatically gets a `ModuleCommand`
for its settings (skipped if the name collides with an existing command), and
shared groups get `.rotate`, `.inventory`, `.targets`, and similar commands
that set a setting across every module having it.

## HUD elements

`AbstractElement extends AbstractModule` (category `HUD`) with an anchor
and offset, drag/stack support in the HUD editor, and show/hide animation.
Subclasses implement `getWidth()`, `getHeight()`, `render(graphics,
deltaTracker)`; `AbstractTextElement` simplifies the common "lines of text"
case via `getLines()`. They draw with `GuiGraphicsExtractor` (the 26.x
render-state API). Elements are registered in the same `ModuleManager`
constructor under the `/* Hud */` section.

## Restrictions

`RestrictionManager` holds `ServerRestriction`s (per-host: blocked modules,
settings locked to a value, modules forced on/off) and `ServerExclusive`s
(modules usable only on given hosts). Host matching covers subdomains and
singleplayer is unrestricted. `AbstractModule.setEnabled` and
`AbstractSetting.getValue` consult these, so modules need no host checks of
their own.

## Components (shared controllers)

`features/components/` holds behavior that many modules share so that they
cooperate instead of fighting over the same resource: rotation, inventory
clicks, held actions, targeting, rendering boxes, entity filtering, trackers
for combat and falling, and large walkers/controllers (elytra, pathing).
Modules request things through these (`Mhack.ROTATION_COMPONENT.rotate(...)`
then `.release()`) and release them in `onDisable()`. Reuse a component
before writing parallel logic in a module, and add a new component when two
modules need the same resource.

## Build, resources, and metadata

- `build.gradle`: Loom plugin `net.fabricmc.fabric-loom`, `release = 25`,
  Lombok (compile-only plus annotation processor, main and test), JUnit 5, an
  optional compile-only Modrinth dependency for Sodium compatibility.
- `gradle.properties`: Minecraft, Loader, Loom, Fabric API, mod version.
  When bumping the mod version, `Mhack.VERSION` and the changelog id follow.
- CI (`.github/workflows/build.yml`): `./gradlew build` on push and PR with
  JDK 25, uploads `build/libs`.
- Changelog: `assets/mhack/changelog.json` (structured, drives the in-game
  `+`/`*` markers) and `CHANGELOG.txt` (plain text). Keep both in sync.
