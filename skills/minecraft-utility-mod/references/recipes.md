# Recipes

Checklists for the common changes. Skeletons are shaped after Magnum's
existing code (`Sprint`, `Zoom`, `Break Highlight`, `FPS`, `Toggle`).
Confirm class names and constructor signatures against the project, which
changes.

## Contents
- New module
- New setting on an existing module
- Draw in the world or on screen
- New HUD element
- New chat command
- New event and the mixin that posts it
- Shared behavior: a controller with a SettingGroup
- Changelog entry
- Tests

## New module

1. Pick the category (`combat`, `movement`, `player`, `visual`, `misc`,
   `core`) and a user-facing name with spaces ("Break Highlight").
2. Create `features/modules/impl/<category>/<Name>Module.java`:

```java
public final class ExampleModule extends AbstractModule {
    private final Minecraft mc = Minecraft.getInstance();

    private final BooleanSetting pause = addSetting(new BooleanSetting(
            "Pause In Screens", "Stops while a screen is open.", true));
    private final FloatSetting range = addSetting(new FloatSetting(
            "Range", "How far it looks, in blocks.", 4.0f, 1.0f, 8.0f, 0.5f));

    public ExampleModule() {
        super("Example", ModuleCategory.MISC);
        this.description = "Does the example thing.";
    }

    @Override
    public void onEnable() {
    }

    @Override
    public void onDisable() {
        // Undo anything held: keys, rotations, queued actions, cached state
    }

    @Subscriber
    private final Listener<GameTickEvent> gameTickEventListener = event -> {
        if (event.phase() != GameTickEvent.Phase.START) return;
        if (mc.player == null) return;
        if (pause.getValue() && mc.gui.screen() != null) return;
        // ...
    };
}
```

3. Register it with `register(new ExampleModule());` in the right section of
   the `ModuleManager` constructor (that order is the GUI order).
4. Nothing else is needed for the GUI, config, bind, or `.example` settings
   command. Add `getSuffix()` if a mode or value should show in the module
   list.
5. If vanilla behavior must change, first see "New event" below or the
   static-hook pattern in `architecture.md`.
6. Add a changelog entry and run the verify steps in `SKILL.md`.

Notes: use `visibleIf(() -> mode.is(Mode.X))` on settings that only matter
for one mode; use `addSettings(group)` for shared groups; enum-backed
`ModeSetting` values display as "Night Vision" from `NIGHT_VISION`.

## New setting on an existing module

1. Add the field with `addSetting(new XSetting(name, description, default...))`
   and read it with `getValue()` where it matters.
2. Pick a default that preserves the old behavior, so saved configs and users
   are unaffected until they opt in.
3. Setting names are also config keys and command arguments. Renaming one
   loses saved values, so avoid it; if needed, keep the old name.
4. Changelog entry with `module` and `setting` set to the exact names.

## Draw in the world or on screen

- World shapes: listen to `Render3DEvent` and use `RenderController` (a
  shared box-drawing group, with fill/outline/color settings) via
  `addSettings(new RenderController())`. Shapes are valid for that frame only,
  so submit them every frame.
- Screen overlays: listen to `HudRenderEvent` (`graphics`, `deltaTracker`) for
  a one-off, or make a HUD element (below) when it should be movable.
- Read game state at draw time from `Minecraft.getInstance()`; copy anything
  you need across frames into your own fields. Rendering APIs follow the
  26.x extract/submit model, so see `fabric-mod`'s `references/rendering.md`.

## New HUD element

```java
public final class ExampleElement extends AbstractTextElement {
    public ExampleElement() {
        super("Example", ElementAnchor.BOTTOM_RIGHT, 2, 56);
        this.description = "Shows the example value.";
        this.setEnabled(true);
    }

    @Override
    protected String[] getLines() {
        return new String[]{
                "Example %s%d".formatted(ChatFormatting.WHITE, value())};
    }
}
```

Register it in the `/* Hud */` section of `ModuleManager`. For custom
drawing, extend `AbstractElement` and implement `getWidth()`, `getHeight()`
and `render(GuiGraphicsExtractor, DeltaTracker)`; derive animation from the
delta tracker or `System.nanoTime()`, and keep per-frame work light.

## New chat command

Module settings already have a command. Add one only for actions.

```java
public final class ExampleCommand extends AbstractCommand {
    public ExampleCommand() {
        super("example");
        this.description = "Does the example thing.";
    }

    @Override
    public void build(
            LiteralArgumentBuilder<ClientSuggestionProvider> builder) {
        builder.then(argument("name", StringArgumentType.word())
                .suggests((ctx, sug) ->
                        SharedSuggestionProvider.suggest(options(), sug))
                .executes(ctx -> {
                    String name = StringArgumentType.getString(ctx, "name");
                    ChatUtil.sendMessage("Did %s.", name);
                    return Command.SINGLE_SUCCESS;
                }));
    }
}
```

Register in the `CommandManager` constructor, before the module settings
commands (modules cannot take an existing command's name). Use `ChatUtil` for
feedback (`sendMessage`, `sendError`, `replaceMessage` for repeated updates)
and return `0` after sending an error.

## New event and the mixin that posts it

1. Add `events/impl/<area>/<Name>Event.java`: a `record ... implements Event`
   for immutable data, or a class with a `cancelled` flag if listeners can
   veto. Document when it is posted and from which thread.
2. Check Fabric API first for an existing hook; Fabric events can feed the
   same bus from a registration instead of a mixin.
3. If a mixin is needed, follow `fabric-mixin`: the smallest injection that
   works, a `mymod`-prefixed handler, registered in the right mixin config
   list (`client` for client-only classes). The body only does
   `Mhack.EVENT_MANAGER.post(new XEvent(...))` and, for cancellable events,
   reads the flag back (`ci.cancel()` or a return value).
4. Subscribe from modules with `@Subscriber Listener<XEvent>`.
5. Verify the hook fires once per occurrence, including when no module is
   listening (posting must be cheap).

## Shared behavior: a controller with a SettingGroup

When two or more modules need the same capability or the same settings
(target picking, rotations, inventory moves, drawing boxes):

1. Create `features/components/<Name>Controller.java` implementing
   `SettingGroup` with the shared settings and the logic that uses them.
2. Modules add it with `addSettings(new XController())` and call it.
3. To expose a `.x` command that sets a value across every module that has
   the group, register `SharedSettingsCommand.forGroup(...)` in
   `CommandManager`.
4. Anything that holds a shared resource (rotation, held slot, input) must
   have a release path that modules call from `onDisable()`.

## Changelog entry

For each user-visible change, update both files with the next release `id`
(or the unreleased/current one):

- `src/main/resources/assets/mhack/changelog.json`: entries typed `new`,
  `changed` or `removed`. Entries about one module need its exact name as
  `module`; entries about one setting also need the exact `setting` name.
  These drive the in-game `+` (new) and `*` (changed) markers, so a typo means
  no marker.
- `CHANGELOG.txt`: the same entries in plain text, grouped under New /
  Changed / Removed, formatted `+ Module > Setting: text`.

Write entries for players, in sentences that say what the feature does and how
its modes differ. A bad or missing name should be caught by reading the JSON
back against the module and setting names in code.

## Tests

Test pure logic (math, parsing, damage or path calculations, data
structures), not Minecraft-bound code. Put such logic in `utils/` classes with
static methods that take plain values, then test them with JUnit 5 under
`src/test/java/me/shae/...` (see `SelfSafetyTest`, `PearlFlightTest`). Run
with `./gradlew test`. Anything touching `Minecraft` instances is verified by
running the client.
