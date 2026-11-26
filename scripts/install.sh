#!/usr/bin/env bash
# Install the skills in this repo for Claude Code.
#
# By default each skill is symlinked into ~/.claude/skills, so a `git pull`
# updates them in place. Use --copy to copy instead.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$repo_root/skills"
dest="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
marker=".installed-by-agent-skills"
mode=link
force=0
names=()

usage() {
  cat <<USAGE
Usage: scripts/install.sh [options] [skill ...]

Installs every skill under skills/ (or only the named ones).

Options:
  --dest DIR   Install into DIR (default: \$CLAUDE_SKILLS_DIR or
               ~/.claude/skills)
  --project    Install into ./.claude/skills of the current directory
  --copy       Copy the skills instead of symlinking them
  --force      Replace a skill that this script did not install; the old one
               is moved to <dest>.bak/<name>.<timestamp>
  -h, --help   Show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dest) [ $# -ge 2 ] || { echo "--dest needs a directory" >&2; exit 2; }
            dest="$2"; shift 2 ;;
    --project) dest="$PWD/.claude/skills"; shift ;;
    --copy) mode=copy; shift ;;
    --force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) names+=("$1"); shift ;;
  esac
done

# Every directory under skills/ that has a SKILL.md is a skill.
available=()
for dir in "$src"/*/; do
  [ -f "${dir}SKILL.md" ] && available+=("$(basename "$dir")")
done
[ ${#available[@]} -gt 0 ] || { echo "No skills found in $src" >&2; exit 1; }

if [ ${#names[@]} -eq 0 ]; then
  names=("${available[@]}")
else
  for n in "${names[@]}"; do
    printf '%s\n' "${available[@]}" | grep -qx -- "$n" \
      || { echo "No such skill: $n (have: ${available[*]})" >&2; exit 1; }
  done
fi

mkdir -p "$dest"
installed=0 current=0 skipped=0

# True when the path was put there by this repo's installer.
is_ours() {
  local path="$1"
  if [ -L "$path" ]; then
    case "$(readlink "$path")" in "$src"/*) return 0 ;; esac
    return 1
  fi
  [ -f "$path/$marker" ] && [ "$(cat "$path/$marker")" = "$repo_root" ]
}

for name in "${names[@]}"; do
  from="$src/$name"
  to="$dest/$name"

  if [ -e "$to" ] || [ -L "$to" ]; then
    if [ "$mode" = link ] && [ -L "$to" ] && [ "$(readlink "$to")" = "$from" ]; then
      echo "ok       $name (already linked)"
      current=$((current + 1))
      continue
    fi
    if is_ours "$to"; then
      rm -rf "$to"
    elif [ "$force" -eq 1 ]; then
      # Keep backups outside the skills directory so they never load as skills
      backup_dir="${dest%/}.bak"
      mkdir -p "$backup_dir"
      backup="$backup_dir/$name.$(date +%Y%m%d%H%M%S)"
      mv "$to" "$backup"
      echo "backup   $name -> $backup"
    else
      echo "skipped  $name ($to exists and was not installed by this repo;" \
           "use --force to replace it)" >&2
      skipped=$((skipped + 1))
      continue
    fi
  fi

  if [ "$mode" = link ]; then
    ln -s "$from" "$to"
    echo "linked   $name"
  else
    cp -R "$from" "$to"
    printf '%s' "$repo_root" > "$to/$marker"
    echo "copied   $name"
  fi
  installed=$((installed + 1))
done

# Remove installs of skills that no longer exist in the repo, but only when
# installing everything and only ones this repo put there.
if [ ${#names[@]} -eq ${#available[@]} ]; then
  for entry in "$dest"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name="$(basename "$entry")"
    printf '%s\n' "${available[@]}" | grep -qx -- "$name" && continue
    if [ -L "$entry" ]; then
      case "$(readlink "$entry")" in "$src"/*) rm "$entry"; echo "removed  $name (no longer in repo)" ;; esac
    elif [ -f "$entry/$marker" ] && [ "$(cat "$entry/$marker")" = "$repo_root" ]; then
      rm -rf "$entry"; echo "removed  $name (no longer in repo)"
    fi
  done
fi

echo
echo "Done: $installed installed, $current already current, $skipped skipped."
echo "Destination: $dest ($mode mode)"
[ "$skipped" -eq 0 ] || exit 1
