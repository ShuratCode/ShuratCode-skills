---
name: pull-all
description: >
  Recursively find every git repo under a given path and update its main branch from
  origin (git pull, fast-forward only). Use when the user asks to "pull all repos",
  "update all my repos", "git pull everything under <path>", "sync all repos", "refresh
  main across my projects", "bring all repos up to date", or names a directory of
  checkouts to update. Reports one line per repo — updated, current, skipped, diverged,
  or failed — and never switches branches or touches a dirty working tree.
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# /pull-all

All the work is done by one script, so this skill reads a short summary instead of
streaming git output for every repo.

## 1) Establish the path

The user must give a root directory. If they did not, ask — do **not** default to
`$PWD` silently, because the wrong root either finds nothing or walks their whole home
directory.

Two things worth confirming when the root is broad (like `~`):

- **Depth.** `--depth` counts path components down to `.git`, so repos in the immediate
  children of the root need `--depth 2`. The default `4` covers `~/code/org/repo`.
- **Dry run first.** For an unfamiliar root, run with `-n` and show the user what would
  change before doing it for real.

## 2) Dry run

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pull-all.sh" --dry-run --depth 2 ~
```

This fetches (which only writes remote-tracking refs) and reports what it *would* do.
No local branch moves.

## 3) Real run

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pull-all.sh" ~/code
```

Output is a single `=== PULL-ALL SUMMARY ===` block, sorted worst-first so the lines
that need a human are at the top. Verbose git output goes to the `LOG:` file.

| status | meaning |
|---|---|
| `FAILED` | fetch or merge errored — remote gone, no auth, timeout |
| `DIVERGED` | local main has commits origin/main doesn't **and** vice versa — needs a human |
| `SKIPPED` | dirty tree (or dirty holding worktree), unreadable status, no origin, no local target branch, or submodule |
| `UPDATED` | fast-forwarded — in place (`main +36`), by ref (`+12 in place (on feature/x)`), or inside the worktree holding the branch (`+3 in worktree …`) |
| `CREATED` | local target branch created from origin (only with `--create`) |
| `CURRENT` | already up to date |

Exit code: `0` if nothing needs attention, `1` if any repo is `DIVERGED` or `FAILED`,
`2` on bad usage.

## 4) Report

Relay the summary, then call out the top of the list — `FAILED` and `DIVERGED` repos are
the only ones the user has to act on. Don't re-run git per repo; the script already
fetched everything. Read the `LOG:` file only if the user wants to dig into a failure.

## Options

| flag | effect |
|---|---|
| `-b, --branch NAME` | force one target branch for every repo (default: per-repo detection) |
| `-d, --depth N` | how deep to search for `.git` (default 4) |
| `-j, --jobs N` | repos in parallel (default 8) |
| `-t, --timeout SECS` | per-repo network timeout (default 120) |
| `-n, --dry-run` | fetch and report, move no local ref |
| `--hidden` | also descend into dot-directories (skipped by default) |
| `--create` | create the target branch locally when it's missing |
| `-l, --log FILE` | verbose log path |

## Safety model

These are guarantees of the script, worth stating to the user when they hesitate:

- **Never switches branches.** If a repo is checked out on `feature/x`, main is advanced
  via `git fetch origin main:main`, which moves the ref without touching the worktree. If
  main is checked out in a linked worktree, the fast-forward runs *in that worktree* — still
  no branch switch anywhere.
- **Never merges non-fast-forward.** `--ff-only` on the checked-out case; a plain ref
  fetch otherwise. Anything that isn't a fast-forward is reported as `DIVERGED`, untouched.
- **Never touches a dirty tree.** Tracked-file modifications mean `SKIPPED`. Untracked
  files are ignored — they don't block a fast-forward. A `git status` that *errors* is also
  `SKIPPED`, never assumed clean.
- **Never creates branches by default.** `--create` is opt-in.

To undo an `UPDATED` repo: `git -C <repo> reset --hard <pre-sha>`, where the pre-sha is
in the `LOG:` file's `Updating <old>..<new>` line.

## Gotchas

