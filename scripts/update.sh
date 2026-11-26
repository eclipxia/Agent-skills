#!/usr/bin/env bash
# Update the skills: pull the latest changes (rebase), then re-run the
# installer so new skills appear and removed ones are cleaned up.
#
# Takes the same options as install.sh (pass --copy again if you installed
# with --copy), plus --no-pull to skip the git step.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pull=1
args=()

for arg in "$@"; do
  case "$arg" in
    --no-pull) pull=0 ;;
    -h|--help)
      echo "Usage: scripts/update.sh [--no-pull] [install.sh options] [skill ...]"
      echo "Pulls with rebase, then runs scripts/install.sh with the options."
      exit 0 ;;
    *) args+=("$arg") ;;
  esac
done

if [ "$pull" -eq 1 ]; then
  git -C "$repo_root" fetch --prune
  if ! git -C "$repo_root" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    echo "The current branch has no upstream to pull from." >&2
    echo "Set one (git branch --set-upstream-to=origin/main) or use --no-pull." >&2
    exit 1
  fi
  old="$(git -C "$repo_root" rev-parse HEAD)"
  git -C "$repo_root" pull --rebase --autostash
  new="$(git -C "$repo_root" rev-parse HEAD)"
  if [ "$old" = "$new" ]; then
    echo "Already up to date."
  else
    echo "Updated:"
    git -C "$repo_root" log --oneline "$old..$new"
  fi
  echo
fi

exec "$repo_root/scripts/install.sh" "${args[@]+"${args[@]}"}"
