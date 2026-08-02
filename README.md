# ShuratCode-skills

Personal skill marketplace for **Claude Code** and **Claude Desktop (Cowork)**, plus
zip bundles for **claude.ai Chat**.

One `.claude-plugin/marketplace.json` serves Code and Cowork — they use the same plugin
format. Chat is the odd one out: it has no marketplace and takes zip uploads only.

| Surface | Install path | Skills available |
|---|---|---|
| Claude Code | `/plugin marketplace add` | all 4 |
| Claude Desktop (Cowork) | Plugins page → Add marketplace | all 4 |
| claude.ai Chat | zip upload | `restaurant-search` only |

## Skills

| Plugin | What it does | Requires |
|---|---|---|
| **fresh-review** | Pre-commit review with enforced producer/reviewer context separation. Runs the lattice review, the gstack review, and the gstack security audit against the current diff via context-isolated subagents, then triages findings back where intent is known. | `lattice` (auto-installed), gstack (manual) |
| **upgrade-all** | One-shot local maintenance: Homebrew formulas + casks + cleanup, gstack upgrade with migrations, and `claude plugins update` for lattice / aws-core / sparkpilot. Prints one summary block instead of streaming every command. | Homebrew, gstack, `claude` CLI — all optional, each degrades to `SKIPPED` |
| **pull-all** | Point it at a directory; it finds every git repo underneath and fast-forwards each one's main branch from origin, in parallel. Never switches branches, never merges non-fast-forward, never touches a dirty tree. Reports one worst-first line per repo. | git |
| **restaurant-search** | Finds restaurants through three gates — in the right area, verifiably open at the target time in the *restaurant's* timezone, and with a menu that verifiably contains a qualifying dish. Never fills gaps with plausible guesses. | nothing |
| **everything** | Meta-plugin with no skills of its own. Installing it pulls in all four. | — |

## Install — Claude Code

```bash
/plugin marketplace add ShuratCode/ShuratCode-skills
/plugin install restaurant-search@ShuratCode-skills
```

Or take everything at once:

```bash
/plugin install everything@ShuratCode-skills
```

Each skill is then callable as `/<plugin>:<skill>` — e.g. `/fresh-review:fresh-review` —
and as bare `/fresh-review` when the name doesn't collide.

### Dependencies install themselves

`fresh-review` declares `"dependencies": ["lattice@lattice"]`, so installing it also
installs the `lattice` plugin from the `lattice` marketplace. This works because
`marketplace.json` allowlists that marketplace:

```json
"allowCrossMarketplaceDependenciesOn": ["lattice"]
```

Only the root marketplace's allowlist applies — there is no transitive trust. Claude Code
resolves dependencies transitively, intersects version ranges when several plugins want
the same dependency, and blocks disabling a plugin that another enabled plugin needs.
`claude plugin prune` removes auto-installed dependencies once nothing needs them.

Requires Claude Code **≥ 2.1.143**.

### What dependencies cannot do

`dependencies` resolves **plugins in marketplaces**. It cannot clone a git repo or install
a system package. So these are *not* auto-installed:

- **gstack** — a git clone at `~/.claude/skills/gstack`, not a plugin. `fresh-review`
  detects it at preflight and reports which review passes it can actually run; with gstack
  absent it runs the lattice pass alone and labels the verdict single-lens.
- **Homebrew** and the `claude` CLI — `upgrade-all` marks each missing component `SKIPPED`
  rather than failing.

Both skills degrade honestly instead of pretending. See [CHANGELOG.md](CHANGELOG.md).

## Install — Claude Desktop (Cowork)

Same repo, same manifest. On the Plugins page choose **Add marketplace** and enter either
`ShuratCode/ShuratCode-skills` or the full `https://github.com/ShuratCode/ShuratCode-skills`.

Note that `fresh-review`, `upgrade-all`, and `pull-all` need a real shell, git, and a local
checkout, so they are only meaningful in a Cowork session with filesystem access.

## Install — claude.ai Chat

Chat has no marketplace and cannot run plugins ("Plugins are available in Cowork and Code.
They aren't used in Chat."). Build the zips:

```bash
./scripts/build-chat-skills.sh
```

Then upload `dist/chat-skills/<skill>.zip` at <https://claude.ai/customize/skills> →
**+** → **Create skill** → **Upload a skill**.

Only `restaurant-search` ships to Chat. `fresh-review`, `upgrade-all`, and `pull-all` need
bash against *your* machine, git, and subagents; the Chat sandbox is isolated from your
filesystem and has no subagent primitive, so porting them would produce skills that
silently fail.

The Chat copy of `restaurant-search` is a genuine variant, not the same file: claude.ai caps
`description` at **200 characters** where Claude Code allows far more, so the trigger text is
rewritten. `scripts/validate.sh` enforces that the two copies' *bodies* stay identical, so the
fork can't quietly widen.

## Development

```bash
./scripts/validate.sh          # lint everything
./scripts/test.sh              # run every plugins/*/tests/test-*.sh
./scripts/check-release.sh     # fail if a plugin changed without a version bump
./scripts/build-chat-skills.sh # package chat zips into dist/
```

### Merging

`main` is protected by a ruleset: **no direct pushes, and the `check` job in
`.github/workflows/ci.yml` must pass before a PR can merge.** It runs `validate.sh`, `test.sh`,
and `check-release.sh`. There are no bypass actors, so the rule applies to the repo owner too —
a red build blocks the merge button rather than warning about it. Branches must also be up to
date with `main` before merging, so a stale PR can't pass the release gate against a base that
has since moved.

Reviews are *not* required (`required_approving_review_count: 0`), since this is a solo repo.

### Releasing

**A change to a plugin isn't shipped until its `version` is bumped.** `claude plugins update`
extracts into a cache keyed on `plugins/<name>/.claude-plugin/plugin.json`'s `version`; if that
string is unchanged the updater reports `CURRENT` and leaves the stale copy in place, so merged
code never reaches a machine. `check-release.sh` enforces this, plus the marketplace version bump
and CHANGELOG entry that go with it. Changes confined to `plugins/<name>/tests/` are exempt.

Note that `claude plugin validate --strict` cannot catch this — it checks manifest shape, not
delivery. Every manifest here passed it during the two releases that shipped nothing.

`validate.sh` fails on:

- invalid JSON, or a marketplace/plugin manifest missing a required field
- a plugin directory not listed in `marketplace.json`, or a `name` that disagrees with its directory
- a dependency naming a plugin that doesn't exist, or a cross-marketplace dependency whose
  marketplace isn't allowlisted
- a skill whose frontmatter `name` doesn't match its directory, or that has no `description`
- `allowed-tools` naming a tool that isn't real (`Task` is the classic — it parses fine and
  does nothing)
- `triggers:`, which is not a supported frontmatter key and is silently ignored
- a Code skill referencing `~/.claude/skills/<itself>`, which breaks the moment it's installed
  as a plugin — use `${CLAUDE_PLUGIN_ROOT}`
- a Chat skill whose description exceeds 200 chars, references a local path, or mentions
  subagents or slash commands
- a Chat skill whose body has drifted from its Code twin

Adding a skill: create `plugins/<name>/.claude-plugin/plugin.json` and
`plugins/<name>/skills/<name>/SKILL.md`, add the entry to `.claude-plugin/marketplace.json`,
add it to `everything`'s `dependencies`, then run `validate.sh`.

## License

MIT
