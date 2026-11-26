# Integrating Baritone into a client

Steps in the order to do them. Names like `Client`, `PathingBackend` and
`PathModule` are placeholders for the project's own classes
(`minecraft-utility-mod` describes the module, command and HUD systems).

## Contents
- 1. Dependency
- 2. Optional versus required
- 3. The backend facade
- 4. Lifecycle
- 5. Settings and chat control
- 6. Modules, commands and HUD
- 7. Rotation and input policy
- 8. Events
- 9. Updating versions
- 10. Troubleshooting

## 1. Dependency

Get `baritone-api-fabric-<version>.jar` for the project's Minecraft version
from the releases page (26.3 → v1.20.0 at the time of writing). The releases
include `checksums.txt` and a signature; verify the jar's hash against it
before adding it to a project, as Baritone's README advises.

Either way, put it on the compile classpath and on the dev runtime classpath
so `runClient` loads Baritone as a mod. With a Loom project on 26.x (no
remapping), plain Gradle configurations are used. Sketch:

```groovy
dependencies {
    compileOnly files("libs/baritone-api-fabric-1.20.0.jar")
    runtimeOnly files("libs/baritone-api-fabric-1.20.0.jar")
}
```

Confirm this against the Loom docs for the project's Loom version
(`https://docs.fabricmc.net/develop/loom/`): older remapping Loom needs
`modCompileOnly` / `modLocalRuntime` for mod jars, and whether a runtime-only
file dependency is loaded as a mod in dev depends on the Loom version. If it
is not picked up, drop the jar into the run directory's `mods/` folder
instead. Prefer not committing the jar (large, versioned per Minecraft
release); either download it in a Gradle task from the release URL or document
where to put it. Use the API variant, never `standalone`, which cannot be
used as a library.

## 2. Optional versus required

- **Optional** (recommended for a public client): list `baritone` under
  `suggests` in `fabric.mod.json`, keep every `baritone.api` reference inside
  one backend class, and only load that class when
  `FabricLoader.getInstance().isModLoaded("baritone")`. Without Baritone the
  pathing modules should disable themselves with a clear message.
- **Required**: list it under `depends`. Simpler code, but the client does not
  start without it.

Class loading is the trap: a module that is always loaded and merely mentions
a Baritone type in a field or signature can fail to load without the jar. Keep
Baritone types out of anything that always loads.

## 3. The backend facade

A small interface the rest of the client uses:

```java
public interface PathingBackend {
    boolean available();
    void goTo(BlockPos pos);               // or a goal abstraction
    void mine(int quantity, Block... blocks);
    void follow(Predicate<Entity> filter);
    void cancel();                          // stops and releases everything
    boolean busy();                         // anything controlling movement
    String status();                        // for HUD and logs
}
```

Implement `BaritoneBackend` (the only class importing `baritone.api`) and,
if the client has its own walker, `OwnBackend` (see `own-pathfinder.md`). A
registry picks one: `Client.PATHING.backend()`. Add methods only when a
module needs them; Baritone processes that have no equivalent in your own
backend (build, farm, elytra) can be Baritone-only features that the GUI
hides when the backend is missing.

Sketch of the Baritone side:

```java
final class BaritoneBackend implements PathingBackend {
    private IBaritone baritone() {
        return BaritoneAPI.getProvider().getPrimaryBaritone();
    }
    public boolean available() { return true; }
    public void goTo(BlockPos pos) {
        baritone().getCustomGoalProcess().setGoalAndPath(new GoalBlock(pos));
    }
    public void mine(int n, Block... blocks) {
        baritone().getMineProcess().mine(n, blocks);
    }
    public void cancel() {
        baritone().getPathingBehavior().cancelEverything();
        baritone().getInputOverrideHandler().clearAllKeys();
    }
    public boolean busy() {
        return baritone().getPathingBehavior().isPathing()
            || baritone().getPathingControlManager().mostRecentInControl()
                  .isPresent();
    }
    public String status() { /* current process displayName, ETA */ return ""; }
}
```

`mostRecentInControl()` returns an `Optional<IBaritoneProcess>` (verified on
the 26.3 branch), which also gives the active process's `displayName()` for
`status()`. The sketch shows intent; confirm any other method you add against
the branch.

## 4. Lifecycle

- Create nothing yourself: `getPrimaryBaritone()` is managed by Baritone and
  follows the player and world. Call it each time you need it rather than
  caching across worlds, and guard for "not in a world".
- On world change, disconnect, death, or the client's module being disabled:
  call the facade's `cancel()`. Baritone cancels its own state on some of
  these, but the client should not depend on that for its own claims.
- Never block the game thread waiting for a path. Baritone calculates on its
  own thread and exposes progress through `getInProgress()` and `PathEvent`s.

## 5. Settings and chat control

On startup (after Baritone is available):

