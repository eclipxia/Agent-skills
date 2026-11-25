# API map: "I want to do X" → use this

Names below are the **Mojang-style (unobfuscated) names used by the docs for
26.x**. On 1.21.11 and older with Yarn, the same ideas exist under Yarn names
(e.g. `Text` for `Component`, `MinecraftClient` for `Minecraft`, `Registries`
for `BuiltInRegistries`). Confirm exact signatures against
`https://docs.fabricmc.net/<version>/develop/` (replace `<version>` using the
docs' version selector; the unversioned URL is the newest).

Docs paths are relative to `https://docs.fabricmc.net/develop/`.

## Contents
- Client features
- Events worth knowing
- Registering content with client assets (item, block, entity checklists)
- Data generation
- Things with no Fabric API hook (mixin candidates)

## Client features

- Draw on the HUD
  - Fabric API / approach:
    `HudElementRegistry.attachElementBefore/After(VanillaHudElements.X, id,
    element)`; element is `(graphics, deltaTracker) -> ...`. Use
    `deltaTracker.getGameTimeDeltaPartialTick(false)` for tick-synced animation,
    `Util.getMillis()` for wall-clock
  - Docs page: `rendering/hud`
- Custom screen
  - Fabric API / approach: Extend `Screen`; build widgets in `init()` with
    `addRenderableWidget`; override the render-state extraction method and call
    `super`; open with `Minecraft.getInstance().gui.setScreen(...)`
  - Docs page: `rendering/gui/custom-screens`, `rendering/gui/custom-widgets`
- Server-synced GUI (inventory-like)
  - Fabric API / approach: Menu + client screen pair
  - Docs page: `blocks/container-menus`
- Keybinding
  - Fabric API / approach: `KeyMapping.Category.register(id)`,
    `KeyMappingHelper.registerKeyMapping(new KeyMapping(...))`; poll in
    `ClientTickEvents.END_CLIENT_TICK` with `while (key.consumeClick())`; inside
    screens use `ScreenKeyboardEvents.beforeKeyPress`
  - Docs page: `key-mappings`
- Client-side command
  - Fabric API / approach: `ClientCommandRegistrationCallback.EVENT` +
    `ClientCommands.literal(...)` (no server involved, works on any server)
  - Docs page: `commands/basics`
- Chat / text
  - Fabric API / approach: `Component.literal`, `Component.translatable(key,
    args)`, `.withStyle(ChatFormatting...)`; strings go in `lang/en_us.json`
  - Docs page: `text-and-translations`
- React to ticks, world join/leave, screens opening
  - Fabric API / approach: Client events: `ClientTickEvents`,
    `ClientPlayConnectionEvents`, `ScreenEvents`
  - Docs page: `events/`
- Draw in the 3D world
  - Fabric API / approach: `LevelExtractionEvents` / `LevelRenderEvents` hooks,
    optional custom `RenderPipeline`. Collect data during extraction, draw from
    immutable render state
  - Docs page: `rendering/world`
- Render a block entity
  - Fabric API / approach: `BlockEntityRenderer<T, S>` +
    `BlockEntityRenderers.register(type, Renderer::new)` in the client
    initializer
  - Docs page: `blocks/block-entity-renderer`
- Render a custom entity
  - Fabric API / approach: model layer via
    `ModelLayerRegistry.registerModelLayer`, renderer via
    `EntityRenderers.register(type, Renderer::new)`; copy entity data into a
    render state in `extractRenderState`
  - Docs page: `entities/first-entity`
- Custom particle
  - Fabric API / approach: Register `FabricParticleTypes.simple()` in common
    init; client `ParticleProviderRegistry.getInstance().register(type,
    Provider::new)`; `assets/<id>/particles/<name>.json`
  - Docs page: `rendering/particles/creating-particles`
- Client ↔ server messages
  - Fabric API / approach: Payload record implementing `CustomPacketPayload`
    with a `StreamCodec`; register types via `PayloadTypeRegistry` (common
    init); receive with `ClientPlayNetworking.registerGlobalReceiver` (client
    init). Validate everything on the server
  - Docs page: `networking`
- Sounds
  - Fabric API / approach: `SoundEvent` + `sounds.json`; dynamic sounds have
    their own page. Play from the logical server for world sounds
  - Docs page: `sounds/using-sounds`, `sounds/custom`, `sounds/dynamic-sounds`
- Item appearance (models, tinting, conditionals)
  - Fabric API / approach: Client item definition JSON under
    `assets/<id>/items/`
  - Docs page: `items/item-models`, `items/item-appearance`
- Config screen / Mod Menu integration
  - Fabric API / approach: Not covered by the Fabric docs; Mod Menu and config
    libraries are third-party. Ask the user which library they want before
    adding a dependency
  - Docs page: n/a

## Events worth knowing

Fabric API events are `Event<T>` fields on callback interfaces:
`SomeCallback.EVENT.register(...)`. Return values: callbacks returning
`InteractionResult` generally continue to the next listener on `PASS` and stop
otherwise. The docs state events often substitute for mixins. Before writing a
mixin, search the Fabric API for an `Event` covering the hook point, such as
client lifecycle, tick, screen, rendering, world render, item group, tooltip,
and player interaction events. If none exists, the docs' recommended approach is
a small mixin that fires **your own custom event**
(`EventFactory.createArrayBacked(...)`), see `references/mixins-last-resort.md`.

## Registering content (with the client assets people forget)

**Item** (`items/first-item`):
- Create `ResourceKey<Item>` with `ResourceKey.create(Registries.ITEM, id)`,
  build with `Item.Properties` plus `.setId(key)`, then
  `Registry.register(BuiltInRegistries.ITEM, key, item)`.
- Static registration classes need a dummy `initialize()` called from
  `ModInitializer` so the class loads.
- Creative tab:
  `CreativeModeTabEvents.modifyOutputEvent(CreativeModeTabs.X).register(tab ->
  tab.accept(item))`.
- Assets: `assets/<id>/models/item/<name>.json`, `assets/<id>/items/<name>.json`
  (client item definition pointing at the model), texture PNG, lang key
  `item.<id>.<name>`.
- `appendHoverText` is deprecated; use data components.

**Block** (`blocks/first-block`):
- Same key pattern; blocks with items need the block-item id and both
  registrations.
- Assets: `blockstates/<name>.json`, `models/block/<name>.json`, item
  definition, texture, lang `block.<id>.<name>`; server data:
  `loot_table/blocks/<name>.json`, tool tags under
  `data/minecraft/tags/block/mineable/`.

**Entity** (`entities/first-entity`): register type + default attributes in
common code; renderer, model layer, texture in the client initializer. Render
state pattern for 26.x: entity data is copied into a render state during
extraction, the renderer reads only the state.

## Data generation

Datagen produces JSON (models, lang, loot, recipes, tags) from Java so you don't
hand-write dozens of files. Setup (`data-generation/setup`): `fabricApi {
configureDataGeneration() { client = true } }` in Gradle, a
`DataGeneratorEntrypoint` registered under `"fabric-datagen"` in
`fabric.mod.json`, run `runDatagen`, output lands in `src/main/generated`.
Provider pages exist for translations, block/item models, loot tables, recipes,
tags, advancements. For a client-only mod, translations and item/block model
providers are the relevant ones. For a handful of files, handwriting JSON is
fine.

## Things with no Fabric API hook (mixin candidates)

Verify this on the docs and in the current Fabric API before accepting it. Known
examples: the draw call of a custom world-render pipeline in 26.3 (docs ship a
mixin for it), modifying private vanilla rendering internals, changing behavior
inside a vanilla method with no event. Anything on that list goes through the
decision ladder in `SKILL.md` before a mixin is written.
