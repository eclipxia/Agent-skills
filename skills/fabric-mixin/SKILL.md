---
name: fabric-mixin
description: >-
  Write, review, debug, or fix Mixins, accessors, and class tweakers (access
  wideners) in a Fabric Minecraft mod, once it is established that Fabric API
  has no hook for the job. Use when the user asks for a mixin, @Inject,
  @WrapOperation, @Accessor, @Invoker, an access widener or classtweaker, or
  hits mixin errors like InvalidInjectionException, "target not found", a
  mixin that silently does nothing, or a crash after a Minecraft update. If
  the user has not yet ruled out Fabric API events, data/assets, or a class
  tweaker, use the fabric-mod skill first, because it decides whether a mixin
  is justified. Not for Forge/NeoForge mixins or Paper plugins.
---

# Writing Fabric mixins

A mixin patches Minecraft's bytecode at load time. It is the right tool only
after the cheaper options are ruled out, and it must be written defensively
because targets move on every Minecraft release and other mods may patch the
same code. This skill covers the "how". The "whether" lives in the
`fabric-mod` skill (its decision ladder and `references/mixins-last-resort.md`).

## Step 1: Confirm a mixin is needed

Before writing anything, check the rungs below and tell the user which one you
landed on. Skipping this is how projects end up with fragile, conflicting
patches.

1. A Fabric API event, registry, or helper exists. Check the docs for the
   project's version and the Fabric API sources. New hooks appear regularly.
2. Data or assets can do it (models, item definitions, lang, resource packs).
3. Reading game state from a tick or HUD callback is enough.
4. Only visibility is the problem (private/final/missing interface): use a
   **class tweaker** instead. See `references/accessors-and-tweakers.md`.
5. Only a private field/method is needed: use an **accessor/invoker**.

If you land on 4 or 5 you are done with this skill's heavy machinery. Only
continue to injection mixins when none of these work.

## Step 2: Read the project

- Minecraft version, Loom plugin, Java version (`gradle.properties`,
  `build.gradle`). Since 26.1 the game is unobfuscated: there are no mappings
  to translate and target names are the real names. On 1.21.11 and older
  (Yarn, remapping Loom), names differ and refmaps are involved, so check the
  docs for that version.
- Existing `*.mixins.json`, the `mixins` entry in `fabric.mod.json`, and the
  package layout. Match them.
- Whether MixinExtras (`@WrapOperation`, `@ModifyReturnValue`, `@Local`...) is
  available. Recent Fabric Loader versions bundle it, but the Fabric docs
  pages do not state this, so confirm by checking that the project compiles
  with a MixinExtras import, or consult the Loader and MixinExtras READMEs
  before relying on it. If it is missing, add it per its README.

## Step 3: Find the real target

Never guess a method name, descriptor, or injection point from memory.

- Run `./gradlew genSources` and read the target class in the IDE or the
  generated sources jar.
- For the exact bytecode shape (needed for `@At("INVOKE")` targets, lambdas,
  local variables), use the docs' bytecode page (`mixins/bytecode`):
  descriptors like `(IILjava/lang/String;I)V`, `<init>`/`<clinit>`, and lambda
  bodies compiled to synthetic `lambda$<method>$<n>` methods.
- Prefer a target that is stable and public-ish (a method boundary) over a
  specific line in the middle of a method.

## Step 4: Pick the least invasive injector

See `references/injectors.md` for the full guide. Short version, in order of
preference:

1. `@Accessor` / `@Invoker`: no behavior change.
2. `@Inject` at `HEAD` / `RETURN` / `TAIL`.
3. MixinExtras: `@ModifyReturnValue`, `@ModifyExpressionValue`,
   `@WrapOperation`, `@WrapWithCondition`. These compose with other mods.
4. `@ModifyVariable` / `@ModifyArg` / `@ModifyConstant` when needed.
5. `@Redirect`: avoid. Only one mod can redirect a given call. Use
   `@WrapOperation` instead.
6. `@Overwrite`: avoid. Explain the cost to the user and look for another way
   first.

## Step 5: Write it so it stays small

- Put real logic in ordinary classes. The mixin only calls into them, ideally
  by firing a custom Fabric `Event` (pattern in `fabric-mod`'s
  `references/mixins-last-resort.md`). Three lines of fragile code is better
  than thirty.
- Prefix every added method and field with the mod id and `$`
  (`mymod$onTick`) so you cannot collide with another mod's mixin.
- One mixin class per target class. Mixin classes are not public API: never
  call them directly from other code, other than accessor interfaces which you
  cast to.
- Client-only targets go in a **client** mixin config, declared in
  `fabric.mod.json` as `{ "config": "<id>.client.mixins.json", "environment":
  "client" }`, and live in the client source set. Config template and package
  rules are in `references/injectors.md`.
- Set `"injectors": { "defaultRequire": 1 }` so a vanished injection point
  fails loudly at startup instead of silently doing nothing.

## Step 6: Verify at runtime

A clean compile proves very little. Mixin problems appear when the target
class loads.

1. `./gradlew runClient` and exercise the exact code path the mixin affects.
2. If something is wrong or silent, read `references/debugging.md` (export the
   mixed class with `-Dmixin.debug.export=true`, enable verbose output, read
   the error).
3. Report to the user what you verified and what you could not (for example,
   you could not launch the game).

## References

- Injector choice, `@At` targets, MixinExtras, config files, examples:
  `references/injectors.md`
- Accessors, invokers, class tweakers (access widening), interface injection:
  `references/accessors-and-tweakers.md`
- Debug flags, exported classes, common errors and what they mean:
  `references/debugging.md`
