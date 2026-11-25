# Client rendering with Fabric API

Rendering code changed substantially in 26.x: drawing is split into an
**extraction** phase (copy what you need from game objects into a render state)
and a **drawing/submit** phase (draw using only that state). Older tutorials
(1.20 and earlier, `MatrixStack` + direct `VertexConsumer` calls) don't apply.
Always check `rendering/*` docs pages for the project's version. The snippets
are condensed from the 26.3 docs and show the shape of each API.

## HUD

```java
// in ClientModInitializer
HudElementRegistry.attachElementBefore(
    VanillaHudElements.CHAT,
    ExampleMod.id("before_chat"),
    HudRenderingEntrypoint::extract);
// extract signature: (GuiGraphicsExtractor graphics, DeltaTracker tickCounter)
```

- Pick the attach point (`attachElementBefore/After`) relative to a
  `VanillaHudElements` entry so layering is deliberate.
- Draw with `graphics.fill(...)`, text/sprite helpers on the graphics object;
  blend colors with `ARGB.linearLerp`.
- Animation: `deltaTracker.getGameTimeDeltaPartialTick(false)` for tick-synced,
  `Util.getMillis()` for real time. Keep per-frame work cheap, as this runs
  every frame.
- Read game state from `Minecraft.getInstance()` (player, level, options). A
  mixin isn't needed to read it.

## Screens and widgets

- Extend `Screen`. Create widgets in `init()`, not the constructor (sizes aren't
  known yet), and add with `addRenderableWidget(...)`.
- Override the render-state extraction method
  (`extractRenderState(GuiGraphicsExtractor, mouseX, mouseY, delta)` in 26.3).
  **Call `super`** or the background and widgets don't render.
- Open: `Minecraft.getInstance().gui.setScreen(new MyScreen(...))`; close:
  `setScreen(null)`.
- These are client-only screens. A screen backed by server inventory state is a
  menu + screen pair (`blocks/container-menus`).
- Opening from a key press: poll the `KeyMapping` in
  `ClientTickEvents.END_CLIENT_TICK` (see `api-map.md`).

## Key mappings

```java
KeyMapping.Category CATEGORY =
    KeyMapping.Category.register(ExampleMod.id("custom_category"));
KeyMapping key = KeyMappingHelper.registerKeyMapping(
    new KeyMapping("key.example-mod.send_to_chat",
        InputConstants.Type.KEYBOARD, InputConstants.KEY_J, CATEGORY));

ClientTickEvents.END_CLIENT_TICK.register(client -> {
    while (key.consumeClick()) { /* act */ }
});
```

Lang keys needed: the mapping name and `key.category.<id>.<name>`. Key constants
are US-layout names. Within a screen, use `ScreenEvents.BEFORE_INIT` +
`ScreenKeyboardEvents.beforeKeyPress(screen)` and `key.matches(keyEvent)`. Note:
26.3 changed input/window handling (SDL3 transition), so verify input signatures
on port.

## World rendering

Two routes (docs `rendering/world`): inject into the existing vanilla render
flow, or define your own `RenderPipeline`.

- Hooks: `LevelExtractionEvents.END_EXTRACTION` (collect data),
  `LevelRenderEvents.BEFORE_RENDER_PASS`, `LevelRenderEvents.END_MAIN`.
- Custom pipeline: register one with `RenderPipelines.register(...)`, built
  from `RenderPipeline.builder(RenderPipelines.DEBUG_FILLED_SNIPPET)` plus
  `.withLocation(...)`, `.withDepthStencilState(...)` and `.build()`; buffers
  via `StagedVertexBuffer`.
- **Known mixin exception (26.3):** the docs state Fabric API does not provide
  the render pass, so the actual draw call is done from a small
  `LevelRendererMixin`, plus a cleanup injection on `GameRenderer.close`. If the
  user wants simple overlays (outlines, boxes), check whether a vanilla debug
  renderer or existing pipeline snippet gets there without a custom pipeline
  before taking this on. When you do write it, copy the docs' mixin approach and
  keep the mixin body to "call my renderer".
- Draw only from extracted, immutable state, never from live world objects,
  which may change on another thread.

## Block entity renderers

```java
// client initializer
BlockEntityRenderers.register(
    ModBlockEntities.COUNTER_BLOCK_ENTITY, CounterBlockEntityRenderer::new);
```

- Implement `BlockEntityRenderer<T, S>` with a render-state class `S`:
  `createRenderState()`, `extractRenderState(blockEntity, state, tickProgress,
  cameraPos, crumblingOverlay)`, `submit(state, PoseStack, SubmitNodeCollector,
  CameraRenderState)`.
- Text: `collector.submitText(...)`.
- Keep the renderer in `src/client`. Never reference it from common code.

## Entity renderers

- Register the model layer: `ModelLayerRegistry.registerModelLayer(LAYER,
  Model::getTexturedModelData)`.
- Register the renderer: `EntityRenderers.register(ModEntityTypes.X,
  XRenderer::new)`.
- Renderer extends `MobRenderer<Entity, RenderState, Model>` (or the appropriate
  base); copy entity data (animation state, flags) into the render state in
  `extractRenderState`.
- The entity type, attributes, and synced data live in common code; the renderer
  is client-only.

## Particles

Common init: `Registry.register(BuiltInRegistries.PARTICLE_TYPE, id,
FabricParticleTypes.simple())`. Client init:
`ParticleProviderRegistry.getInstance().register(TYPE,
EndRodParticle.Provider::new)` (or your own provider). Assets:
`assets/<id>/particles/<name>.json` with `{"textures": ["<id>:<texture>"]}`,
textures in `assets/<id>/textures/particle/`.

## Quick debugging pointers

- Nothing renders: wrong entrypoint (client init not listed in
  `fabric.mod.json`), missing `super` call in a screen, missing asset (check
  `latest.log` for resource warnings).
- Crash on dedicated server: client class referenced from common code. Run
  `scripts/audit-client-mod.sh`.
- Works in dev, breaks after a Minecraft bump: a mixin target moved. Re-evaluate
  whether new Fabric API covers it.
