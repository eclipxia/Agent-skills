# Project setup, build, and porting

## Contents
- Starting a project
- Version matrix (what to expect)
- fabric.mod.json for a client-only mod
- Split source sets
- Build, run, troubleshoot
- Porting between Minecraft versions

## Starting a project

Use the Fabric Template Mod Generator at
<https://fabricmc.net/develop/template/> (it has an "Enable Data Generation"
option and a split client source set option). Manual alternative: clone
`FabricMC/fabric-example-mod`, delete `.git`, edit `gradle.properties`
(`maven_group`, `archive_base_name`) and `fabric.mod.json`. The docs say to take
the current Minecraft, Loader, and Loom versions from the develop site. Don't
invent version numbers; read them from the generator or the example mod for the
target version.

## Version matrix (as of the 26.3 docs; verify, this ages quickly)

- 26.1+ (docs default 26.3)
  - Loom plugin: `net.fabricmc.fabric-loom`
  - Names: Unobfuscated, Mojang-style; no mappings dependency
  - Java: 25
- 1.21.11 and older
  - Loom plugin: `net.fabricmc.fabric-loom-remap` (legacy id `fabric-loom`)
  - Names: Yarn (maintenance ended at 26.1) or Mojang via
    `loom.officialMojangMappings()`
  - Java: 21 on 1.21.x

The 26.3 docs' example `fabric.mod.json` depends on `fabricloader >=0.19.0`,
`minecraft 26.3`, `java >=25`, and a matching `fabric-api`. Copy the Fabric API
version string from the template, since it embeds the Minecraft version (`<api
version>+<mc version>`).

## fabric.mod.json for a client-only mod

Mandatory fields: `schemaVersion` (always `1`), `id`, `version`.

```json
{
  "schemaVersion": 1,
  "id": "mymod",
  "version": "${version}",
  "name": "My Mod",
  "environment": "client",
  "entrypoints": {
    "client": ["com.example.mymod.client.MyModClient"]
  },
  "mixins": [
    { "config": "mymod.client.mixins.json", "environment": "client" }
  ],
  "depends": {
    "fabricloader": ">=<from template>",
    "minecraft": "<target version>",
    "java": ">=<from template>",
    "fabric-api": "*"
  }
}
```

Notes:
- `"environment": "client"` makes the loader skip the mod on dedicated servers.
  Drop it only if the mod ships server logic too.
- Entrypoint keys: `main` (`ModInitializer`), `client` (`ClientModInitializer`,
  runs after main), `server`, and `fabric-datagen`. A client-only mod may need
  only `client`, but assets-only registrations (items/blocks/particle types)
  must be registered from code that runs on both sides, so keep those in a
  `main` entrypoint if you register content.
- Omit `mixins` entirely when you have none. Don't add an empty mixin config
  "just in case".
- `accessWidener` / class tweaker is referenced from here when used.
- Version ranges use Fabric's SemVer superset; the part after `+` is ignored in
  comparisons.
- `"fabric-api": "*"` is fine to start; tighten to the minimum version you
  actually use before publishing.

## Split source sets

Optional but recommended for client mods. Needs Minecraft 1.18+ (1.19+
recommended), Loader 0.14+, Loom 1.0+. The generator can set it up. By hand:

```groovy
loom {
    splitEnvironmentSourceSets()
    mods {
        "mymod" {
            sourceSet sourceSets.main
            sourceSet sourceSets.client
        }
    }
}
```

Then client code (`src/client/java`) can see `main`, but `main` can't see client
classes. Compile errors become your guard against server crashes. Client
resources like assets can live in either source set; mixin configs for client
mixins are usually in `src/client/resources`.

## Build, run, troubleshoot

```bash
./gradlew build                          # compile + jar (build/libs/)
./gradlew runClient                      # launch dev client
./gradlew runDatagen                     # if datagen is configured
./gradlew build --refresh-dependencies   # fixes stale Loom/dependency caches
```

Loom caches live in `${GRADLE_USER_HOME}/caches/fabric-loom`,
`.gradle/loom-cache`, and `build/loom-cache`. Use `./gradlew genSources` (see
`getting-started/generating-sources`) to get readable Minecraft sources in the
IDE. This is how you find the right hook, and how you confirm a signature when
the docs don't cover it.

## Porting between Minecraft versions

1. Read the docs' Porting section for the target version and the Fabric blog
   post for it, plus the Fabric API porting page for the relevant version
   (`porting/`, `porting/fabric-api`).
2. Update Minecraft/Loader/Fabric API/Loom/Java versions together from the
   template for the target version. Yarn → Mojang naming: Loom's
   `migrateMappings` task, or the Ravel IntelliJ plugin (also handles Kotlin).
   Expect manual fixes, **especially in mixins**.
3. **Audit every mixin first.** For each, check whether Fabric API now offers a
   hook (they get added regularly) and delete the mixin if so. This is the
   cheapest port you can do.
4. Check rendering and input code against the docs for the target version: 26.x
   moved to an extract/submit rendering model, and 26.3 changed input/window
   handling.
5. Build, run the client, exercise each feature.
