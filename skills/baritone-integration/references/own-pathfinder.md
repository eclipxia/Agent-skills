# Building your own pathfinder

A client-owned pathfinder is a small A* search over "spots you can stand on",
plus a walker that turns the result into key presses and rotations. This file
gives the logic and the code shape for each part. The snippets use
Mojang-style names (Minecraft 26.x) and are deliberately compact: compile-check
them against the project, then grow them one capability at a time.

## Contents
- When to build your own
- Architecture
- 1. The goal contract
- 2. Spots, floors and passability
- 3. Moves and costs
- 4. The search (time-sliced A*)
- 5. The walker
- 6. Ownership: one controller at a time
- 7. Growing it
- 8. Pitfalls
- 9. Testing
- 10. Behind the Baritone facade

## When to build your own

Choose it when modules need exact control over rotations, inputs and timing,
must cooperate with the client's other movement components, or when depending
on another mod is unacceptable. Baritone is the better choice when you want
mining, building, farming, exploring and elytra routing without writing them
(`SKILL.md`). Many clients run both behind one facade (section 10).

## Architecture

```
Goal ──► PathFinder (A*, time-sliced) ──► Path (list of Steps)
                                              │
Module ──claims──► Walker (per tick) ◄────────┘
                      └─► inputs + rotation, replans when stuck
```

- **Goal**: says which spots finish the trip and roughly how far a spot is.
- **PathFinder**: pure search; reads the world, never moves the player.
- **Walker**: follows a path each tick and owns movement while it does.
- **Ownership**: one module controls the walker at a time.

## 1. The goal contract

```java
public interface Goal {
    /** Extra cost of finishing at this spot, in ticks; NaN = not a finish. */
    double cost(BlockPos pos);

    /** Where the search heads; used by the default estimate. */
    BlockPos target();

    /** Lower-bound estimate of the cost from here to the goal. */
    default double estimate(BlockPos pos) {
        BlockPos t = target();
        if (t == null) return 0.0;
        int dx = Math.abs(pos.getX() - t.getX());
        int dz = Math.abs(pos.getZ() - t.getZ());
        int dy = pos.getY() - t.getY();
        // Straight plus diagonal steps, which is how it actually walks
        double flat = Math.max(dx, dz) + (Math.sqrt(2) - 1) * Math.min(dx, dz);
        return Math.sqrt(flat * flat + dy * dy) * Costs.WALK;
    }
}

record GoalBlock(BlockPos pos) implements Goal {
    public double cost(BlockPos spot) {
        return spot.equals(pos) ? 0.0 : Double.NaN;
    }
    public BlockPos target() { return pos; }
}

record GoalXZ(int x, int z) implements Goal {          // any height in a column
    public double cost(BlockPos s) {
        return s.getX() == x && s.getZ() == z ? 0.0 : Double.NaN;
    }
    public BlockPos target() { return new BlockPos(x, 0, z); }
    public double estimate(BlockPos s) { return Goal.super.estimate(s.atY(0)); }
}
```

Why this shape:

- `cost` doubling as the finish test lets a goal charge for finishing, for
  example the ticks to break what still stands between a spot and an ore, so
  the route found is cheapest all the way to the end, not just to the first
  acceptable spot.
- Goals are cheap records rebuilt every tick from where things are, so a goal
  for a moving target (a player, an animal) follows it naturally.
- The estimate must never exceed the true cost or A* stops being optimal;
  using the walking cost per block keeps it safe.

Baritone's `Goal` has `isInGoal(x, y, z)` and `heuristic(x, y, z)`, which map
directly onto `cost`'s NaN test and `estimate`.

## 2. Spots, floors and passability

A **spot** is a block position your feet can occupy. Its **floor** is the
height you stand at, which is not always an integer (slabs, carpet,
farmland). Everything in the search goes through these helpers, so get them
right first.

```java
final class World {
    final ClientLevel level;

    boolean passable(BlockPos p) {                   // body can occupy it
        BlockState s = level.getBlockState(p);
        return s.getCollisionShape(level, p).isEmpty()
            && !s.getFluidState().is(FluidTags.LAVA)
            && !s.is(Blocks.FIRE) && !s.is(Blocks.CACTUS);
    }

    /** Height you would stand at in this spot, or NaN if you cannot. */
    double floor(BlockPos p) {
        if (!passable(p) || !passable(p.above())) return Double.NaN; // 2 high
        BlockPos below = p.below();
        BlockState b = level.getBlockState(below);
        if (b.getFluidState().is(FluidTags.WATER)) return p.getY();   // swim
        VoxelShape shape = b.getCollisionShape(level, below);
        if (shape.isEmpty()) return Double.NaN;       // nothing to stand on
        double top = below.getY() + shape.max(Direction.Axis.Y);
        // A floor above the block top needs head room above the spot too
        if (top > p.getY() && !passable(p.above(2))) return Double.NaN;
        return top;
    }
}
```

