# Accessors, class tweakers, interface injection

These solve "I can't reach X" without changing any behavior. They are cheaper
and safer than an injection mixin, so use them first. Syntax is from the
Fabric docs for 26.3 (`mixins/accessors`, `class-tweakers/`). Check the docs
page for the project's version.

## Contents
- Choosing between them
- Accessors and invokers
- Class tweakers (formerly access wideners)
- Interface injection

## Choosing between them

- Private field or method on a class you can already see: **accessor or
  invoker** (no Gradle reload needed).
- The class itself is private/protected/package-private, you need to extend a
  final class, or override a final method: **class tweaker** (accessors cannot
  do this).
- You want vanilla classes to implement your interface: **interface
  injection** (a class tweaker directive).

## Accessors and invokers

An accessor mixin is an **interface** annotated `@Mixin(Target.class)` that
contains only `@Accessor` and `@Invoker` methods. Convention: name it
`XAccessor`, put it in a `mixin.accessor` subpackage, and prefix methods with
the mod id and `$`.

```java
@Mixin(Hud.class)
public interface HudAccessor {
    @Accessor("overlayMessageTime")
    int example_mod$getOverlayMessageTime();

    @Accessor("overlayMessageTime")
    void example_mod$setOverlayMessageTime(int messageTime);

    @Invoker("methodName")
    boolean example_mod$someMethod(ItemStack a, ItemStack b);
}

// use: cast the instance to the accessor interface
int t = ((HudAccessor) hud).example_mod$getOverlayMessageTime();
```

- For a `final` field, add `@Mutable` to the setter.
- If the target class is final, the compiler rejects the direct cast, so go
  through `Object`: `((TargetAccessor) (Object) instance)`.
- Accessors cannot reach private or final *classes*, or override final
  methods. Use a class tweaker for that.
- Register the interface in the mixin config like any other mixin (client
  config if the target is client-only).

## Class tweakers (formerly access wideners)

Requires Fabric Loader 0.18.0+ and Loom 1.12+ per the docs; the older name
"access widener" and the `accessWidener` key still appear. Targets vanilla
classes only. Check the project's Loom version.

File: `src/main/resources/<modid>.classtweaker`. First line is the header,
whitespace separated:

```
classTweaker v1 official
```

Comments start with `#`; one entry per line. Directives:

- `accessible`: classes and fields become public; methods become public (and
  final if they were private).
- `extendable`: classes become public and non-final; methods become non-final
  (and protected if they were private).
- `mutable`: fields become non-final.

Class entry: `accessible class net/minecraft/some/Type$Inner` (internal names
use `/` and `$`). Field and method entries also need the owner class, the
name, and the bytecode descriptor, so do not hand-write them from memory.
Generate entries with the MCDev IntelliJ plugin ("Copy / Paste Special" then
"AW Entry") or mcsrc.dev, or copy a line from the docs page.

Wire it up in two places, then reload Gradle and regenerate sources:

```groovy
// build.gradle
loom {
    accessWidenerPath = file("src/main/resources/example-mod.classtweaker")
}
```

```json
// fabric.mod.json
"accessWidener": "example-mod.classtweaker"
```

Entries that reference a missing target are **silently ignored**. Run the
`validateAccessWidener` Gradle task after editing, and after every Minecraft
update.

## Interface injection

Makes a vanilla class implement your interface at runtime, so you can call
your methods on it without casts.

1. Write the interface **outside** your mixin package. Every method must be
   `default` and prefixed with the mod id:

   ```java
   public interface BucketEmptySoundGetter {
       default Optional<SoundEvent> example_mod$getBucketEmptySound() {
           throw new AssertionError("Implemented in Mixin");
       }
   }
   ```

2. Add a class tweaker entry (target class, then your interface; the names
   here are illustrative):

   ```
   inject-interface net/minecraft/world/level/block/Block com/example/Glow
   ```

   Generics go at the end of the interface name in bytecode-signature form,
   for example `...GenericInterface<+Ljava/lang/String;[Ljava/lang/Boolean;>`.

3. If the default bodies are enough, you need no mixin. To override them for
   a class, write an abstract mixin that `implements` the interface:
   `@Mixin(Block.class) abstract class BlockMixin implements Glow { ... }`.

Injected members exist at runtime but do not show in decompiled sources, so
tell the user where the implementation lives.
