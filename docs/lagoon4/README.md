# Lagoon 4

This is SORACOM's fork of Grafana. Lagoon 4 is the port of the Lagoon
customisations onto Grafana 13.2.1, and this directory holds the notes that are
ours rather than upstream's.

Everything upstream still applies. `contribute/developer-guide.md` is the real
build documentation and it wins over anything here; this page only covers what's
different because we're a fork, and the places where the devcontainer or the host
will trip you up.

## Branch model

- **`main`** is upstream `grafana/grafana` main. We never modify it. It exists so
  the fork can pull upstream in.
- **`lagoon4`** is the integration branch and the actual product. It was cut from
  the upstream tag `v13.2.1`, and every SORACOM change lands here as a merged PR.
  Later it gets moved forward onto newer upstream tags.
- **Feature branches** are `l4-<feature>` — `l4-bootstrap`, `l4-auth`, and so on.
  They branch from `origin/lagoon4` and never from `main`.

The hyphen isn't cosmetic. Git stores branches as files under `.git/refs/heads/`,
so a branch named `lagoon4` and a branch named `lagoon4/auth` can't both exist —
one is a file, the other needs a directory of the same name. Naming things
`lagoon4/<feature>` would make it impossible to have the `lagoon4` branch itself.

To start work:

```sh
git fetch origin
git switch -c l4-<feature> origin/lagoon4
```

PRs target `lagoon4`, never `main`. Keep frontend and backend changes in separate
PRs where you reasonably can — upstream asks for this and it also keeps the
merge-forward diffs readable.

## Porting inventory

The inventory of what actually has to be ported from Lagoon 3 is in
`docs/lagoon4/inventory.md`. It's arriving in its own PR, so if that file isn't
there yet, that work hasn't landed.

Two things from it are worth knowing before you touch anything, because they
change which tree you should be reading:

- **Port from `soracom-release-11.6.5`**, the branch in `soracom/grafana`, not
  from the 9.3.9 branch. Treat `soracom/grafana` as read-only — we don't push to
  it. 11.6.5 is much closer to 13.2.1 and it already absorbed a lot of the churn
  you'd otherwise redo by hand.
- **The 9.3.9 fork point upstream is commit `cf157c123cb`.** There's no `v9.3.9`
  tag, so if you need to diff Lagoon 3 against stock Grafana, that commit is the
  base to use rather than hunting for a tag that doesn't exist.

See `docs/lagoon4/inventory.md` for the actual per-feature detail.

## Building in the devcontainer

Open the repo in the devcontainer (`.devcontainer/devcontainer.json`) and you
should get Go 1.26.6, Node 24 and Yarn 4.17.1 without doing anything:

```sh
go version     # go1.26.6 linux/amd64
node --version # v24.x
yarn --version # 4.17.1
```

Then, one at a time — see the note about the host below:

```sh
yarn install --immutable                      # frontend dependencies
go build -o ./bin/grafana ./pkg/cmd/grafana   # backend
yarn build                                    # frontend production bundle
```

`make build-go` is the Makefile equivalent of the `go build` line and is what the
developer guide points at; plain `go build` is fine for checking the tree compiles.

To run it:

```sh
./bin/grafana server --homepath "$(pwd)"
```

That serves on `http://localhost:3000` with `admin` / `admin` and an embedded
SQLite database, so there's nothing to stand up first. `make run` does the same
with hot reload via air, which is nicer for actual development.

**The homepath has to be absolute.** `--homepath .` looks like it should work and
it doesn't — you get this, after a full and otherwise successful startup:

```
Error: could not find core plugins in directory /usr/share/grafana/public
```

which is confusing, because you never asked for `/usr/share/grafana`. The reason is
in `pkg/registry/apps/plugins/register.go`: if `StaticRootPath` isn't an absolute
path it's replaced outright with the packaged install location, so a relative
homepath silently turns into the path a distro package would use. `$(pwd)` avoids
the whole thing.

