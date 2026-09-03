---
name: worktree-cleanup
description: >
  Clean up git worktrees safely. Use when the user asks to "clean up worktrees",
  "remove old worktrees", "prune worktrees", "delete finished worktrees", or
  "tidy .claude/worktrees". Always dry-runs first and shows which worktrees are
  safe to delete versus which are kept because they have uncommitted changes or
  unpublished commits. Deletes only the worktrees the user approves, one path at
  a time, re-checking each for safety before it goes.
allowed-tools:
  - Bash
  - AskUserQuestion
---

# /worktree-cleanup

One bash script does the work. It has two modes: a **dry run** that classifies
every linked worktree, and a **remove** mode that deletes only the exact paths
you name — re-checking each one first. The script deletes nothing on its own.

Paths below are relative to the plugin; the script itself takes `--repo` and
defaults to the repo containing the current directory.

## The rule this enforces

A worktree is **kept, never a delete candidate**, when it has any of:

- **Uncommitted changes** — modified tracked files *or* untracked files.
- **Unpublished commits** — commits not reachable from any remote-tracking
  branch. If the repo has no remote at all, every worktree is kept (nothing can
  be verified as published).
- **A lock.**

Everything else — clean working tree, HEAD already on a remote — is a `REMOVE`
candidate. The user still approves each one before anything is deleted.

## 1) Dry run — classify everything

Run this first, every time. It deletes nothing.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-cleanup.sh"
```

Add `--repo PATH` to target a repo other than the current directory:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-cleanup.sh" --repo ~/some/repo
```

Output is a table, one row per linked worktree:

| VERDICT | meaning |
|---|---|
| `REMOVE` | clean and fully published — safe to delete once approved |
| `KEEP` | has uncommitted changes, unpublished commits, a lock, or its status could not be read (fail-closed) |
| `PRUNABLE` | the worktree's directory is already gone from disk — clear the stale admin entry with `--prune` |

The primary worktree is never listed as a candidate.

## 2) Approve with the user

Show the `REMOVE` rows and the `KEEP` rows with their reasons. Ask which of the
`REMOVE` candidates to delete — use `AskUserQuestion` with the candidate paths as
options (multi-select). **Delete only what the user picks.** Do not delete a
`KEEP` worktree; that is the whole point of the skill.

## 3) Remove the approved ones

Pass one `--remove` per approved path. The script re-classifies each path and
refuses it if it turned unsafe since the dry run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-cleanup.sh" \
  --remove .claude/worktrees/fresh-review-skill-error-92ed84 \
  --remove .claude/worktrees/fresh-review-v0-6-1-release-690cb9
```

Per-path result lines: `REMOVED`, `REFUSED` (was `KEEP`), `SKIPPED` (not a
worktree, or `PRUNABLE`), `FAILED`. Exit `0` only if every named path was
removed; `1` if any was refused, skipped, or failed.

To clear stale entries for worktrees whose directories are already gone:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-cleanup.sh" --prune
```

## Options

