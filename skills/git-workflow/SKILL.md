---
name: git-workflow
description: >-
  The user's git workflow: one git worktree per branch, short-lived feat/*
  branches, small conventional commits, rebase-only merges, and the gh CLI when
  available. Use whenever starting new work in a repo, creating or naming a
  branch, committing, opening or merging a pull request, cleaning up after a
  merge, or whenever the user mentions git, worktree, branch, commit, PR,
  rebase, or merge. Apply it even when the user does not mention these rules,
  because they are the default for every repo.
---

# Git workflow

These are the user's standing rules. Follow them without being asked.

## Rules

1. **Always use a worktree** for new work. Do not switch branches inside the
   main checkout.
2. **Branches are `feat/<short-name>`** (kebab-case, a few words). Use the
   conventional-commit type as the prefix when the work is not a feature
   (`fix/`, `docs/`, `chore/`, `refactor/`).
3. **Branches are short-lived.** One focused change per branch. Merge it soon
   and delete it; do not let branches accumulate or drift from the base.
4. **Conventional commits**, and **small ones.** Commit as you go, one logical
   change per commit, instead of one big commit at the end.
5. **Never merge-commit and never squash. Always rebase-merge.** History stays
   linear and every small commit is preserved.
6. **Use the `gh` CLI when it is available** (`command -v gh`) for pull requests
   and merging. Otherwise fall back to plain git.
7. **Remove a worktree only after its content is merged.**

## Starting work

```bash
git fetch --prune
git worktree add ../<name> -b feat/<name> origin/main
cd ../<name>
```

- Base the branch on the up-to-date default branch (`origin/main`, or `main`
  when there is no remote).
- Worktrees live next to the project checkout (`../<name>`), named after the
  branch without its prefix, so they stay in the projects directory and out of
  the repo.
- `git switch <branch>` only moves within a worktree. To work on an existing
  branch, add a worktree for it (`git worktree add ../<name> <branch>`); a
  branch can be checked out in only one worktree at a time.
- `git worktree list` shows what exists.

## Committing

```bash
git add <path> [<path>...]     # name files; avoid `git add -A` / `.`
git commit -m "<type>(<scope>): <summary>"
```

- Stage explicit paths so stray files (secrets, build output, scratch work)
  never get committed. Check `git status` and `git diff --staged` first.
- Format: `<type>(<scope>): <imperative summary>`, scope optional, summary
  under about 72 characters. Types: `feat`, `fix`, `docs`, `refactor`, `test`,
  `chore`, `build`, `ci`, `perf`, `style`. Breaking change: `feat!:` or a
  `BREAKING CHANGE:` footer.
- Add a body only to explain why. Follow any commit attribution lines the
  environment asks for.
- Keep commits small: if the message needs "and", split it. Use `git add -p`
  to separate unrelated hunks.

## Publishing and merging

Pushing, opening a PR, and merging are visible to others, so do them when the
user asks (or has said to). When asked:

```bash
git push -u origin feat/<name>
gh pr create --fill                 # gh available
gh pr merge --rebase --delete-branch    # never --squash, never --merge
```

- To pick up new commits from the base, **rebase** the branch
  (`git fetch --prune && git rebase origin/main`), never merge the base in.
  After a rebase of a pushed branch, push with `git push --force-with-lease`.
- If the repo's settings disallow rebase merges, say so rather than falling
  back to squash or a merge commit.

## Cleaning up (only after the merge)

Verify the content is merged first. Rebase-merging rewrites commit hashes, so
`git branch --merged` will not show the branch as merged; check the PR instead:

```bash
gh pr view feat/<name> --json state -q .state   # expect MERGED
git fetch --prune
git worktree remove ../<name>        # refuses if there are uncommitted changes
git branch -D feat/<name>            # -D is needed after a rebase merge
git worktree prune
```

Without `gh`, confirm on the remote that the commits are on the default branch
(for example `git fetch --prune && git cherry origin/main feat/<name>` shows no
`+` lines). If the worktree is dirty or the branch is not merged, stop and tell
the user instead of forcing removal.

## Useful commands

- `git fetch --prune`: update remotes and drop deleted remote branches.
- `git worktree add ../<name> -b feat/<name> origin/main`: new worktree.
- `git worktree list` / `git worktree remove ../<name>` /
  `git worktree prune`.
- `git switch <branch>`: switch branches within a worktree.
- `git add <path>` then `git commit -m "..."`.
- `git rebase origin/main`: update a branch.
- `git status -sb`, `git log --oneline -10`, `git diff --staged`.