Keep a per-search cache (`Long2DoubleOpenHashMap` keyed by `pos.asLong()`),
since floors are queried many times. Treat unloaded chunks explicitly
(`level.hasChunkAt(pos)`): either refuse to path into them or give them a
high cost, never silently treat them as solid.

## 3. Moves and costs

Costs are in **ticks**, so a slow action counts as a long way round. Start
with this small set and add the rest later (section 7):

```java
final class Costs {
    static final double WALK = 4.6, SWIM = 9.0, JUMP = 2.0, FALL = 1.0;
    static final double CLIMB_UP = 5.0, CLIMB_DOWN = 6.7;
    static final double LAVA_NEAR = 40.0, TURN = 1.5;
    static final double STEP_HEIGHT = 0.6, JUMP_HEIGHT = 1.25;
}

enum Move { WALK, JUMP, FALL, SWIM, CLIMB, DIG, BRIDGE, PILLAR }

record Step(BlockPos pos, double floor, Move move, BlockPos from) {}
record Path(List<Step> steps, boolean complete) {}   // complete = reaches goal
```

Neighbour generation from a node, for each of the eight horizontal
directions:

```java
List<Node> neighbours(Node from) {
    List<Node> out = new ArrayList<>();
    for (int[] d : DIRECTIONS) {              // 4 straight + 4 diagonal
        int dx = d[0], dz = d[1];
        boolean diagonal = dx != 0 && dz != 0;
        // No cutting corners: both blocks beside a diagonal must be clear
        if (diagonal
                && (!clearBeside(from, dx, 0) || !clearBeside(from, 0, dz)))
            continue;
        walk(out, from, dx, dz, diagonal);
    }
    return out;
}

void walk(List<Node> out, Node from, int dx, int dz, boolean diagonal) {
    BlockPos level = from.pos.offset(dx, 0, dz);
    double horizontal = diagonal ? Math.sqrt(2) : 1.0;

    // 1) Same height, or a step Minecraft climbs on its own
    double f = world.floor(level);
    if (!Double.isNaN(f) && Math.abs(f - from.floor) <= Costs.STEP_HEIGHT) {
        boolean swim = world.isWater(level);
        out.add(link(from, level, f,
            (swim ? Costs.SWIM : Costs.WALK) * horizontal,
            swim ? Move.SWIM : Move.WALK));
        return;
    }
    // 2) Jump up one block (not diagonally; need head room above start)
    BlockPos up = level.above();
    double uf = world.floor(up);
    if (!diagonal && !Double.isNaN(uf) && uf - from.floor <= Costs.JUMP_HEIGHT
            && world.passable(from.pos.above(2))) {
        out.add(link(from, up, uf, Costs.WALK + Costs.JUMP, Move.JUMP));
        return;
    }
    // 3) Drop: air in the column beside, fall to the first floor below
    if (world.passable(level) && world.passable(level.above())) {
        for (int drop = 1; drop <= maxFall; drop++) {
            BlockPos down = level.below(drop);
            double df = world.floor(down);
            if (!Double.isNaN(df)) {
                out.add(link(from, down, df,
                    Costs.WALK * horizontal + Costs.FALL * drop, Move.FALL));
                return;
            }
        }
    }
}
```

`link` builds the next node: `cost = from.cost + stepCost`, plus
`TURN` when the direction changed, parent set to `from`, and the move kind
stored for the walker:

```java
Node link(Node from, BlockPos pos, double floor, double stepCost, Move move) {
    Node n = new Node(pos.immutable(), floor);
    n.parent = from;
    n.move = move;
    n.cost = from.cost + stepCost;      // + Costs.TURN if the direction changed
    return n;
}
```

Then add penalties that shape the result: extra cost for spots next to lava
(`LAVA_NEAR`), a small cost for changing direction (`TURN`) so equal-length
routes prefer the straightest, and the **tie-break** factor in the node
comparison (below).

## 4. The search (time-sliced A*)

