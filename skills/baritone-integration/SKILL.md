---
name: baritone-integration
description: >-
  Integrate the Baritone pathfinding bot into a client-side Minecraft (Fabric)
  utility client, or decide between Baritone and the client's own pathfinder.
  Use whenever the user mentions Baritone, BaritoneAPI, goto/mine/follow/
  build/farm/explore automation through Baritone, wiring pathfinding into
  modules or commands, Baritone goals or settings, baritone.api, or asks how
  a client should do pathfinding or auto-walking, even if they only say "add
  pathfinding" or "make it walk to a block". Covers adding the dependency,
  a backend facade, module/command/HUD wiring, rotation and input ownership,
  settings sync, and updating when Minecraft or Baritone versions change.
  Works with the minecraft-utility-mod, fabric-mod and fabric-mixin skills.
---

# Baritone integration for utility clients

Baritone is a pathfinding and automation bot (goto, mine, follow, build,
farm, explore, elytra) that other clients can use as a library: its README
says it is meant to be used in custom utility clients, under the LGPL-3.0.
This skill covers how to integrate it cleanly, and how to choose between it
and a client-owned pathfinder.

Facts here were read from the Baritone repository (`cabaletta/baritone`,
branch `26.3`, release `v1.20.0`, Java 25, Fabric Loader 0.19.5+) on
2026-11-25. Baritone ships one branch per Minecraft version, so before
relying on a signature, read the branch that matches the project's Minecraft
version (see `references/api.md` for how). If the client writes its own
pathfinder, `~/git/magnum` has one that can serve as a reference only
(`references/own-pathfinder.md`); design the client's own for its needs.

## Step 1: decide the approach

Ask or infer which of these fits, because they lead to different code:

1. **Baritone as the backend.** Fastest route to a mature pathfinder with
   mining, building, farming, exploring and elytra. Costs: an external
   dependency to keep in step with each Minecraft version, Baritone's own
   mixins and input handling in the game, and less control over exact
   movement. Best when the client wants features, not custom movement.
2. **Client-owned pathfinder.** Full control over rotations, inputs, timing
   and how it cooperates with the client's other modules. Costs: you write and
   maintain the search and the movement. Magnum's is a reference to read, not
   a template. Best when modules need tight control
   (for example, movement that must look like a specific kind of player) or
   when you cannot depend on another mod.
3. **Both behind a facade.** Define a small pathing interface (go to goal,
   cancel, is-busy, status) with a Baritone implementation and an own
   implementation, so modules do not care which runs. Choose this when the
   client already has its own walker and wants Baritone's heavier processes
   (mine, build, elytra) without rewriting them.

If the project already has a pathfinder, default to option 3 and keep its
modules on the facade. If it has none, default to option 1.

## Step 2: wire it (Baritone as backend)

Follow `references/integration.md` in order. In short:

1. **Dependency.** Use the release jar `baritone-api-fabric-<version>.jar`
   for the project's Minecraft version (the "API" variant exists for mods
   that integrate; the "standalone" variant is for players and cannot be
   used as a library). Put it on the compile classpath and on the dev
   runtime. Players install the same jar as a mod. Declare it in
   `fabric.mod.json` under `suggests` (optional) or `depends` (required).
2. **Never touch anything outside `baritone.api`.** Only that package is
   supported in the API jar; the rest is obfuscated and can change.
3. **Get the instance lazily and null-safely.** `BaritoneAPI.getProvider()
   .getPrimaryBaritone()`; guard every use so the client still runs when
   Baritone is absent (class-loading it from a module that is always loaded
   will crash without the jar, so keep all Baritone references in one backend
   class that is only loaded when the mod is present).
4. **Silence Baritone's own chat control** (`chatControl` off, and choose a
   non-clashing `prefix`) because Baritone intercepts chat and its docs say
   this should be disabled when it is embedded. Expose commands through the
   client's own command system and call Baritone's command manager from
   there if wanted.
5. **Decide who owns rotation and input** before writing modules (below).
6. **Map the features onto the client's own module, settings, command and
   HUD systems** (`minecraft-utility-mod`) so users never see two parallel
   UIs.

## Rotation and input ownership (the part that goes wrong)

Baritone drives the player by forcing key states (`IInputOverrideHandler`)
and by setting look targets through its look behavior (`freeLook`,
`blockFreeLook` and `antiCheatCompatibility` control how). A client with its
own rotation or movement component will fight it. Decide one policy and
write it down in the code:

- **Baritone owns movement while a Baritone process is active.** The client's
  own movement modules back off (check `pathing.isBusy()` or the facade), and
  release their rotation and input claims.
- **The client owns rotation, Baritone owns pathing.** Use Baritone's
  `freeLook` so it does not force the client-side camera, and route its
  look targets through the client's rotation component if the API allows it.
  Verify this works in game, since it depends on Baritone's internals.
- **Never run two controllers at once.** Cancel one before starting the other
  (`cancelEverything()` on Baritone; the client's own cancel on the other).

Also check for mixin conflicts: Baritone patches the player, controller,
screen, chunk and render classes. When a client mixin targets the same
method, test both orders and prefer `@WrapOperation`/`@Inject` over
`@Redirect`.

## Conventions

- **One backend class.** All `baritone.api` imports live behind a facade or a
  single backend, so removing or replacing Baritone later is a one-file
  change and the client builds without the jar when it is optional.
- **Always provide a stop path.** Disabling a module or calling stop must
  call `cancelEverything()`, clear input overrides, and release anything the
  client claimed.
- **Mirror settings, do not duplicate state.** If the client exposes Baritone
  settings in its GUI, read and write `BaritoneAPI.getSettings()` values
  directly, and treat Baritone's settings file as the persistence layer or
  save them in the client's config explicitly. Do not keep a second copy that
  can drift.
- **Respect server rules.** Automation is blocked on many servers. Gate it
  with the client's restriction system, and keep Baritone's defaults for
  placing, breaking and inventory use conservative unless the user opts in.
- **License.** Baritone is LGPL-3.0. Keep its license text with a bundled
  copy, do not strip notices, and keep it as a replaceable library (a
  separate jar) rather than copying its source into a closed client.

## Verify

```bash
./gradlew build
./gradlew runClient
```

In game with Baritone loaded: path to a nearby goal and watch it arrive,
cancel mid-route and confirm movement stops and keys release, toggle the
module on and off repeatedly, run it while another movement module is
enabled, and run the client without Baritone to confirm it still starts. Say
what you could not test.

## References

- `references/api.md`: the verified API surface (provider, behaviors,
  processes, goals, events, input, settings, commands), version mapping, and
  where to look when it changes.
- `references/integration.md`: dependency setup, facade, module/command/HUD
  mapping, lifecycle, rotation/input policy, updating versions.
- `references/own-pathfinder.md`: pointers to Magnum's pathfinder as a
  reference for a client-owned one.
