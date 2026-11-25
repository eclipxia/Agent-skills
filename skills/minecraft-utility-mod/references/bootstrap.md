# Bootstrapping a new utility client

Build the smallest framework that makes the first module cheap to write, then
grow it. Order matters: each step is usable on its own. The skeletons are
deliberately minimal and written for Mojang-style names on Minecraft 26.x
(project from the Fabric template generator); compile-check them and adapt to
the project's version and style. Package `pkg` and class `Client` below are
placeholders.

## Contents
- Step 0: project
- Step 1: event bus
- Step 2: settings
- Step 3: modules and the manager
- Step 4: the first hook (a mixin that posts an event)
- Step 5: first module, then grow
- What to add next, in order

## Step 0: project

1. Generate the project from <https://fabricmc.net/develop/template/> for the
   target Minecraft version (see `fabric-mod`, `references/project-setup.md`).
   Prefer split source sets, or at least keep client classes out of common
   code.
2. `fabric.mod.json`: `"environment": "client"`, a `client` or `main`
   entrypoint, and a client mixin config declared with
   `{ "config": "<id>.mixins.json", "environment": "client" }`.
3. Optional dependencies you only compile against (a renderer mod, say) get
   their own mixin config and must not be required at runtime.
4. Add JUnit 5 for tests of pure logic. Lombok is optional; the reference
   client uses it, a new one need not.
5. A `Client` main class with static singletons for the managers (created in
   field initializers in dependency order), a `NAME`/`MOD_ID`/`VERSION`, and a
   logger.

## Step 1: event bus

```java
public interface Event {}

public interface Listener<T extends Event> { void call(T event); }

public interface Handler {
    default boolean listening() { return true; }
}

@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.FIELD)
public @interface Subscriber {
    Priority value() default Priority.NORMAL;
}

public enum Priority { LOWEST, LOW, NORMAL, HIGH, HIGHEST }
```

`EventManager` keeps `Map<Class<?>, List<Entry>>` (concurrent, copy-on-write
lists). `register(Handler)` walks the handler's class and superclasses, finds
fields annotated `@Subscriber` of type `Listener<E>`, resolves `E` from the
field's generic type, and stores `(handler, listener, priority)` sorted by
priority descending (stable). `post(event)` looks up by `event.getClass()` and
calls only entries whose `handler.listening()` is true. Core events to start:
`GameTickEvent(phase)`, `HudRenderEvent(graphics, deltaTracker)`, a keyboard
and mouse event, a packet event with a `cancelled` flag, and a 3D render
event.

## Step 2: settings

```java
public abstract class AbstractSetting<T> {
    protected final String name, description;
    protected final T defaultValue;
    protected T value;
    private BooleanSupplier visibility;

    // ctor sets value = defaultValue
    public T getValue() { return value; }
    public void setValue(T v) { value = v; }
    public abstract boolean setFromText(String text);   // commands, GUI
    public abstract JsonElement toJson();               // configs
    public abstract void fromJson(JsonElement json);    // tolerant, clamped
    public boolean isVisible() {
        return visibility == null || visibility.getAsBoolean();
    }
    public <S extends AbstractSetting<T>> S visibleIf(BooleanSupplier c) { ... }
}
```

Start with `BooleanSetting`, a numeric setting with min/max/step, a
`ModeSetting<E extends Enum<E>>`, and a bind/key setting; add string, color
and registry-list settings when a module needs them. Make `fromJson` ignore
bad or unknown values and clamp to bounds, from day one, since saved configs
outlive code. Leave a hook for locking a setting to a value (used later by
server restrictions) by routing reads through `getValue()`.

## Step 3: modules and the manager

```java
public abstract class AbstractModule implements Handler {
    protected final String name;
    protected final ModuleCategory category;
    protected String description = "";
    private boolean enabled;
    private int bind;
    private final List<AbstractSetting<?>> settings = new ArrayList<>();

    protected AbstractModule(String name, ModuleCategory category) { ... }

    @Override public boolean listening() { return enabled; }

    protected <S extends AbstractSetting<?>> S addSetting(S s) {
        settings.add(s);
        return s;
    }

    public abstract void onEnable();
    public abstract void onDisable();

    public void setEnabled(boolean value) {
        if (enabled == value) return;
        enabled = value;
        if (value) onEnable(); else onDisable();
    }
    public String getSuffix() { return ""; }
}
```

`ModuleManager` stores modules in a `LinkedHashMap<Class, AbstractModule>`
(insertion order = GUI order), `register(module)` puts it in the map and calls
`EVENT_MANAGER.register(module)`, and offers `getModule(Class)` and
`getModule(String name)` (case- and space-insensitive). Categories:
combat, movement, player, visual, misc, core (settings of the client itself),
and hud if HUD elements are modules.

Keybinds: register the toggle key with Fabric API's key mapping helper, or
poll raw keyboard events from the input event; support toggle and hold modes.
Keep client-wide keys (open GUI) as modules in `core`.

## Step 4: the first hook

Prefer a Fabric API event if one fits (`ClientTickEvents`, HUD element
registry, key mappings, client lifecycle). Use it to post to the bus:

```java
ClientTickEvents.START_CLIENT_TICK.register(
    c -> Client.EVENT_MANAGER.post(new GameTickEvent(Phase.START)));
```

Only when Fabric API has no hook, write a minimal mixin following
`fabric-mixin`: one injection at a method boundary that posts the event and,
for cancellable events, reads the flag back. Register it in the client mixin
config with `"injectors": { "defaultRequire": 1 }`.

## Step 5: first module, then grow

Write a trivial module (a tick listener that logs, or a HUD text). Confirm in
`runClient` that it registers, toggles, and stops listening when disabled.
Then use `recipes.md` for each addition.

## What to add next, in order

1. **GUI**: a Click GUI screen that lists modules by category, toggles them,
   and edits settings by type. It reads only the module and setting
   interfaces, so it never needs changes when modules are added.
2. **Config persistence**: save enabled state, bind and settings as JSON under
   the game directory in a `<modid>/` folder, load on client start, save on
   stop. Keep `fromJson` tolerant.
3. **Chat commands**: a Brigadier dispatcher on a prefix (intercepted from the
   chat screen), plus an auto-generated per-module settings command.
4. **HUD elements**: a module subtype with anchor/offset and an editor screen.
5. **Notifications and chat helpers**: one `ChatUtil`-style class for client
   messages with a consistent tag.
6. **Components**: rotation, inventory, targeting, render controllers when two
   modules need the same resource. Create each when the second user appears,
   not before.
7. **Restrictions**: per-server blocked modules and locked settings.
8. **Changelog**: structured file plus the GUI markers for new and changed
   modules and settings.
9. **CI**: `./gradlew build` on push and pull request with the project's JDK.