**A `go build` binary reports the wrong version.** It'll say `9.2.0`, which is just
the default assigned to the `version` variable in `pkg/cmd/grafana/main.go`. The
real version comes from an ldflag the Makefile builds out of `package.json`, so
only `make build-go` produces a binary that knows it's 13.2.1. Fine for local work,
worth remembering before you report a version number from a hand-built binary.

### What each step actually costs

Measured on the shared dev host (16 cores), one step at a time, from a cold cache:

| Step | Wall clock | Peak RSS | Leaves behind |
| --- | --- | --- | --- |
| `yarn install --immutable` (first, cold store) | 0:51 | 3.3 GB | 2.2 GB Yarn store + node_modules |
| `yarn install --immutable` (another worktree, warm store) | 0:11 | 0.9 GB | ~91 MiB |
| `go build -o ./bin/grafana ./pkg/cmd/grafana` | 7:05 | 6.0 GB | 3.7 GB module cache, 5.0 GB build cache, 496 MiB binary |
| `yarn build` | 3:13 | 8.6 GB | 205 MB in `public/build` |

The Go numbers are the ones that surprise people. `go build` peaked at 6 GB of RSS
and the build cache alone grew to 5 GB, and the binary is 496 MiB because the
default build keeps full debug symbols.

The frontend build is the memory ceiling, though. It peaked at **8.6 GB RSS**,
which is essentially the 8 GB heap that `NODE_OPTIONS=--max-old-space-size=8192`
grants it. It completed fine, but there was only around 9-11 GB of memory actually
available on the host at the time, so **two `yarn build`s at once will not fit**.
If several agents are working in parallel, the frontend build is the step that has
to be taken in turns.

### One disagreement with the developer guide

`contribute/developer-guide.md` says to build the frontend with `yarn start`. That's
the *watch* build — it compiles and then sits there rebuilding on change, so it
never exits and can't be used as a one-shot "does the frontend build" check. For
that, use `yarn build`, the production webpack build, which does exit. The repo's
own `AGENTS.md` already says `yarn build`. Both are right for their own purpose;
just don't reach for `yarn start` in a script or in CI.

## Several agents, several worktrees, one small disk

Port work runs as several agents at once, each in its own worktree under
`.worktrees/`. The host has roughly 16 GB free, and a full `node_modules` is
2.5 GB, so the naive arrangement doesn't fit — seven worktrees would want about
17.5 GB of `node_modules` before anything else.

The devcontainer sets this up for you in `.devcontainer/post-create.sh`, which
writes a **user-level** `~/.yarnrc.yml`:

```yaml
globalFolder: "/workspaces/lagoon4-poc/.yarn-global"
nmMode: hardlinks-global
```

`hardlinks-global` makes every worktree's `node_modules` hardlink to one shared
copy of each file instead of duplicating it. Measured, with two worktrees:

| | Without sharing (`nmMode: classic`) | With `hardlinks-global` |
| --- | --- | --- |
| First worktree | 2.5 GB | 2.2 GB shared store, ~91 MiB marginal after |
| Each worktree after that | 2.5 GB | **91 MiB** |
| Install time for worktree 2 | 2:35 | **0:11** |
| 7 worktrees, node_modules only | ~17.5 GB | **~2.6 GB** |

Add about 272 MiB per worktree for the source checkout itself, so seven worktrees
land near 4.5 GB all-in rather than 19 GB.

Two details matter, and both are easy to get wrong:

**The store has to be on the same filesystem as the worktrees.** `/home/vscode` is
the container overlay (`st_dev` 172) and `/workspaces/lagoon4-poc` is a bind mount
(`st_dev` 64513). Hardlinks can't cross a filesystem boundary, so if you leave
`globalFolder` at its `~/.yarn/berry` default, `hardlinks-global` quietly falls back
to copying — no error, no warning, you just pay full price per worktree.
`post-create.sh` compares the two `st_dev` values and warns if they ever diverge.

