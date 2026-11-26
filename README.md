# Agent skills

A collection of [Claude Code](https://claude.com/claude-code) skills for
building Minecraft client mods on Fabric, plus the git workflow used to
maintain them. Each skill is a folder under `skills/` with a `SKILL.md` and,
where it helps, `references/` and `scripts/` that the agent reads on demand.

## Skills

- **`fabric-mod`**: client-side Fabric mods that use Fabric API first and
  treat mixins as a last resort. Detects the project and Minecraft version,
  walks a decision ladder (API, data/assets, class tweaker, accessor, tiny
  mixin), and keeps client code out of common code. Includes an audit script
  for mixins and client-class leaks.
- **`fabric-mixin`**: how to write, register and debug a mixin once one is
  justified: injector choice, MixinExtras, accessors, class tweakers,
  interface injection, and debugging flags.
- **`minecraft-utility-mod`**: a blueprint for creating and maintaining
  utility clients: modules, settings, an event bus, Click GUI, HUD, commands,
  configs and changelog. Covers bootstrapping a new client, adding features,
  and updating across Minecraft versions.
- **`baritone-integration`**: integrating Baritone into a client (dependency,
  facade, rotation and input ownership, settings and commands), and how to
  build your own pathfinder instead.
- **`git-workflow`**: one worktree per branch, short-lived `feat/*` branches,
  small conventional commits, rebase-only merges, and `gh` when available.
- **`rusherhack-plugin`**: creating and editing plugins for the RusherHack
  client.

The Fabric skills work together: `minecraft-utility-mod` and
`baritone-integration` defer to `fabric-mod` for choosing hooks, and
`fabric-mod` hands off to `fabric-mixin` when a mixin is needed.

## Install

```bash
git clone git@github.com:eclipxia/Agent-skills.git
cd Agent-skills
scripts/install.sh
```

By default every skill is symlinked into `~/.claude/skills`, so the repo stays
the single source of truth and a pull updates them in place. Claude Code picks
them up on the next session.

Options:

- `scripts/install.sh fabric-mod git-workflow`: install only the named skills.
- `--project`: install into `./.claude/skills` of the current directory
  instead of your user directory.
- `--dest DIR`: install somewhere else (or set `CLAUDE_SKILLS_DIR`).
- `--copy`: copy the skills instead of symlinking them.
- `--force`: replace a skill that this script did not install. The old one is
  moved to `<dest>.bak/` (outside the skills directory, so it never loads).

The installer never overwrites something it did not put there unless you pass
`--force`, is safe to re-run, and removes its own installs of skills that have
been deleted from the repo.

The scripts are bash. On Windows, use WSL or Git Bash (symlinks need
developer mode, or use `--copy`).

## Update

```bash
scripts/update.sh
```

This fetches, pulls with rebase (stashing local changes first), prints the new
commits, then re-runs the installer so new skills appear and removed ones are
cleaned up. It takes the same options as the installer, so pass `--copy`
again if you installed with it, and `--no-pull` to only re-run the install.

## Layout

```
skills/<name>/SKILL.md        the skill (frontmatter + instructions)
skills/<name>/references/     longer docs the agent reads when needed
skills/<name>/scripts/        helper scripts the skill can run
scripts/install.sh            install the skills
scripts/update.sh             pull and reinstall
```

A directory under `skills/` is only a skill if it has a `SKILL.md`.

## Adding or changing a skill

- Write `SKILL.md` with `name` and `description` frontmatter. The description
  decides when the skill triggers, so say what it does and when to use it,
  including phrases a user might actually type.
- Keep `SKILL.md` short and move detail into `references/`, with pointers
  saying when to read each file.
- Wrap markdown at 80 columns.
- Skills that mention `~/git/magnum` refer to a private local project as an
  optional reference. They are written to work without it.
- Follow the `git-workflow` skill when changing this repo: small conventional
  commits, no co-author trailers.
