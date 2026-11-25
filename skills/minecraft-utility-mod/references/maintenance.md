# Maintaining a utility client

A client built this way ages through Minecraft updates, not through its own
features. The goal of every task here is to keep the fragile surface (mixins,
rendering code) small and well understood, and keep users' saved configs
working.

## Contents
- Updating to a new Minecraft version
- Auditing mixins
- Config and settings compatibility
- Optional dependencies
- Releases and changelog
- Housekeeping
- Review checklist

## Updating to a new Minecraft version

1. **Read first.** Fabric's blog post and the docs' porting pages for the
   target version (`https://docs.fabricmc.net/develop/porting/`), and the
   Fabric API porting notes. Rendering and input have changed between major
   versions; 26.x uses an extract/submit render model.
2. **Bump versions together** from the template generator or example mod:
   Minecraft, Loader, Loom, Fabric API, Java, plus the mod version. Update
   `fabric.mod.json` `depends` and any compile-only optional dependencies.
3. **Refresh dev sources** (`./gradlew genSources`) so you can read the real
   target classes.
4. **Compile and fix in layers**, smallest blast radius first: utilities and
   modules (renames, signature changes), then rendering, then mixins.
   Commit each layer.
5. **Mixins last, and audit them** (below). A mixin that compiled can still
   fail at startup; `defaultRequire: 1` makes that loud.
6. `./gradlew build`, then `./gradlew runClient`, and exercise every area the
   changes touched: GUI, each hook the event bus exposes (tick, input,
   packets, rendering, chat), HUD, commands, config load/save.
7. Update the changelog and bump the version.

Use small commits during a port (`fix:`/`refactor:` per layer), not one giant
"update to X" commit, so a regression can be bisected.

## Auditing mixins

Every mixin is a recurring cost. Periodically, and on every port, for each
mixin ask:

1. Does Fabric API now offer an event or helper for this hook? Replace it,
   deleting the mixin. New hooks are added every release.
2. Could it be an accessor or class tweaker instead of an injector?
3. Is it `@Redirect` or `@Overwrite` where `@WrapOperation` or an `@Inject`
   would do? Those conflict with other mods.
4. Is it still needed (is the module that used it still in the client)?
5. Is the logic in the mixin or delegated to an event or static hook?
   Heavy logic in mixins should move out.
6. Is it in the client mixin config, with client-only targets kept out of the
   common one?

The `fabric-mod` skill's `scripts/audit-client-mod.sh` summarizes mixins and
flags client classes leaking into common code. Run it on the project for a
quick inventory, then work through the list. Consolidate several mixins on the
same target when practical; keep them one-per-target-class.

Prefer posting events from mixins so modules stay mixin-free. When many
modules each added their own mixin on the same class, that is a sign a shared
event or static hook is missing.

## Config and settings compatibility

Users' saved configs outlive code, so:

- **Never rename or retype a setting casually.** Its name is the config key
  and the command argument. If a rename is worth it, accept the old key when
  loading (read old, write new) and mention it in the changelog.
- **Loading must be tolerant**: missing keys keep defaults, unknown keys are
  ignored, out-of-range numbers are clamped, removed enum values keep the
  current mode.
- **New settings default to the old behavior**, so updating changes nothing
  until the user opts in.
- **Removing a module or setting** needs a changelog `removed` entry and, if
  the config would otherwise error, a skip rule for the stale key.
- Config files get a version field if the shape of the file (not just a
  setting) ever changes, with a migration step on load.

## Optional dependencies

Compatibility with another mod (a renderer, a schematic mod) goes in its own
mixin config and code path, compile-only, guarded so the client runs without
it: check whether the mod is loaded (`FabricLoader.getInstance().isModLoaded`)
before touching its classes, and consider a mixin config plugin for
conditional mixins. Declare it under `suggests`, not `depends`.

## Releases and changelog

- One changelog entry per user-visible change, using the exact module and
  setting names. If the GUI marks new/changed items from it, a typo silently
  loses the marker, so cross-check names against the code before release.
- Keep the structured changelog and any plain-text copy in sync.
- Keep the version in one source of truth (`gradle.properties`), and have the
  main class constant and `fabric.mod.json` follow it (`${version}`
  expansion).
- CI builds on every push and pull request; release artifacts come from
  `build/libs`.

## Housekeeping

- Delete dead modules, settings, events and mixins instead of leaving them
  disabled; unregistered code still has to compile on every port.
- Keep unit tests for the pure logic (calculations, parsing, damage or path
  math) and run them in CI; they are the cheapest regression net across
  Minecraft updates.
- Keep shared behavior in components and settings groups, not copy-pasted
  between modules; when you find duplication across three modules, extract it.
- Keep descriptions accurate when behavior changes; they are the in-game docs.

## Review checklist

When reviewing a change to a client built this way:

1. Does the feature live in one module and register through the manager?
2. Are all settings described, with defaults that preserve current behavior?
3. Does `onDisable()` undo everything and do tick/render listeners null-check?
4. Is any new mixin justified through the ladder, tiny, prefixed, in the
   client config, and delegating to an event or static hook?
5. Are saved configs still loadable? Were names changed?
6. Changelog entry with exact names? Version bumped if releasing?
7. Built, tests passing, and tried in `runClient`?