**It goes in `~/.yarnrc.yml`, not the repo's.** The repo's `.yarnrc.yml` is
upstream's file. Setting `nmMode` there would conflict on every merge-forward onto
a newer tag. Yarn merges the user-level file with the repo one, and the repo sets
neither `globalFolder` nor `nmMode`, so the user-level values apply cleanly.

To confirm sharing is actually working rather than trusting the config, compare
inodes for the same file in two worktrees:

```sh
stat -c '%i %h %n' */node_modules/react/package.json
```

Same inode in both, and a link count above 1, means it's genuinely shared.

**The Go caches need no setup.** `GOMODCACHE` is `/go/pkg/mod` and `GOCACHE` is
`~/.cache/go-build` — both live outside the worktrees and are per-user, so every
worktree already shares them. That's 3.7 GB plus up to 5 GB once, not per agent.

**Do delete your binary when you're done with it.** `bin/grafana` is 496 MiB and it
*is* per-worktree; seven of them is 3.5 GB of avoidable pressure.

## Other things that will trip you up

**Check `df -h` before you start, and run heavy steps one at a time.** The steps
above each want several GB of RAM as well as disk. `NODE_OPTIONS=--max-old-space-size=8192`
is set in the devcontainer because the frontend build genuinely needs the headroom.

If you need to reclaim space: `go clean -cache` drops the Go build cache (5 GB)
without touching the downloaded modules, and the Yarn store can be rebuilt from a
`yarn install`. Deleting `/go/pkg/mod` means re-downloading 3.7 GB, so leave it.

**Git hooks are opt-in, and that's upstream's choice.** Grafana used to install
lefthook hooks during `yarn install`; it doesn't any more. `.yarnrc.yml` sets
`enableScripts: false` and there's no `prepare` script, so nothing installs itself.
If you want the pre-commit lint and format hooks:

```sh
make lefthook-install
```

The developer guide recommends this for frontend work, mostly so
`eslint-suppressions.json` stays in sync.

**`python3` ships only a partial stdlib.** The base image has `python3-minimal`,
which is not the same as no Python and not the same as a working one: `import re`
and `import io` succeed, `import json` fails with `ModuleNotFoundError`. That mix is
what makes it confusing -- a script can get several lines in before it dies. Nothing
in Grafana's build needs Python, so it blocks nothing, but it will catch you the
first time you reach for a one-line JSON parse. `post-create.sh` now installs the
full `python3`.

**Node drifts from `.nvmrc`.** `.nvmrc` pins `v24.11.0`, but the devcontainer asks
the Node feature for major version `24` and gets whatever the current 24.x is. Both
satisfy `package.json`'s `engines` (`">= 22 <25"`), so it's fine — but if you're
chasing a version-specific bug, that's why your container and a colleague's nvm
install don't match.

**New dependencies have a waiting period.** `.yarnrc.yml` sets
`npmMinimalAgeGate: 3d`, so a package published in the last three days is refused.
That's an upstream supply-chain guard, not something we added, and worth knowing
before you conclude your `yarn add` is broken.

**Git worktrees are fine.** Worth saying because it's the sort of thing that
usually needs a `safe.directory` entry: worktrees under this checkout work without
one, because the files already belong to the container user.

## CI

We deliberately left upstream's `.github/workflows` in place — all 94 of them —
rather than deleting them on `lagoon4`. They're upstream files that change
constantly, so deleting them would put a modify/delete conflict in the way of every
future merge onto a newer upstream tag, which is the one operation this branch model
exists to make easy.

The intent is that GitHub Actions stays disabled for this repository at the settings
level instead, which is a toggle rather than a diff and can be reverted without
touching the tree. **This has not been confirmed** — see the PR discussion. If you
see upstream workflows actually running on a PR into `lagoon4`, that's the setting
being on, not a decision we made.

No SORACOM CI has been added yet. Lagoon 3's build setup is worth looking at before
we add any, so that it's a deliberate choice rather than a reflex.
