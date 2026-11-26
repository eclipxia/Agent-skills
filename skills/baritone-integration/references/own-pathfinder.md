# Client-owned pathfinder: Magnum as a reference

When a client builds its own pathfinder instead of (or beside) Baritone, the
design belongs to that client. `~/git/magnum` (package `me.shae`) has one, and
it is only a reference: read it for ideas and to see one way the pieces fit,
then design what the project needs. Do not copy it wholesale or treat its
choices as requirements.

## Where to look in Magnum

Under `src/main/java/me/shae/`:

- `utils/PathFinder.java`: the search (A* over standable spots, with options
  for digging, swimming, climbing, doors and placing blocks).
- `utils/Goals.java`: goal types the search accepts.
- `features/components/WalkerController.java`: turns a path into per-tick
  inputs and rotations.
- `features/modules/impl/core/PathfindingModule.java`: the shared module that
  holds the walker and its settings, and how other modules ask it to go
  somewhere.
- `utils/ElytraPathFinder.java`, `features/components/ElytraController.java`:
  flight routing, itself inspired by Baritone's elytra planning.

Each file has a long class comment that explains its behavior; read those
before the code.

## What to take from it

Only these, and only where they suit the project:

- It is useful to have one owner of movement at a time, so several features
  do not fight over inputs and rotation. The same idea applies when sharing
  control with Baritone (see `SKILL.md`).
- Splitting a long search across ticks keeps the game responsive.
- Keeping the goal abstraction small (is this spot a finish, where to head,
  a lower-bound estimate) makes it easy to adapt to Baritone's `Goal`
  (`isInGoal`, `heuristic`) behind a facade.

## Using one behind the facade

Wrap the client's pathfinder in the same `PathingBackend` interface as
Baritone (`integration.md`, section 3) so modules do not care which runs.
Keep any difference in how the two are driven (a backend that needs a call
every tick versus Baritone's self-driving processes) inside the backend class.
