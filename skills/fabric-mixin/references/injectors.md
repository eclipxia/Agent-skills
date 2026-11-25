# Choosing and writing injectors

Mixin and MixinExtras are third-party libraries with their own docs:
<https://github.com/SpongePowered/Mixin/wiki> and
<https://github.com/LlamaLad7/MixinExtras/wiki>. The snippets below show the
shape; confirm signatures against the target class from `genSources`.

## Contents
- Injector guide, least to most invasive
- Common `@At` targets
- MixinExtras injectors
- Config file and registration
- Client mixin example
- Rules of thumb

## Injector guide, least to most invasive

- `@Accessor` / `@Invoker`: expose a private member. See
  `accessors-and-tweakers.md`.
- `@Inject(at = HEAD | RETURN | TAIL)`: run code at a method boundary.
  Add `cancellable = true` and use `ci.cancel()` (or `cir.setReturnValue(x)`
  for non-void) to skip the original. Low risk.
- `@ModifyReturnValue` (MixinExtras): change what a method returns. Better
  than `@Inject` at `RETURN` plus `cir.setReturnValue`, because several mods
  can chain it.
- `@ModifyExpressionValue` (MixinExtras): change the value of one expression
  (a method call result, field read, constant) inside the target.
- `@WrapOperation` (MixinExtras): wrap one call/field access/`new`, calling
  `original.call(...)` or skipping it. Chains with other mods. Use this
  instead of `@Redirect`.
- `@WrapWithCondition` (MixinExtras): run a void call only when a condition
  holds.
- `@ModifyVariable`, `@ModifyArg`, `@ModifyConstant`: tweak a local,
  argument, or constant. Locals depend on bytecode layout, so they break
  easily. MixinExtras `@Local` is more robust than raw indexes.
- `@Redirect`: replaces one call. Two mods redirecting the same call
  conflict. Avoid.
- `@Overwrite`: replaces a whole method. Avoid; if unavoidable, tell the user
  it will conflict with any other mod touching that method.

## Common `@At` targets

- `@At("HEAD")`, `@At("RETURN")`, `@At("TAIL")`: method boundaries. Most
  stable.
- `@At(value = "INVOKE", target = "Lpkg/Owner;method(I)V")`: before a specific
  call. Needs an exact owner and descriptor, so copy it from the sources.
- `@At(value = "FIELD", ...)`, `@At("NEW")`, `@At("CONSTANT")`: field access,
  object creation, constants.
- Constructors are `<init>`, static initializers `<clinit>`, lambdas
  `lambda$<method>$<n>` (a synthetic name that shifts when the source
  changes, so re-check after each update).
- `ordinal`, `shift`, and `slice` narrow an ambiguous target. If you need
  several of them to pin one spot, the target is fragile: look for a boundary
  injection or a `@WrapOperation` on a unique call instead.

## MixinExtras injectors

Wrap a call and keep the original reachable:

```java
@WrapOperation(
    method = "targetMethod",
    at = @At(value = "INVOKE",
             target = "Lsome/pkg/TargetClass;expensiveCalculation(Z)I"))
private int mymod$maybeBypass(TargetClass instance, boolean flag,
                              Operation<Integer> original) {
    return MyMod.bypass ? 10 : original.call(instance, flag);
}
```

Handler arguments for an instance call: the receiver, the original arguments,
then `Operation<ReturnType>`. For a static call: the original arguments, then
the `Operation`. Always go through `original.call(...)` unless you mean to
skip the call.

Modify a return value:

```java
@ModifyReturnValue(method = "getSpeed", at = @At("RETURN"))
private float mymod$scaleSpeed(float original) {
    return original * MyMod.speedFactor();
}
```

MixinExtras also has `@Local` (capture a local variable), `@Share` (share a
value between injectors in one method), `@ModifyReceiver`, `@WrapMethod`, and
an expression language for precise targets. Read the relevant wiki page before
using these; do not write them from memory. Whether MixinExtras is on the
classpath depends on the Fabric Loader version, so check that a MixinExtras
import compiles before you rely on it.

## Config file and registration

`src/main/resources/<modid>.mixins.json` (or `src/client/resources` for the
client config):

```json
{
  "required": true,
  "minVersion": "0.8",
  "package": "com.example.mymod.mixin",
  "compatibilityLevel": "JAVA_25",
  "mixins": ["SomeCommonMixin"],
  "client": ["client.SomeClientMixin"],
  "injectors": { "defaultRequire": 1 }
}
```

- `package` is the base package; entries are class names relative to it.
- `compatibilityLevel` matches the project's Java: `JAVA_25` on 26.x,
  `JAVA_21` on 1.21.x.
- `"client"` entries load only on the physical client. A fully client-only
  mod can instead use a separate client config (below) and leave `"mixins"`
  empty.
- `"defaultRequire": 1` turns "injection point not found" into a startup
  failure, which is what you want. Without it a stale mixin is silently
  skipped.
- Register the config in `fabric.mod.json`:

```json
"mixins": [
  "mymod.mixins.json",
  { "config": "mymod.client.mixins.json", "environment": "client" }
]
```

On 1.21.11 and older (remapping Loom) the build generates a refmap
automatically. Do not hand-write refmaps.

## Client mixin example

```java
@Mixin(Gui.class)   // Mojang-style name on 26.x; use the project's names
public abstract class GuiMixin {
    @Inject(method = "render", at = @At("TAIL"))
    private void mymod$afterRender(CallbackInfo ci) {
        MyHooks.onGuiRendered();   // keep the logic outside the mixin
    }
}
```

Before using this, check whether `HudElementRegistry` already covers it: a
HUD overlay almost never needs a mixin. The class and method names above are
illustrative; read the real signatures from the sources for the project's
version.

## Rules of thumb

- Name added members `mymod$name`.
- Keep handlers short; delegate to normal classes.
- Handler signatures must match the target: the injected parameters first
  (as in the target), then `CallbackInfo` / `CallbackInfoReturnable<T>`. A
  mismatch is a startup error, not a compile error.
- Shadow fields/methods with `@Shadow` instead of reflection.
- Mixins cannot add non-private static members or public API. Put those in a
  normal class.
- One feature should touch as few target classes as possible.