```java
Settings s = BaritoneAPI.getSettings();
s.chatControl.value = false;      // do not eat chat; embedded use
s.prefixControl.value = false;    // route commands through the client
```

Pick one command route. If users should type Baritone commands, either keep
`prefixControl` on with a prefix that does not clash with the client's (the
default `#`), or have the client's command forward text to
`baritone.getCommandManager().execute(text)`.

Expose the settings that matter (`allowBreak`, `allowPlace`, `allowSprint`,
`allowParkour`, `allowInventory`, timeouts, `avoidance`, `freeLook`,
`legitMine`, `renderPath`...) as client settings that read and write
`s.<name>.value` directly, so the client's GUI and Baritone agree. Baritone
persists its own settings to `baritone/settings.txt`; decide whether the
client's config or that file is authoritative, and re-apply on load so the two
cannot drift. Defaults that touch the world (`allowBreak`, `allowPlace`,
`allowInventory`) should be reviewed against the client's own safety
defaults.

## 6. Modules, commands and HUD

- **Module(s):** a "Pathing" core module for global settings, and feature
  modules (Auto Mine via `IMineProcess`, Follow via `IFollowProcess`, Build,
  Farm, Explore) that start a process on enable and `cancel()` on disable.
  Gate each on `backend.available()`.
- **Commands:** `goto`, `stop`, `mine`, `follow`... on the client's own
  command system calling the facade, or a single passthrough command into
  Baritone's command manager.
- **HUD:** show current process name, ETA (`estimatedTicksToGoal()`), and
  goal; optionally render the path (Baritone has `renderPath`/`renderGoal`).
- **Notifications:** bridge `PathEvent` (`AT_GOAL`, `CALC_FAILED`,
  `CANCELED`) to client toasts or chat.

## 7. Rotation and input policy

Decide and write the policy in code comments (see `SKILL.md`). Practical
steps:

1. List every client component that sets rotations or presses movement keys
   (rotation component, movement modules, aura-like modules).
2. Define what happens when a Baritone process is active: either the client's
   movement modules refuse to run (check `backend.busy()`), or starting one
   cancels Baritone.
3. If the client has its own rotation system, test with `freeLook` on and
   off; with it on Baritone applies movement without forcing the visible
   camera, with it off it moves the camera. `blockFreeLook` extends that to
   breaking and placing. `antiCheatCompatibility` adjusts how silent rotations
   are set for sprinting.
4. Release input: call `clearAllKeys()` on cancel, and do not leave the
   client's own forced key states set after a hand-off.
5. For a feature that must coexist with Baritone's priorities, write a custom
   `IBaritoneProcess` (priority, `onTick` returning a `PathingCommand`)
   instead of fighting from outside.

## 8. Events

Register once per `IBaritone` (and again if you ever create more than one):

```java
baritone.getGameEventHandler().registerEventListener(
    new AbstractGameEventListener() {
        @Override public void onPathEvent(PathEvent event) {
            Client.EVENT_MANAGER.post(new PathingEvent(event));
        }
    });
```

Check how the project's event bus is used, and keep the listener inside the
backend class.

## 9. Updating versions

1. Pick the Baritone branch for the new Minecraft version (`SETUP.md` has the
   version table) and read what changed in `src/api` between the old and new
   branches (`git diff <old>..<new> -- src/api`).
2. Download the matching `baritone-api-fabric-<ver>.jar`, verify checksum,
   update the Gradle dependency, `fabric.mod.json` `suggests`/`depends`, and
   documentation.
3. Fix compile errors inside the backend class only (that is the point of the
   facade). Re-test cancel, goto, mine and any custom process.
4. Re-check mixin conflicts with the client's own mixins on shared classes,
   and re-check Baritone's defaults in `Settings.java` for changes.
5. Baritone often lags new Minecraft versions by days to weeks. If the matching
   branch does not exist yet, the client must still run without it (optional
   dependency) and the facade's own backend, if any, takes over.

## 10. Troubleshooting

- **`ClassNotFoundException: baritone.BaritoneProvider` or NoClassDefFound:**
  Baritone is not on the runtime classpath, or a Baritone type was loaded
  from always-loaded code.
- **Chat commands vanish or double-fire:** `chatControl`/`prefixControl`
  still on, or the client's prefix clashes with `#`.
- **Player jitters or rotates fighting between two systems:** two controllers
  active; apply the policy in section 7.
- **Won't path or stops instantly:** `allowBreak`/`allowPlace` off with a goal
  needing them, `blocksToAvoid`, no loaded chunks, or the elytra process
  without `elytraTermsAccepted`. Turn on `chatDebug` temporarily.
- **Crashes after a Minecraft update:** wrong Baritone branch for the game
  version, or a mixin conflict on the same target; compare logs for Baritone
  mixin names.