| flag | effect |
|---|---|
| `-C, --repo PATH` | repo to operate on (default: the current directory's repo) |
| `--remove PATH` | delete this worktree; repeatable; only named paths are ever touched |
| `--prune` | also run `git worktree prune` — clears admin entries for directories already gone |
| `--force` | let `--remove` delete a `KEEP` worktree — **discards uncommitted changes and unpublished commits**. Never overrides the primary-worktree refusal. |

## Safety model

State these to the user when they hesitate — they are guarantees of the script:

- **Dry run by default.** With no `--remove`, the script only reports. It cannot
  delete anything.
- **Only named paths are touched.** `--remove` acts on exactly the paths given,
  nothing discovered. There is no "remove all".
- **Every removal is re-checked.** A path that became dirty or grew an
  unpublished commit between the dry run and the remove is `REFUSED`, not deleted.
- **Fail closed.** If `git status` errors on a worktree, it is kept, never
  assumed clean.
- **The primary worktree is never removable**, not even with `--force`.
- **`--force` is the only way to delete a `KEEP` worktree**, and it says loudly
  what it discarded.
- **"Published" is judged against *local* remote-tracking refs, not the live
  remote.** The script never touches the network. If a branch was deleted or
  rewound on the real remote but your stale `refs/remotes/…` still points at those
  commits, they read as published and become a `REMOVE` candidate. Run
  `git fetch --prune` first when that gap matters; the dry-run output says this too.
- **Untracked work is always seen**, regardless of your `status.showUntrackedFiles`
  config. The dirty check forces `--untracked-files=all`, so a worktree holding
  only untracked files is `KEEP`, never silently removed under a `no` setting.
- **Gitignored local files force a `KEEP`.** A `.env`, a local database, or a build
  cache is not a tracked change, so git calls the tree clean — but those files are
  backed up nowhere, so a worktree carrying them is kept with reason `has ignored
  local files (e.g. .env/build); --force to discard`. Because `--remove` only ever
  touches the paths you name, `--force --remove <that path>` drops exactly that one
  worktree (handy for a stale `node_modules` checkout) without endangering any other.
- **Locked worktrees are a `KEEP` too, and `--force` removes them** — the script
  passes git the second `--force` a lock requires, so you never have to unlock by
  hand first.

## Gotchas

- **"Unpublished" is measured against *all* remote-tracking branches, not the
  upstream.** The check is `git rev-list --count <HEAD> --not --remotes`. A
  detached-HEAD worktree sitting on a commit that was merged to `origin/main`
  under a different branch name reads as `0 unpublished` and is a safe `REMOVE` —
  verified against three real detached worktrees whose HEADs were merge commits
  already on `origin`.
- **No remote at all ⇒ everything is kept.** With no remotes, `--not --remotes`
  excludes nothing, so the ahead-count equals the whole history and every
  worktree is `KEEP  no remote to verify against`. That is deliberate fail-safe,
  not a bug — verified on a fixture repo with `origin` removed.
- **A stale remote-tracking ref can mislabel work as published.** The check reads
  local `refs/remotes/…`, which only move on `git fetch`. A branch force-pushed or
  deleted on the remote leaves a stale local ref, and a worktree on those commits
  then reads `clean, fully published` even though the work is no longer on the
  remote. `git fetch --prune` before the dry run closes the window; the tool never
  fetches on its own because a cleanup command should have no network side effects.
  The same "only as fresh as the last fetch" caveat, plus a shallow clone or grafts
  altering reachability, is the one narrow case where a detached-HEAD worktree's
  commits could be miscounted — `git fetch` and a full (non-shallow) clone remove it.
- **Untracked files count as "dirty" — and the check ignores your git config.**
  A worktree clean on tracked files but holding an untracked scratch file is
  `KEEP`. The status probe forces `--untracked-files=all`, so this holds even
  when the repo or global config sets `status.showUntrackedFiles=no` — without
  that flag both the check *and* `git worktree remove` would honor the config and
  silently drop the file. Verified: an untracked-only worktree under `-uno` still
  classifies `KEEP  dirty` and is refused.
- **A deleted worktree directory becomes `PRUNABLE`, not `REMOVE`.** Once the
  directory is gone from disk, `git worktree remove` errors with "gitdir file
  points to non-existent location"; the fix is `--prune`, which the `--remove`
  path tells you to use rather than failing silently.
- **The primary worktree is filtered by physical path**, resolved with `pwd -P`,
  so a symlinked or `~`-relative `--repo` still matches and is never offered for
  deletion.
- **Inherited `GIT_*` routing is dropped at startup.** `GIT_DIR`, `GIT_WORK_TREE`,
  `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, and `GIT_OBJECT_DIRECTORY` are unset before any
  git call, so a status read can't be pointed at a different index than the worktree
  being deleted. Target a repo with `--repo`, never by exporting `GIT_DIR`.
- **`assume-unchanged` / `skip-worktree` can hide a modified tracked file.** Those
  index bits tell git to ignore a file's changes, so a worktree edited only through
  such a file reads clean and is removable. That is a deliberate power-user setting;
  if you use it, clear it before cleaning up (`git update-index --no-assume-unchanged`).
- **A worktree path containing a newline, tab, or quote is not parsed.** git quotes
  such paths in `--porcelain`, which the plain-text `sed`/`awk` matching does not
  decode. Ordinary paths (including spaces) are fine; pathological ones are simply
  never matched, so they are left alone rather than mis-targeted.
- **Written for bash 3.2** (macOS `/bin/bash`): no associative arrays, no
  `mapfile`. The porcelain block for one worktree is pulled with an `awk`
  paragraph-mode match on the exact `worktree <path>` line.

## Troubleshooting

- **`REFUSED ... dirty` on a worktree you thought was done**: it has uncommitted
  or untracked files. Commit, stash, or discard them in that worktree, then
  re-run the dry run. Only use `--force` if you truly mean to throw the work away.
- **`REFUSED ... N unpublished commit(s)`**: push that worktree's branch (or
  confirm the commits are merged to a remote branch), then re-run. The count is
  how many commits are not on any remote.
- **`SKIPPED ... not a worktree of this repo`**: the path was mistyped or belongs
  to another repo. Copy the exact path from the dry-run table.
- **`SKIPPED ... worktree directory is gone`**: the directory was deleted by
  hand. Run with `--prune` to clear the stale entry.