- **Target branch is detected per repo, not assumed to be `main`.** Order:
  `origin/HEAD` → `main` → `master` → `trunk`. A repo whose `origin/HEAD` is stale gets
  the wrong answer; `-b` overrides. Verified: a `master`-default repo in the same tree as
  `main` repos updates its own branch correctly.
- **Dot-directories are pruned by default, and this matters.** A scan of `~` without it
  finds `~/.nvm` and `~/.oh-my-zsh` and offers to update them — `~/.nvm` sits at a
  detached HEAD, so with `--create` it would grow a local `master` branch it never had.
  `--hidden` opts back in.
- **`.git` is itself a dot-name.** The find prune is
  `\( -name '.[^.]*' ! -name .git \) -prune -o -name .git -print`. Drop the `! -name .git`
  and the prune eats every repo before `-print` sees it — the script silently finds zero
  repos. This is why the discovery expression looks over-engineered.
- **`--depth 1` finds only a repo at the root itself.** Depth counts down to the `.git`
  entry, so immediate children need `2`. `bash pull-all.sh -n -d 1 ~` legitimately prints
  "no git repos found".
- **Submodules and linked worktrees are `SKIPPED`, detected by `.git` being a file**
  rather than a directory. Pulling a submodule's own main is almost never what the parent
  repo wants.
- **A bare repo still answers `symbolic-ref HEAD` with a branch name.** `~/activate/vi-activate`
  has `core.bare = true` with files on disk and its real checkouts in linked worktrees (the
  Cursor / `.claude/worktrees` pattern). Asking for the branch name says `main`, so a naive
  script takes the checked-out path and dies with `fatal: this operation must be run in a
  work tree`. Detection is `git rev-parse --is-bare-repository`; bare repos take the ref-fetch
  path and report `in place (on (bare))`.
- **`git status` exits 128 in a bare repo, and an errored status read must not look clean.**
  Capturing only stdout makes the failure indistinguishable from a clean tree, so the repo
  sails through the dirty gate and fails later at the merge. The check tests the exit status
  and reports `cannot read status` — fail closed, not open.
- **If the target branch is checked out in a *linked* worktree, it gets fast-forwarded
  there.** git refuses to fetch into a branch checked out anywhere, so the ref-fetch path is
  unavailable — instead the merge runs inside the worktree that holds the branch, which is
  the only place it has a working tree to move. Reported as
  `UPDATED  main +3 in worktree ~/.cursor/worktrees/foo/abcd`. That worktree gets the same
  dirty guard as any other checkout; if it has tracked modifications the repo is `SKIPPED`.
- **`git worktree list` includes the primary worktree**, so for an ordinary repo sitting on
  main the reported "holder" is the repo directory itself. The worktree branch is checked
  only after the `cur == target` case has already returned, so a normal repo never reaches it
  and there's no double handling. Only genuinely linked holders land there.
- **`CURRENT` can still mean "you have unpushed work."** The detail reads
  `main up to date (13 unpushed)` — nothing to pull, but the branch is ahead.
- **A repo whose GitHub remote was renamed or deleted shows up as `FAILED` with
  `Repository not found`.** That's the remote, not the script. Three of the repos under
  the author's `~` are in this state.
- **`git pull` is never invoked.** It's `fetch` then an explicit `merge --ff-only` (or a
  ref fetch), so a configured `pull.rebase` can't change the behavior.
- **Written for bash 3.2** (macOS `/bin/bash`): no associative arrays, no `wait -n`, no
  `mapfile`. Keep it that way when editing — the throttle loop polls `jobs -rp` on purpose.

## Troubleshooting

- **`fetch timed out after 120s`**: a remote is hanging. Raise `-t`, or find the repo in
  the `LOG:` file and check its remote by hand.
- **A private repo `FAILED` with an auth error**: the script sets `GIT_TERMINAL_PROMPT=0`
  and `ssh -o BatchMode=yes` so it can never block on a credential prompt. Fix the
  credential helper / ssh agent, then re-run.
- **`no git repos found` on a path you know has repos**: raise `--depth`, and add
  `--hidden` if the repos live under a dot-directory.
- **Whole run feels slow**: it's network-bound. `-j 16` helps on many small repos; the
  fixture tree takes 3s at `-j 1` versus under 1s at the default `-j 8`.
