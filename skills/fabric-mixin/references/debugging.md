# Debugging mixins

Mixin errors surface when the target class loads, not at compile time. Read
the full stack trace in `run/logs/latest.log` (and `run/crash-reports/`): the
first "Caused by" usually names the mixin, the handler, and what failed.

## Contents
- JVM flags worth knowing
- Seeing what the mixin actually did
- Common failures
- General checklist

## JVM flags worth knowing

Add them as JVM arguments of the run configuration (for example in the Loom
`runs` block or the IDE run configuration):

- `-Dmixin.debug.export=true`: write the post-mixin bytecode of every target
  to `<run dir>/.mixin.out/`, in package/class layout. When a decompiler is
  available it also decompiles them. This is the best way to see what your
  mixin did to the class.
- `-Dmixin.debug.export.filter=...`: restrict export to matching class names
  (`*`, `**`, `?`). Export is slow, so filter.
- `-Dmixin.debug.verbose=true`: show debug-level Mixin messages at INFO.
- `-Dmixin.debug.countInjections=true`: make failed injections errors.
- `-Dmixin.dumpTargetOnFailure=true`: dump the un-mixed target class when a
  mixin fails, so you can inspect it with `javap`.
- `-Dmixin.debug=true`: enables the debug options together.

Source: the SpongePowered Mixin wiki's system-properties page, last edited in
2018, so a flag may have changed. If one does nothing, check the wiki.

The Fabric docs' debugging page covers loggers, breakpoints, and hotswap
(use the IDE's Debug run option, not Run). Mixin classes can be hot-swapped
only if the run configuration allows it.

## Seeing what the mixin actually did

1. Add `-Dmixin.debug.export=true` and a filter for the target class.
2. Run the client and trigger the target class loading.
3. Open the exported class under `.mixin.out/` and look for your handler call.
   If it is missing, the mixin did not apply (check the config registration
   and `environment`). If it is present in the wrong place, adjust the `@At`.

## Common failures

- **Mixin does nothing, no error.** Not registered in `fabric.mod.json`, not
  listed in the config's `mixins`/`client` array, wrong `package`, or
  `defaultRequire` unset so a missing injection point was skipped. Add
  `"defaultRequire": 1` and re-run.
- **InvalidInjectionException / "no targets found" / target method not
  found.** The method name or descriptor does not exist in this Minecraft
  version. Re-read the target in the sources (`genSources`); names changed
  between 1.21.x/Yarn and 26.x unobfuscated. Do not patch it by guessing.
- **Injector "expected N" / "0 matches" for an `@At`.** The `INVOKE` target or
  `ordinal` is wrong, or the bytecode shape changed. Re-derive from the
  sources, or move to a boundary injection or `@WrapOperation` on a unique
  call.
- **Handler signature mismatch.** Parameters must match the target's (and
  captured locals) followed by `CallbackInfo`/`CallbackInfoReturnable`. Use a
  Minecraft Development IDE plugin's inspections if available, or compare
  against the target's descriptor.
- **Crash on a dedicated server (`ClassNotFoundException` / `NoClassDefFound`
  mentioning client classes).** A client-only mixin or reference ended up in
  the common config or the common source set. Move it to the client config
  and source set.
- **Class tweaker change has no effect.** Entries with missing targets are
  silently ignored. Run `validateAccessWidener`, reload Gradle, regenerate
  sources.
- **Works in dev, fails in production (1.21.11 and older).** Refmap or
  mapping problem: confirm the project uses the remapping Loom plugin and
  that the mixin config is the one in the built jar.
- **Broke after a Minecraft update.** Open the new target in `genSources`,
  compare, and first check whether Fabric API now offers an event that makes
  the mixin unnecessary.

## General checklist

1. Is the config registered, with the right environment?
2. Does the target method exist with that exact name and descriptor in this
   version?
3. Does the handler signature match?
4. Is the mixin client-only, and in the client config?
5. Did you export the class and confirm the code landed where you expect?
