# The client-owned pathfinder alternative

Reference: `~/git/magnum` (package `me.shae`). Read these files there before
building one, and note the design choices below. This describes the design,
not a drop-in library.

## Contents
- When to own it
- Design of the reference
- Goal contract
- Walker and ownership
- Elytra
- Using it behind the facade
- Pitfalls

## When to own it

Choose it when modules need exact control over rotations and inputs, must
cooperate with the client's other movement and rotation components, or when
depending on another mod is unacceptable. Choose Baritone when you want mining,
building, farming, exploring and elytra routing without writing them. Mixed
clients run both behind one facade (`integration.md`, section 3).

## Design of the reference

Files (all under `src/main/java/me/shae/`):

- `utils/PathFinder.java`: A* over "spots" you can stand on. It considers walk
  steps, one-block jumps, short drops, swimming, ladders and vines, doors and
  gates, tunneling (with a break cost, avoiding blocks touching fluids or with
  falling blocks above), and placing blocks to bridge or pillar. Costs are in
  ticks. It is configured with an `Options` record (dig, swim, climb, doors,
  place, place count, max fall, node budget, avoid set, planned breaks, place
  cost function).
- `utils/Goals.java`: goal records (`GoalBlock`, `GoalXZ`, ...) implementing
  `PathFinder.Goal`.
- `features/components/WalkerController.java`: turns a path into per-tick
  inputs and rotations, handles breaking and placing, stuck detection and
  re-planning, and can render its plan.
- `features/modules/impl/core/PathfindingModule.java`: the shared module that
  owns the walker and the settings, plus the `.goto` command and static
  entry points for other modules.
- `utils/ElytraPathFinder.java` and `features/components/ElytraController.java`:
  flying routes, modeled on how Baritone plans elytra flight (trying a route
  out in a simulation, keeping to one route, treating unseen chunks as open
  air at a higher cost).

Key ideas worth copying:

- **Time-sliced search.** A search is started and advanced for a small budget
  each tick, so long searches never freeze the game; when the budget runs out
  it returns the way to the spot closest to the target, so far trips are made in
  parts as more of the world loads.
- **Costs in ticks, plus penalties.** Slow blocks, swims, lava proximity and
  turns cost more, so the result is the quickest practical route, not just the
  shortest.
- **Goals are rebuilt every tick** from where things are, so a goal for a moving
  target follows it. A goal supplies per-spot `cost` (NaN means "not a
  finish"), `target()` and an `estimate` heuristic.
- **Goals can carry a finishing cost,** such as the blocks still in the way of
  an ore from a spot, so the route is cheapest all the way to the end.

## Goal contract

A goal answers three questions: is this spot a finish and what extra cost does
finishing here have (`cost(spot)`, NaN if not a finish), where does the search
head (`target()`), and a lower-bound estimate for pruning (`estimate(spot)`).
Compare Baritone's `Goal`: `isInGoal(x, y, z)` and `heuristic(x, y, z)`. The
two map cleanly, which is what lets a facade accept one goal abstraction and
convert to either implementation.

## Walker and ownership

One walker serves every module. A module calls
`PathfindingModule.path(owner, rotations, goal, dig)` each tick it wants to go
somewhere; the walker moves it one tick toward the goal using that module's
own rotation settings. Only one owner has the walker at a time and keeps it
while it keeps asking, or until it calls `cancel(owner)`; others asking in the
meantime are not moved and wait. `pause(owner)` and `claim(owner, ...)` exist
for hand-offs. This ownership rule is what prevents two features fighting over
movement, and the same rule is what you should apply when sharing control with
Baritone (`SKILL.md`, rotation and input ownership).

## Elytra

Long trips are flown when an elytra is available, picked by environment
(highways, nether rocket flight, overworld climb-and-glide), landing near the
end and walking the rest, with elytra swapping and mending handled. This is
large (about 1,000 lines each for the controllers); treat Baritone's
`IElytraProcess` (which requires `elytraTermsAccepted`) as the cheaper
alternative unless the client needs different behavior.

## Using it behind the facade

Implement `PathingBackend` over `PathfindingModule`:
`goTo(pos)` becomes `path(owner, rotations, new GoalBlock(pos), dig)` called
each tick until arrival (the owner object is the pathing feature), `cancel()`
becomes `cancel(owner)`, `busy()` becomes `isWalking()`. Because the walker
needs per-tick calls, the backend holds the goal and a tick listener drives it;
Baritone's process is self-driving, so keep that difference inside the backend.

## Pitfalls

- Searches near unloaded chunks: treat unknown space explicitly (open air at a
  higher cost, as the elytra finder does) rather than as solid.
- Digging near fluids and falling blocks: refuse breaks that flood or drop
  gravel on the player.
- Stuck detection and an avoid set: remember spots where progress stalled and
  route around them on the next search.
- Always release rotations and inputs when ownership ends.
- Keep pure cost and geometry logic in testable helpers and unit test it
  (see Magnum's `PearlFlightTest`/`SelfSafetyTest` for the style).
