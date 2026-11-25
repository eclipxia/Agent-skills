# Mixins: last resort

This file is the gate: whether a mixin is justified. Once it is, use the
`fabric-mixin` skill for how to write, register, and debug it.

Read this before writing, changing, or approving a mixin. Mixins patch
Minecraft's bytecode at load time. They're powerful and fragile: targets move
every Minecraft version, two mods patching the same spot can conflict, and
failures show up at runtime (often only when that code path runs).

## Contents
- Before you write one
- Which kind of mixin
- Keep the mixin tiny: fire your own event
- Client mixin config
- Writing it safely
- Reviewing an existing mixin

## Before you write one

Work down the ladder in `SKILL.md` and be able to say why each rung above
failed:

1. Is there a Fabric API event, registry, or helper? (`references/api-map.md`;
   docs `events/`.) Check the current Fabric API, not memory: hooks are added
   every release.
2. Can data/assets do it (models, item definitions, lang, particle JSON,
   resource pack)?
3. Do you only need to *read* game state? Use `Minecraft.getInstance()` from a
   tick or HUD callback.
4. Is the only obstacle visibility (private/final) or a missing interface? Use a
   **class tweaker** (`class-tweakers/access-widening`, `interface-injection`)
   instead.
5. Do you only need a private field/method? Use an **accessor/invoker** mixin
   (`mixins/accessors`), no behavior change.

Only then is an injection mixin justified. In your reply to the user, name the
rung you landed on and in one sentence why the higher ones didn't work (e.g.
"Fabric API has no event for X, so this is a single `@Inject` that fires a
custom event").

## Which kind of mixin (least to most invasive)

- `@Accessor` / `@Invoker`
  - Use: Expose a private member
  - Risk: Low
- `@Inject` at `HEAD`/`RETURN`/`TAIL` (optionally cancellable)
  - Use: Run code at a method boundary
  - Risk: Low-medium
- `@ModifyVariable`, `@ModifyArg`, `@ModifyReturnValue` (MixinExtras)
  - Use: Tweak a value
  - Risk: Medium
- `@WrapOperation` (MixinExtras)
  - Use: Wrap a call so others can still coexist
  - Risk: Medium; preferred over `@Redirect`
- `@Redirect`
  - Use: Replace one call
  - Risk: High: only one mod can redirect the same call
- `@Overwrite`
  - Use: Replace a whole method
  - Risk: Highest: avoid; breaks every other mod touching it

Prefer boundary injections (`HEAD`/`RETURN`) over fragile ones that count
bytecode offsets or local-variable indexes. If you must target a lambda or
capture locals, the docs' bytecode page (`mixins/bytecode`) explains lambda
methods, LVT indexes, and `invokedynamic`. Names are unobfuscated since 26.1, so
targets can be named directly, which makes matching more reliable.

## Keep the mixin tiny: fire your own event

The docs' recommended pattern when no hook exists: define a callback interface
with an `Event`, fire it from a one-line injection, and do all real logic in a
normal listener.

```java
public interface MyHookCallback {
    Event<MyHookCallback> EVENT = EventFactory.createArrayBacked(
        MyHookCallback.class,
        listeners -> (arg) -> {
            for (MyHookCallback l : listeners) {
                InteractionResult r = l.onHook(arg);
                if (r != InteractionResult.PASS) return r;
            }
            return InteractionResult.PASS;
        });

    InteractionResult onHook(SomeType arg);
}

@Mixin(TargetClass.class)
abstract class TargetClassMixin {
    @Inject(method = "targetMethod", at = @At("HEAD"), cancellable = true)
    private void mymod$onTarget(SomeType arg, CallbackInfo ci) {
        var result = MyHookCallback.EVENT.invoker().onHook(arg);
        if (result != InteractionResult.PASS) ci.cancel();
    }
}
```

Benefits: the fragile part is 3 lines; the rest of the mod is testable normal
code; adding a second listener later costs nothing. (Adjust `cancellable`/return
types to the real target. The shape above is illustrative and the exact injector
signature depends on the target method.)

## Client mixin config

Register client-only mixins in a separate config and mark it client in
`fabric.mod.json`:

```json
{ "config": "mymod.client.mixins.json", "environment": "client" }
```

```json
{
  "required": true,
  "minVersion": "0.8",
  "package": "com.example.mymod.mixin.client",
  "compatibilityLevel": "JAVA_25",
  "client": ["TargetClassMixin"],
  "injectors": { "defaultRequire": 1 }
}
```

Set `compatibilityLevel` to the project's Java version (`JAVA_21` on 1.21.x,
`JAVA_25` on 26.x). `defaultRequire: 1` makes a mixin whose injection point
vanished fail loudly at startup instead of silently doing nothing, which is what
you want during a version bump.

## Writing it safely

- **Prefix** injected method names with the mod id (`mymod$onTarget`) to avoid
  collisions with other mods.
- One mixin class per target class; keep them `abstract`/package-private with no
  public API.
- Don't put mod logic in the mixin; delegate (see the event pattern).
- Keep client mixins out of common-side code and config. Client classes
  referenced from a common mixin crash dedicated servers.
- Verify target names against the sources for the exact version (`./gradlew
  genSources`). Never guess method names or descriptors from memory.
- After writing, run `./gradlew runClient` and exercise the code path. Mixin
  errors usually appear only when the target class loads, so a clean compile
  proves little.

## Reviewing an existing mixin

For each mixin in a project (also when porting): does a Fabric API event/helper
now cover it? Could it be an accessor or class tweaker? Is it
`@Redirect`/`@Overwrite` where `@WrapOperation`/`@Inject` would do? Is it in the
client config only if it touches client classes? Replace or delete wherever the
answer lets you. Every mixin removed is one fewer thing to break on the next
Minecraft release.
