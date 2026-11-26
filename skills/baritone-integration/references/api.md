# Baritone API surface

Read from branch `26.3` (v1.20.0). Only `baritone.api.*` is supported to
integrate against. Always confirm against the branch that matches the
project's Minecraft version.

## Contents
- Versions and where the right code lives
- Entry points
- Behaviors
- Processes
- Goals
- Player context and input
- Events
- Settings
- Commands
- Reading the source

## Versions and where the right code lives

- Baritone keeps a branch per Minecraft version (for example `1.21.4`,
  `26.1`, `26.2`, `26.3`); the repository's default branch can lag, so do not
  read the default branch for a newer game. Use
  `git ls-remote --heads https://github.com/cabaletta/baritone.git` to list
  them, and clone with `--branch <mc version>`.
- Major Baritone version per Minecraft version (from `SETUP.md`): 1.21.4 →
  v1.13, 1.21.5 → v1.14, 1.21.6-1.21.8 → v1.15, 1.21.9-1.21.10 → v1.16,
  1.21.11 → v1.17, 26.1 → v1.18, 26.2 → v1.19, 26.3 → v1.20.
- Releases: `https://github.com/cabaletta/baritone/releases`. File names:
  `baritone-api-fabric-<ver>.jar` (for integration and play),
  `baritone-standalone-fabric-<ver>.jar` (play only, fully obfuscated),
  `baritone-unoptimized-fabric-<ver>.jar` (debugging). Forge, NeoForge and
  tweaker variants also exist. The 26.3 API jar is v1.20.0.
- Java: 25 for 26.x, 21 for 1.20.5-1.21.11, 17 for 1.18-1.20.4.
- Mod id `baritone`; its `fabric.mod.json` requires Fabric Loader >= 0.19.5
  and Minecraft ~26.3 on that branch. It is `"environment": "*"`.
- Javadocs for the latest release: <https://baritone.leijurv.com/>.

## Entry points

```java
IBaritoneProvider provider = BaritoneAPI.getProvider();
IBaritone baritone = provider.getPrimaryBaritone();
Settings settings = BaritoneAPI.getSettings();
```

`IBaritoneProvider` also has `getAllBaritones()`, `getBaritoneForPlayer`,
`getBaritoneForMinecraft`, `getBaritoneForConnection`, `createBaritone(mc)`,
`destroyBaritone`, `getWorldScanner()`, `getCommandSystem()` and
`getSchematicSystem()`. `BaritoneAPI` loads `baritone.BaritoneProvider`
reflectively, so it throws if the Baritone mod is not on the classpath at
runtime.

`IBaritone` exposes: `getPathingBehavior()`, `getLookBehavior()`,
`getFollowProcess()`, `getMineProcess()`, `getBuilderProcess()`,
`getExploreProcess()`, `getFarmProcess()`, `getCustomGoalProcess()`,
`getGetToBlockProcess()`, `getElytraProcess()`, `getWorldProvider()`,
`getPathingControlManager()`, `getInputOverrideHandler()`,
`getPlayerContext()`, `getGameEventHandler()`, `getSelectionManager()`,
`getCommandManager()`.

## Behaviors

`IPathingBehavior`: `getGoal()`, `isPathing()`, `hasPath()`,
`cancelEverything()` (returns whether anything was cancelled),
`forceCancel()`, `estimatedTicksToGoal()`, `ticksRemainingInSegment()`,
`getPath()`, `getInProgress()`, `getCurrent()`, `getNext()`.

`ILookBehavior`: `updateTarget(Rotation, boolean blockInteract)`,
`getAimProcessor()`.

## Processes

A process is a task that can control pathing. Only one is in control at a
time; `getPathingControlManager()` picks by priority.

- `ICustomGoalProcess`: `setGoal(Goal)`, `path()`, `getGoal()`,
  `mostRecentGoal()`, `setGoalAndPath(Goal)`. The basic "go there" route.
- `IGetToBlockProcess`: `getToBlock(Block | BlockOptionalMeta)`,
  `blacklistClosest()`.
- `IMineProcess`: `mine(int quantity, Block... | BlockOptionalMeta... |
  BlockOptionalMetaLookup)`, `mineByName(...)`, `cancel()`.
- `IFollowProcess`: `follow(Predicate<Entity>)`, `pickup(Predicate<ItemStack>)`,
  `following()`, `currentFilter()`, `cancel()`.
- `IExploreProcess`: `explore(centerX, centerZ)`, `applyJsonFilter(...)`.
- `IFarmProcess`: `farm()`, `farm(range)`, `farm(range, pos)`.
- `IBuilderProcess`: `build(name, schematic, origin)` (and a file overload),
  `buildOpenSchematic()`, `buildOpenLitematic(i)`, `pause()`, `resume()`,
  `isPaused()`, `clearArea(corner1, corner2)`, `getApproxPlaceable()`,
  `getMinLayer()`, `getMaxLayer()`.
- `IElytraProcess`: `pathTo(BlockPos | Goal)`, `currentDestination()`,
  `getPath()`, `resetState()`, `isLoaded()`, `isSafeToCancel()`,
  `repackChunks()`. Has a terms-accepted setting (`elytraTermsAccepted`) that
  must be set for it to run.