```java
final class PathFinder {
    private static final double TIE_BREAK = 1.001;
    private final Long2ObjectOpenHashMap<Node> nodes =
        new Long2ObjectOpenHashMap<>();
    private final PriorityQueue<Node> open = new PriorityQueue<>();
    private final Goal goal;
    private final int maxNodes;
    private Node first, closest;
    private int visited;
    private Path result;
    private boolean done;

    static final class Node implements Comparable<Node> {
        final BlockPos pos; final double floor;
        double cost, estimate;
        Node parent;
        Move move = Move.WALK;
        boolean closed;
        Node(BlockPos pos, double floor) { this.pos = pos; this.floor = floor; }
        public int compareTo(Node o) {
            return Double.compare(cost + estimate * TIE_BREAK,
                                  o.cost + o.estimate * TIE_BREAK);
        }
    }

    PathFinder(BlockPos start, Goal goal, int maxNodes) {
        this.goal = goal; this.maxNodes = maxNodes;
        first = new Node(start.immutable(), world.floor(start));
        first.estimate = goal.estimate(start);
        closest = first;
        nodes.put(start.asLong(), first);
        open.add(first);
    }

    /** Runs for about `nanos`; returns true once finished. Call every tick. */
    boolean search(long nanos) {
        if (done) return true;
        long end = System.nanoTime() + nanos;
        int sinceCheck = 0;
        while (!open.isEmpty() && visited < maxNodes) {
            if (++sinceCheck >= 64) {                  // check the clock rarely
                sinceCheck = 0;
                if (System.nanoTime() > end) return false;
            }
            Node n = open.poll();
            // A spot reached again by a shorter way leaves a stale entry: skip
            if (n.closed || nodes.get(n.pos.asLong()) != n) continue;
            n.closed = true; visited++;

            double finish = goal.cost(n.pos);
            if (!Double.isNaN(finish) && finish <= 0.0)
                return done(build(n, true));
            if (n.estimate < closest.estimate) closest = n;

            for (Node next : neighbours(n)) {
                Node known = nodes.get(next.pos.asLong());
                if (known != null && (known.closed || known.cost <= next.cost))
                    continue;
                next.estimate = goal.estimate(next.pos);
                nodes.put(next.pos.asLong(), next);
                open.add(next);
            }
        }
        // Gave up or ran out of space: go as near as it got, so far trips are
        // made in parts and replanned as more of the world loads
        return done(closest == first ? null : build(closest, false));
    }

    private static Path build(Node end, boolean complete) {
        List<Step> steps = new ArrayList<>();
        for (Node n = end; n.parent != null; n = n.parent)
            steps.add(new Step(n.pos, n.floor, n.move, n.parent.pos));
        Collections.reverse(steps);
        return new Path(steps, complete);
    }
    private boolean done(Path p) {
        result = p; done = true;
        nodes.clear(); open.clear();
        return true;
    }
    Path result() { return result; }
}
```

Key points:

- **Time slicing**: call `search(2_000_000L)` (about 2 ms) each tick, so a
  long search never freezes the game. Return partial paths to the closest spot
  when the node budget runs out, then plan again from there.
- **Lazy deletion**: a node found by a cheaper route is re-queued; the old
  queue entry is skipped when popped (the `nodes.get(...) != n` check).
