#!/usr/bin/env bash
# Quick audit of a Fabric client mod project.
# Usage: audit-client-mod.sh [project-dir]
# Reports: versions, Loom flavor, source layout, entrypoints, mixin inventory,
# and client-only classes referenced from common code (dedicated-server crash risk).
set -u
dir="${1:-.}"
cd "$dir" || { echo "cannot cd to $dir"; exit 1; }

echo "== Project facts =="
if [ -f gradle.properties ]; then
  grep -E '^(minecraft_version|loader_version|fabric_version|fabric_api_version|yarn_mappings|loom_version|archives_base_name|archive_base_name|mod_version)=' gradle.properties || echo "(no standard version keys found in gradle.properties)"
else
  echo "no gradle.properties"
fi
grep -hE "id ['\"]?(net\.fabricmc\.fabric-loom(-remap)?|fabric-loom)['\"]?" build.gradle build.gradle.kts settings.gradle 2>/dev/null | head -3 || true

echo
echo "== Layout =="
[ -d src/client ] && echo "split source sets: yes (src/client)" || echo "split source sets: NO (single source set; client classes can leak into common code)"
fmj=$(find src -name fabric.mod.json 2>/dev/null | head -1)
if [ -n "$fmj" ]; then
  echo "fabric.mod.json: $fmj"
  grep -nE '"environment"|"client"|"main"|"fabric-datagen"|"accessWidener"|"classTweaker"|"mixins"' "$fmj" | head -20
else
  echo "fabric.mod.json: NOT FOUND"
fi

echo
echo "== Mixins (each one is a maintenance cost; justify or replace) =="
mixin_files=$(grep -rlE '^\s*@Mixin\b|@Mixin\(' src --include=*.java 2>/dev/null)
if [ -z "$mixin_files" ]; then
  echo "none"
else
  echo "$mixin_files" | while read -r f; do
    kinds=$(grep -ohE '@(Inject|ModifyVariable|ModifyArg|ModifyArgs|ModifyConstant|ModifyReturnValue|WrapOperation|WrapWithCondition|WrapMethod|Redirect|Overwrite|Accessor|Invoker|Shadow|Unique)\b' "$f" | sort | uniq -c | tr -s ' ' | tr '\n' ',' )
    echo "$f: $kinds"
  done
  echo
  if grep -rnE '@(Redirect|Overwrite)\b' src --include=*.java 2>/dev/null; then
    echo "^^ @Redirect/@Overwrite found: highest conflict risk; prefer @WrapOperation/@Inject or a Fabric API event."
  fi
fi

echo
echo "== Client classes referenced from common code (src/main) =="
if [ -d src/client ] && [ -d src/main/java ]; then
  # Client-only packages/classes; tweak the pattern list as needed for your version.
  pat='net\.minecraft\.client\.|net\.fabricmc\.fabric\.api\.client\.|GuiGraphics|BlockEntityRenderer|EntityRenderer|KeyMapping|ClientModInitializer|@Environment\(EnvType\.CLIENT\)'
  hits=$(grep -rnE "$pat" src/main/java 2>/dev/null)
  if [ -n "$hits" ]; then echo "$hits" | head -40; echo "^^ these will crash a dedicated server if loaded; move to src/client."; else echo "none found"; fi
else
  echo "skipped (needs split source sets). In a single source set, grep for the same client imports outside your client package."
fi