- `IBaritoneProcess` (to write your own): `isActive()`,
  `onTick(calcFailed, isSafeToCancel)` returning a `PathingCommand(goal,
  PathingCommandType)`, `isTemporary()`, `onLostControl()`, `priority()`,
  `displayName0()`. `PathingCommandType`: `SET_GOAL_AND_PATH`,
  `REQUEST_PAUSE`, `CANCEL_AND_SET_GOAL`, `REVALIDATE_GOAL_AND_PATH`,
  `FORCE_REVALIDATE_GOAL_AND_PATH`, `DEFER`, `SET_GOAL_AND_PAUSE`. Register a
  custom process with the control manager when a client feature should
  cooperate with Baritone's priority system instead of fighting it.

Pattern:

```java
IBaritone b = BaritoneAPI.getProvider().getPrimaryBaritone();
b.getCustomGoalProcess().setGoalAndPath(new GoalBlock(pos));
b.getMineProcess().mine(64, Blocks.DIAMOND_ORE);
b.getPathingBehavior().cancelEverything();   // stop
```

## Goals

`baritone.api.pathing.goals`: `GoalBlock(pos | x,y,z)`, `GoalXZ(x, z)`,
`GoalYLevel(y)`, `GoalNear(pos, range)`, `GoalGetToBlock(pos)` (get adjacent
to a block), `GoalTwoBlocks(pos)` (stand at the feet or head position of a
2-high spot), `GoalComposite(goals...)`, `GoalInverted(goal)`,
`GoalRunAway(distance, from...)`, `GoalAxis`, `GoalStrictDirection(origin,
direction)`. A custom goal implements `Goal`: `isInGoal(x, y, z)` and
`heuristic(x, y, z)` (an admissible estimate to the goal, in the pathing's
cost units).

## Player context and input

- `IPlayerContext`: `minecraft()`, `player()`, `world()`, `playerFeet()`,
  `playerHead()`, `playerMotion()`, `playerRotations()`, `getSelectedBlock()`,
  `isLookingAt(pos)`, `entities()`.
- `IInputOverrideHandler`: `isInputForcedDown(Input)`,
  `setInputForceState(Input, boolean)`, `clearAllKeys()`. This is how Baritone
  presses keys; clearing it is part of any stop path.

## Events

`IBaritone.getGameEventHandler()` is an `IEventBus` with
`registerEventListener(IGameEventListener)`. Use
`AbstractGameEventListener` to override only what you need. Callbacks:
`onTick`, `onPostTick`, `onPlayerUpdate`, `onSendChatMessage`,
`onPreTabComplete`, `onChunkEvent`, `onBlockChange`, `onRenderPass`,
`onWorldEvent`, `onSendPacket`, `onReceivePacket`, `onPlayerRotationMove`,
`onPlayerSprintState`, `onBlockInteract`, `onPlayerDeath`, `onPathEvent`.
`PathEvent` values: `CALC_STARTED`, `CALC_FINISHED_NOW_EXECUTING`,
`CALC_FAILED`, `NEXT_SEGMENT_CALC_STARTED`, `NEXT_SEGMENT_CALC_FINISHED`,
`CONTINUING_ONTO_PLANNED_NEXT`, `SPLICING_ONTO_NEXT_EARLY`, `AT_GOAL`,
`PATH_FINISHED_NEXT_STILL_CALCULATING`, `NEXT_CALC_FAILED`, `DISCARD_NEXT`,
`CANCELED`. Bridge these into the client's own event bus when modules need to
react to "arrived" or "failed".

## Settings

`BaritoneAPI.getSettings()` returns a `Settings` object of
`Setting<T>` fields with `.value`; roughly a hundred. They persist to
`baritone/settings.txt` in the game directory (read by `SettingsUtil` when
`BaritoneAPI` loads). Useful ones (defaults on 26.3): `allowBreak` (true),
`allowPlace` (true), `allowSprint` (true), `allowParkour` (false),
`allowInventory` (false), `autoTool` (true), `assumeExternalAutoTool`
(false), `primaryTimeoutMS` (500), `failureTimeoutMS` (2000),
`pathCutoffFactor` (0.9), `maxFallHeightNoWater` (3), `avoidance` (false),
`legitMine` (false), `freeLook` (true), `blockFreeLook` (false),
`antiCheatCompatibility` (true), `renderPath`, `renderGoal`, `logAsToast`,
`prefix` ("#"), `chatControl` (true), `chatControlAnyway` (false),
`prefixControl` (true), `blocksToAvoid`, `blocksToDisallowBreaking`,
`acceptableThrowawayItems`, `buildInLayers`, `mapArtMode`,
`elytraTermsAccepted`.
Read the javadoc above each field for meaning. Set them with
`settings.allowBreak.value = false;`.

Embedding note from the source: `chatControl` ("Allow chat based control of
Baritone. Most likely should be disabled when Baritone is imported for use in
something else").

## Commands

`IBaritone.getCommandManager().execute("goto 100 64 200")` runs a Baritone
command string without the prefix, and `tabComplete(...)` gives suggestions,
which lets a client forward its own command to Baritone. User-facing command
list: Baritone's `USAGE.md` (goto, goal, path, mine, follow, build, farm,
explore, tunnel, cancel/stop, waypoints, selection, and so on).

## Reading the source

```bash
git clone --depth 1 --branch 26.3 https://github.com/cabaletta/baritone.git
# API: src/api/java/baritone/api/
# Settings and docs: src/api/java/baritone/api/Settings.java
# Install/versions: SETUP.md, usage: USAGE.md, features: FEATURES.md
```

Clone into a fresh directory of your own and do not run its build scripts
unless the user asks.