- **Goals that charge for finishing**: when `finish > 0`, add a "finishing"
  node with `cost + finish` to the queue instead of ending immediately, so the
  cheaper overall finish wins (useful for "mine this ore from the cheapest
  spot").
- **Run it off-thread only if the world reads are thread-safe**; the simple
  and safe default is the time-sliced approach above on the game thread.

## 5. The walker

The walker takes the current `Path` and, each tick, decides inputs and
rotation. It does not search.

```java
final class Walker {
    private Path path;
    private int index;
    private int stuckTicks;
    private Vec3 lastPos = Vec3.ZERO;

    void setPath(Path p) { path = p; index = 0; stuckTicks = 0; }

    /** Call once per tick while this walker has control. */
    Result tick(LocalPlayer player, RotationControl rotation) {
        if (path == null || index >= path.steps().size())
            return path != null && path.complete()
                ? Result.ARRIVED : Result.NEEDS_NEW_PATH;

        Step step = path.steps().get(index);
        Vec3 target = Vec3.atBottomCenterOf(step.pos())
            .with(Direction.Axis.Y, step.floor());

        // Advance when we are on, or past, the step
        if (player.position().distanceToSqr(target) < 0.25 * 0.25
                || reachedByHeight(player, step)) {
            index++;
            return Result.WALKING;
        }

        // Face the step (yaw only for walking; pitch left alone)
        double dz = target.z - player.getZ(), dx = target.x - player.getX();
        float yaw = (float) (Mth.atan2(dz, dx) * 180 / Math.PI) - 90f;
        rotation.request(yaw);

        boolean jump = step.move() == Move.JUMP
                || (step.floor() - player.getY() > 0.6 && player.onGround());
        press(player, true, jump, /*sprint*/ step.move() == Move.WALK);

        // Stuck: no real progress for a second, replan around this spot
        double moved = player.position().distanceToSqr(lastPos);
        stuckTicks = moved < 0.0004 ? stuckTicks + 1 : 0;
        lastPos = player.position();
        if (stuckTicks > 20) return Result.STUCK;
        return Result.WALKING;
    }

    void stop(LocalPlayer player, RotationControl rotation) {
        path = null;
        releaseKeys(player);      // always release on every exit
        rotation.release();
    }
}
enum Result { WALKING, ARRIVED, NEEDS_NEW_PATH, STUCK, BUSY }
```

How to set inputs depends on the client: either set the movement-key states
the game reads, or write the player's input object directly during the input
phase, and match how the client's other movement code already does it. Keep
that code in one method (`press`) so a Minecraft update changes one place.

Per-step behavior to add as you grow:

- **Replan triggers**: `STUCK`, a block on the path changed
  (`BlockUpdate`), the goal moved (goals are rebuilt every tick; compare
  `target()`), or the path ended before the goal (`!complete`).
- **Smoothing**: look a step or two ahead and aim there, so turns round
  corners instead of stopping at each spot center.
- **Stop cleanly**: on arrival, cancel, disable or world change, release keys
  and rotation. Leaving a key forced is the classic bug.

## 6. Ownership: one controller at a time

Several modules will want to walk. Give the walker one owner at a time:

```java
final class Pathing {
    private Object owner;
    private final Walker walker = new Walker();

    /** A module calls this each tick it wants to go somewhere. */
    Result path(Object who, Goal goal /* rebuilt each tick */) {
        if (owner != null && owner != who)
            return Result.BUSY;                       // wait your turn
        owner = who;
        // (re)plan if there is no path or the goal moved, then walker.tick(...)
        return stepOnce(goal);
    }

    void cancel(Object who) {
        if (owner == who) { walker.stop(player, rotation); owner = null; }
    }
}
```

The owner keeps control while it keeps asking, or until it cancels; others
asking meanwhile are refused and try again later. This prevents two features
fighting over inputs and rotation, and it is the same rule to apply when
sharing control with Baritone (`SKILL.md`).

## 7. Growing it

Add one capability at a time, each as new neighbour generators plus a walker
behavior, with its own cost:

- **Swimming and wading** (cost `SWIM`, keep your head out of water).
- **Ladders and vines** (`CLIMB_UP`/`CLIMB_DOWN`, hold forward or jump/sneak).
- **Doors and gates**: open the shut ones, only on the level, and cost extra.
- **Digging** (tunnel ahead, a step up, or down): cost the break time plus a
  penalty, so it digs only where it is clearly shorter than walking round.
  Never break a block touching water or lava, or one with gravel or sand above
  it, and leave containers and doors alone. Remember blocks a previous route
  planned to break and make them cheaper, so a new route keeps to the same
  tunnel.
- **Placing blocks**: bridge across a gap (place ahead, then walk) and pillar
  up (jump, place under yourself), limited by how many blocks you hold.
- **Flying (elytra)**: a separate search over positions in open air plus a
  controller that handles take-off, rockets and landing. Substantial; consider
  Baritone's elytra process before writing it.

## 8. Pitfalls

- Over-estimating in `estimate` makes routes suboptimal; keep it a lower bound.
- Stale cached floors after a block changes; clear caches per search.
- Unloaded chunks treated as solid or air without a cost.
- Stuck loops: remember spots where progress stalled and add them to an
  "avoid" set for the next search.
- Searching every tick for a moving goal: replan only when the target moved
  by more than a block or the path became invalid.
- Forgetting to release inputs and rotation on every exit path.

## 9. Testing

Put the pure parts (cost model, estimate, goal logic, path building) behind
plain-value inputs so JUnit tests can cover them without a running game:
for a hand-built grid, assert the cheapest route, tie-breaks, partial paths
when the budget runs out, and that `estimate` never exceeds the true cost. Then
test movement in `runClient` on a flat world with obstacles: gaps, steps,
water, lava edges, and a goal that moves.

## 10. Behind the Baritone facade

Wrap this in the same `PathingBackend` interface as Baritone
(`integration.md`, section 3): `goTo(pos)` stores a `GoalBlock` and the owner
drives `Pathing.path(...)` each tick until arrival; `cancel()` calls
`Pathing.cancel(owner)`; `busy()` is "has an owner". Keep the difference in
how they are driven (this needs a call every tick; Baritone's processes drive
themselves) inside the backend class.
