# Lagoon 4: inventory of every SORACOM customization, and what it takes to port each one to Grafana 13.2.1

Stream 1 of the Lagoon 4 effort (agentbridge task 269, umbrella 268). Written 2026-09-08.

This is the working document for the porting agents. It is long on purpose — completeness matters
more than brevity here, and a porting agent should be able to pick one section and work from it
without re-deriving anything.

---

## 0. How to reproduce every number in this document

**These commands do not run in this repository.** Every diff, `git grep` and `git log` quoted
below was run in a clone of **`soracom/grafana`** (the Lagoon 3 fork), not in `soracom/lagoon4-poc`.
That's where the Lagoon 3 history and the `soracom-release-*` branches live; this repo is a fresh
fork of `grafana/grafana` and has none of it. The document ships here because this is where the
port agents work, but to check any claim you need the other clone.

Set that clone up like this — remote names matter, because the commands below use them:

```bash
# in a clone of soracom/grafana
git remote -v
# origin    https://github.com/soracom/grafana.git     <- the Lagoon 3 fork
# upstream  https://github.com/grafana/grafana.git     <- upstream Grafana

git fetch origin
git fetch upstream tag v13.2.1 --no-tags
git fetch upstream tag v11.6.5 --no-tags

# There is no v9.3.9 tag anywhere - not on origin, not on upstream. See section 1.
# Create it locally, in that soracom/grafana clone, before running anything below:
git tag v9.3.9 cf157c123cb0c461bdd00190f578a19e4f92d470
```

The `v9.3.9` tag is local-only and exists in no remote. Anyone re-running these commands has to
create it themselves, in their `soracom/grafana` clone. Creating it here in `lagoon4-poc` would
not help: `cf157c123cb` is not reachable from this repository's history.

For reference, `lagoon4-poc`'s own integration branch `lagoon4` is exactly the upstream v13.2.1
commit `56cd3e9288d8255fecebe5d05b48d191f50674b5` (`git rev-parse 'v13.2.1^{}'`), so "the v13.2.1
tree" in this document and "the `lagoon4` branch" are the same tree.

Reference points, all verified rather than assumed:

| ref | sha | what it is |
|---|---|---|
| `v9.3.9` (local alias) | `cf157c123cb0c461bdd00190f578a19e4f92d470` | upstream "Release: Bump version to 9.3.9 (#63857)", Grot, 2023-02-28 |
| `origin/soracom-release-9.3.9` | `6a5bac922bed83871cdd53e3b58f2fd91c585bad` | production Lagoon 3, "[build] Bump harvest-backend hash and drop lagoon plugin branch suffixes", Shogo Okada, 2026-06-22 |
| `origin/soracom_main` | `d943ee009c7d1897fa6bf4434f0916add61767b2` | fork default branch, base of most feature PRs |
| `origin/soracom-upstream-merge-base` | `4a713bd9ed4f276f6b9634d2551c9ec2cb8e1e96` | upstream 11.6.0-pre @ 2025-03-10, base of the 11.6.x port |
| `origin/soracom-release-11.6.5` | `15d65de0f5a21ca106f60fc51312cfeeb98ebdda` | composed 11.6.5 port branch, 2025-09-03 |
| `v11.6.5` | upstream tag | ancestor of `soracom-release-11.6.5` (verified) |
| `v13.2.1` | upstream tag | the target |

The repository was treated as read-only throughout: fetch, diff, read. Nothing was pushed, no
remote branch or PR was touched. The only local mutation is the `v9.3.9` tag, which lives in this
worktree's object store.

`gh` is not installed in this container (`gh: command not found`). All PR data came from the
`gh` **MCP server** (`list_pull_requests`, `pull_request_read`), which is authenticated for
`soracom/grafana`. All 46 PRs (#1–#46) were read, open and closed.

The repository has **no `CLAUDE.md`** — not at the root of `soracom_main`, not on the release
branch, not anywhere in the worktree. The brief's "the repo's own CLAUDE.md wins" is therefore
moot, and the porting repo will need build instructions written from scratch (see §8).

---

## 1. Corrections to the brief and to the task description

Three things in the brief and task description do not match what is actually in the repository.
Flagging them rather than silently working around them:

**1. There is no `v9.3.9` tag in grafana/grafana.**

```
$ git fetch upstream tag v9.3.9 --no-tags
fatal: couldn't find remote ref refs/tags/v9.3.9

$ git ls-remote --tags upstream | grep -E 'refs/tags/v9\.3\.[0-9]+$' | sort -V
... v9.3.0 v9.3.1 v9.3.2 v9.3.4 v9.3.6 v9.3.8 v9.3.11 v9.3.13 v9.3.14 v9.3.15 v9.3.16
```

9.3.3, .5, .7, .9, .10 and .12 were security releases whose tags were never pushed to the public
repo — the fork's own history shows the tell-tale low-numbered security-repo PR references
(`Geomap: Sanitize the attribution string (#745)`, `Auth: Update saml go.mod (#712)`) sitting right
underneath the version bump. The bump commit itself *is* public and *is* an ancestor of the
release branch:

```
$ git log -1 --format='%H %ad %an %s' --date=short cf157c123cb
cf157c123cb0c461bdd00190f578a19e4f92d470 2023-02-28 Grot (@grafanabot) Release: Bump version to 9.3.9 (#63857)

$ git merge-base --is-ancestor cf157c123cb origin/soracom-release-9.3.9 && echo YES
YES

$ git show origin/soracom-release-9.3.9:package.json | grep '"version"'
  "version": "9.3.9",
```

So `cf157c123cb` is the fork point and everything below uses it as `v9.3.9`, via a tag created
locally in a `soracom/grafana` clone (see section 0). It is not a tag you can fetch, and it is
not reachable from `soracom/lagoon4-poc`.

**2. The 11.6.x work is not just PRs #32–#44.** There is a composed release branch,
`origin/soracom-release-11.6.5`, that the task description doesn't mention. It has 203 non-merge
commits on top of upstream v11.6.5 and a 136-file Lagoon delta, and it contains work that exists
in none of the individual PRs (scenes dashboard init, MegaMenu branding, mjml email templates,
i18n locale edits). See §3 — this changes the recommended porting base for most features.
There are also `origin/soracom-experimental-11.6.2` and `origin/soracom-experimental-11.5.1`,
and seven dated `soracom-release-9.3.9-2025*` branches, none of which the brief lists.

**3. The PR generations are correct but the "still open against soracom_main" framing hides a
split.** PRs #26/#27 were opened against `soracom-release-9.3.9-shogo-dev` and #29 against
`soracom-release-9.3.9-new-deployment-logic`, not against `soracom_main`. And several open
feature branches have moved on *past* what was merged into the release branch, so
`git merge-base --is-ancestor <branch> soracom-release-9.3.9` returns false for branches whose
content is unambiguously in production (firehose, dev-tools, regex-meta-flag, lagoon-icons,
deployment). **Do not use branch ancestry to decide what ships — use the file-level diff.**
Everything in this document is keyed off the file diff.

---

## 2. Scale

```
$ git diff --shortstat v9.3.9...origin/soracom-release-9.3.9
 158 files changed, 5441 insertions(+), 326 deletions(-)

$ git log --oneline v9.3.9..origin/soracom-release-9.3.9 | wc -l
288        # 228 non-merge, 60 merge commits
```

Three of those 288 are upstream commits that also landed on `upstream/release-9.3.11` — a
changelog commit and two 9.3.x backports (`TimeSeries: Fix legend and tooltip colors…` #63870,
`NPM: Stop using the folder path before the name path` #63860). The other ~285 are SORACOM's.

The 5441-insertion figure is inflated by three lumps that are not code to port:

| lump | lines | what it is |
|---|---|---|
| `conf/development.ini` + `conf/production.ini` | 2329 | whole-file copies of an old upstream `sample.ini` with ~25 values changed |
| `scripts/build-soracom/pre-built-plugins/grafana-clock-panel/**` | ~290 + binaries | vendored prebuilt third-party plugin |
| `.yarn/sdks/**` | ~250 | yarn SDK churn, incidental |

Net real Lagoon source delta: roughly **1.5k lines across ~110 files**. The single largest item is
`pkg/services/ngalert/notifier/redis_peer.go` at 595 lines — and that one turns out to be
obsolete (§6.1).

For comparison, the 11.6.5 port:

```
$ git diff --shortstat v11.6.5...origin/soracom-release-11.6.5
 136 files changed, 12133 insertions(+), 1454 deletions(-)
```

(inflated by `emails/package-lock.json` at 7512 lines and the same clock panel; net delta is
comparable to 9.3.9's.)

---

## 3. The single most important decision: port from 11.6.5, not from 9.3.9

`origin/soracom-release-11.6.5` already survives four upstream rewrites that sit between 9.3.9 and
13.2.1 and that would otherwise have to be redone from scratch:

- **scenes** — dashboards became scene-based; `initDashboard.ts` is gone, replaced by
  `dashboard-scene/serialization/buildNewDashboardSaveModel.ts`. The 11.6.5 branch has a 111-line
  patch there, and that file still exists in v13.2.1.
- **AppChrome / MegaMenu** — `NavBar/NavBarItemIcon.tsx` is gone; branding moved to
  `AppChrome/MegaMenu/MegaMenuHeader.tsx` and `AppChrome/TopBar/SingleTopBar.tsx`. 11.6.5 patches
  both; both still exist in v13.2.1.
- **mjml e-mail templates** — `emails/templates/*.html` became `*.mjml` with partials. 11.6.5 has
  the full mjml rewrite of the Lagoon branding; v13.2.1 uses the same mjml pipeline.
- **i18n extraction** — hundreds of strings moved into `public/locales/*/grafana.json`. 11.6.5
  edits seven locale files; v13.2.1 has twenty.

So the recommended base for **most** features is the 11.6.5 tree, with the 9.3.9 tree used as the
completeness checklist. **But 11.6.5 is not a superset.** Diffing the two file sets:

### Present in 9.3.9, never carried to 11.6.5, and still needed

| # | item | files (9.3.9) | why it was missed |
|---|---|---|---|
| 1 | Teams API org-membership leak fix (PR #45) | `pkg/api/team_members.go` +34, `team_members_test.go` +86/−14 | landed 2025-10, after 11.6.x work stopped |
| 2 | resource-permission org validation | `pkg/services/accesscontrol/resourcepermissions/service.go` +13/−2 | same PR family as #1 |
| 3 | org-quota middleware bypass | `pkg/middleware/quota.go` +3 | never ported |
| 4 | Soracom datasource-rename DB migration | `pkg/services/sqlstore/migrations/soracom_mig.go` +8, `migrations.go` +3 | never ported |
| 5 | plugin gRPC logs at INFO | `grpcplugin/log_wrapper.go` +2/−2, `grpc_plugin.go` +4 | never ported |
| 6 | render timeout 10s→20s (PR #46) | `pkg/services/ngalert/image/service.go` +1/−1 | landed 2025-12, after 11.6.x |
| 7 | public-dashboards `hide` query change | `pkg/services/publicdashboards/service/query.go` +12/−13 | never ported; probably obsolete anyway (§6.5) |

Items 1, 2 and 3 are the ones that matter. 1 and 2 are security fixes; 4 is a data migration that
cannot simply be skipped.

Everything else in 9.3.9 but not in 11.6.5 is obsolete for an independent reason and is listed in
§6.

---

## 4. Feature inventory

Classification used throughout, per the task description:

- **(a) mechanical re-apply** — the upstream code is recognizably the same; the patch applies with
  at most a rename.
- **(b) needs adaptation** — the code exists but the surrounding API/types/file layout changed.
- **(c) needs re-design** — the upstream subsystem was rewritten; the intent has to be re-expressed.
- **(d) obsolete** — upstream now does this natively, or the thing being patched is gone.
- **(e) unclear** — needs Shogo's decision.

Where I say "still exists in v13.2.1" I mean I looked at the v13.2.1 tree with `git grep`/`git show`.
Where I am guessing at *why* something was written, I say so.

### Group A — Branding and product identity

The largest single theme by file count and the lowest risk. PRs **#6** (`soracom_add_logos_and_branding`,
15 files, +78/−53), **#17** (`soracom-add-lagoon-icons-to-alerts`, 16 files, +84/−84),
**#5**/**#15** (`soracom_add_email_templates` +663, `soracom-modify-email-templates` 19 files,
+38/−38). 11.6.x equivalents: **#34** (`add-logos-and-branding`, 30 files), **#40**
(`modify-email-templates`, 38 files).

**What it does.** Replaces every user-visible "Grafana" with "SORACOM Lagoon": the app title, the
favicon and apple-touch-icon, the loading logo and preloader text, the login page title, the menu
logo, the e-mail templates (logo image, "Sent by SORACOM Lagoon" footer, "Reset your Lagoon
password" subject), the footer links (Grafana docs/support/community → SORACOM developers docs,
Japanese users docs, User Console), the welcome panel links, the "powered by Grafana" public
dashboard footer, the news panel removal from `home.json`, and the string
`"Grafana v" + BuildVersion` → `"Lagoon v3 - " + BuildVersion` in every alert notifier footer
(Slack, Discord, Google Chat, VictorOps, HipChat, plus `FooterIconURL`). It also renders the
Lagoon version as literal `"3"` with the Grafana build version demoted to the commit slot in the
help menu (`navtree.go`).

**One customer-facing feature hides in here**, and it is not just branding: `MenuLogo` in
`Branding.tsx` does a `fetch(..., {method:'HEAD'})` against
`https://soracom-customer-images.s3.amazonaws.com/lagoon/<orgName>/logo` for `-PRO` orgs and
swaps the menu logo for the customer's own uploaded logo if it 200s. That pairs with the image
upload API in Group B.

**Where it lives (9.3.9).** `pkg/api/index.go` (+8/−8), `pkg/setting/setting.go`
(`ApplicationName = "Lagoon"`), `public/app/core/components/Branding/Branding.tsx` (+50/−13),
`Footer/Footer.tsx` (+20/−20), `NavBar/NavBarItemIcon.tsx`, `ForgottenPassword.tsx`,
`public/views/index-template.html`, `public/app/plugins/panel/welcome/Welcome.tsx`,
`public/dashboards/home.json` (−16), `public/img/{favicon-lagoon.png,apple-touch-icon-180.png,lagoon-logo-cl.svg}`,
all of `public/emails/*` and `emails/templates/*`, `pkg/services/alerting/notifiers/*` (legacy),
`pkg/services/ngalert/notifier/channels/{discord,googlechat,slack,victorops,util}.go`,
`GrafanaManagedAlert.tsx`, `PublicDashboardsFooter.tsx`, `navtree.go`.

**Touches.** Frontend UI, e-mail templates, alerting notifier payloads, static assets, i18n.

**Porting assessment for 13.2.1 — mostly (b), some (c), some (d):**

- `pkg/setting/setting.go:59` still reads `ApplicationName = "Grafana"`. **(a)**
- `pkg/api/index.go:193–198` still has `FavIcon` / `AppleTouchIcon` / `AppTitle` / `LoadingLogo`,
  but the values are now `template.URL(assets.ContentDeliveryURL + "public/build/img/…")` rather
  than bare `public/img/…` strings. **(b)** — the Lagoon assets must move into the
  `public/build/img` pipeline.
- `Branding.tsx` still exists with `LoginLogo` / `MenuLogo` / `AppTitle` / `LoginTitle`, but images
  are now ES module imports (`import grafanaIconSvg from 'img/grafana_icon.svg'`) instead of path
  strings. **(b)**, and the Lagoon SVG needs to become an importable asset.
- The `operatorId` prop plumbing is *simpler* in 13.2.1 than in either 9.3.9 or 11.6.5: `MenuLogo`
  is now called from `HomeLogo` inside `Branding.tsx` itself (line 74) and from `ThemePreview.tsx`,
  not from a dozen chrome components. The org name can be read from `config.bootData.user.orgName`
  inside `MenuLogo` and the prop dropped entirely. **(b), and an opportunity to simplify.**
- `public/views/index-template.html` is gone; the preloader text lives in `public/views/index.html`
  (`aria-label="Loading Grafana"` at line 208). 11.6.5 already ported this. **(a)** from 11.6.5.
- `NavBar/NavBarItemIcon.tsx` is gone. 11.6.5's `MegaMenuHeader.tsx` / `SingleTopBar.tsx` patches
  are the right shape and both files still exist in v13.2.1. **(b)**
- `BouncingLoader.tsx` (patched in 11.6.5) **no longer exists** in v13.2.1. **(e)** — find the
  replacement loader or drop it.
- Legacy `pkg/services/alerting/notifiers/*` is **gone** from v13.2.1 (legacy alerting removed).
  **(d)** — half the notifier branding patches evaporate.
- `pkg/services/ngalert/notifier/channels/*` is **gone**: notifier implementations moved out to the
  `github.com/grafana/alerting` Go module (`v0.0.0-20260805100035-e1a167a201a8` in v13.2.1's
  go.mod). The "Lagoon v3 - " footers and `FooterIconURL` are now inside a third-party module.
  **(c)** — this needs re-design; options are a fork of grafana/alerting, a template override, or
  accepting Grafana-branded notifier footers. **Flagging for Shogo (Q4).**
- `PublicDashboardsFooter.tsx` is gone → `public/app/features/dashboard/components/PublicDashboard/DashboardBrandingFooter.tsx`,
  which is now **configurable** via `useGetPublicDashboardConfig()` and has explicit `text` / `logoUrl` /
  `linkUrl` override props plus a `'grafana-logo'` sentinel. **(d)/(b)** — the patch becomes config,
  not a code edit. Good news.
- E-mails: `emails/templates/*.html` → `*.mjml` with `partials/layout/{header,footer,head}.mjml`.
  v13.2.1 has the same mjml layout as 11.6.5, plus `verify_email` and `passwordless_verify_*`
  templates that 11.6.5 also covers. **(a)/(b) from 11.6.5**, **(c) from 9.3.9**.
- `public/dashboards/home.json` still has the news panel at line 52 in v13.2.1. **(a)**
- `Welcome.tsx` still exists. **(a)**
- `Footer.tsx` still exists with the same `getFooterLinks()` / `getVersionLinks()` shape.
  **(a)** — but note 11.6.5 chose instead to comment out `getEditionAndUpdateLinks()` in
  `AppChrome/MegaMenu/utils.ts`, which still exists in v13.2.1 at line 141. Either works.
- `GrafanaManagedAlert.tsx` is gone from v13.2.1. **(e)** — find where the rule-type picker lives now.

**Dependencies.** None. This group is a prerequisite for nothing and depends on nothing. It is the
ideal first parallel workstream.

---

### Group B — The Lagoon plan model and plan-based gating

PR **#12** (`soracom-add-lagoon-settings`, 11 files, +228/−9) and PR **#36** (11.6.x, 19 files,
+281/−11). Also PR **#10** (`soracom-enable-editors-to-publish-public-dashboards`, 3 files) and
PR **#16**/**#38** (`soracom-add-image-link`, +113).

**What it does.** `pkg/lagoon/lagoon.go` (127 lines, new package) is the heart of Lagoon's
commercial model inside Grafana. It derives the customer's plan from the **organisation name
suffix** — `-FREE` → `PlanFree`, `-PRO` → `PlanPro`, anything else → `PlanMaker` — and exposes:

- `AlertFrequencyForPlan(plan)` → 60 / 30 / 5 seconds, the fastest permitted refresh and alert
  evaluation interval per plan;
- `PublicDashboardsEnabledForPlan(plan)` → PRO only;
- `IsFreePlan` / `IsProPlan` / `IsMakerPlan`;
- `GetOrgAccessKey(dsService, ctx, orgID)` — walks the org's datasources looking for a
  `soracom-harvest-datasource` or `harvest-backend-datasource` and returns its `User` field as
  the SORACOM access key, and `HashWithOrgAccessKey` which md5s something with it.

That plan value is then consumed in four places:
- `pkg/api/frontendsettings.go` — injects `minRefreshInterval` and `alertingMinInterval` per plan
  into the frontend bootdata, and **overwrites the `publicDashboards` feature toggle per-org** for
  non-admin, non-public-dashboard-view requests;
- `pkg/services/navtree/navtreeimpl/navtree.go` — hides the Snapshots nav item unless PRO;
- `public/app/features/dashboard/components/ShareModal/ShareModal.tsx` — hides the Snapshot tab
  unless the org name ends `-PRO`;
- `Branding.tsx` — the customer-logo fetch above.

PR #10 separately changes `pkg/api/accesscontrol.go` so the fixed public-dashboard-writer role is
granted to `org.RoleEditor` instead of `"Admin"`.

PR #16 adds `GET /api/orgs/:orgId/image/link` (`pkg/api/images.go`, 112 lines): for `-PRO` orgs
only, it HMAC-SHA256-signs `"LagoonLogo:<orgName>:<unixtime>"` with `IMAGE_LINKER_KEY`, calls an
external `IMAGE_LINKER_URL` service, and proxies back a presigned upload link so a PRO customer
can upload their own logo. The logo then shows up via the `Branding.tsx` fetch.

**Why it exists** (inferred from code and PR #12's body, which lists exactly these four effects):
Lagoon is sold in FREE / MAKER / PRO tiers and Grafana OSS has no tenancy or licensing hook, so
the plan is smuggled in through the org name and enforced ad hoc at each site. PR #12's body is
explicit: "Restricts public dashboards to the operators allowed (currently PRO) / Enables maximum
refresh rates per plan (on the frontend, the backend is restricted in the Harvest plugin) /
Restricts the snapshot tab in the share modal depending on plan / Hides menus under dashboard
section depending on plan."

**Touches.** Settings/frontend bootdata, RBAC fixed roles, nav tree, share modal, feature toggles,
datasources service, org service, a new HTTP endpoint, two environment variables.

**Porting assessment for 13.2.1:**

- `pkg/lagoon/lagoon.go` itself is nearly self-contained. Its two external dependencies both still
  exist: `org.Service.GetByID(ctx, *GetOrgByIDQuery) (*Org, error)` (`pkg/services/org/org.go:15`)
  and `datasources.GetDataSources(ctx, *GetDataSourcesQuery) ([]*DataSource, error)`
  (`pkg/services/datasources/datasources.go:24`). Note the 9.3.9 code uses the old
  `query.Result` out-param style; v13.2.1 returns slices. Also `GetOrgByIdQuery` → `GetOrgByIDQuery`.
  **(b)** — small, mechanical-ish rename work. 11.6.5's copy is already halfway there.
- `pkg/api/frontendsettings.go` **moved** to `pkg/api/frontendsettings/frontendsettings.go`.
  `MinRefreshInterval` is still a field (`frontendsettings.go:35`) and
  `UnifiedAlerting.MinInterval` still exists (`pkg/api/dtos/frontend_settings.go:106`).
  `ReqContext.IsPublicDashboardView()` still exists (`contexthandler/model/model.go:66`).
  **(b)** — the 11.6.5 version of this patch is the one to port, not the 9.3.9 one.
- **The `publicDashboards` feature toggle no longer exists in v13.2.1.** `registry.go` only has
  `publicDashboardsEmailSharing`; public dashboards went GA and are now gated by
  `[public_dashboards] enabled` in `conf/defaults.ini:2477`. So the per-org toggle override
  **has no toggle to override**. **(c)** — the plan gate has to be re-expressed, most plausibly as
  an RBAC permission grant per org rather than a bootdata mutation.
  **Flagging for Shogo (Q1).**
- Snapshot gating: v13.2.1's own `ShareModal.tsx` now gates on
  `contextSrv.isSignedIn && config.snapshotEnabled && contextSrv.hasPermission(AccessControlAction.SnapshotsCreate)`,
  and `navtree.go:362` gates the Snapshots nav item on
  `s.cfg.SnapshotEnabled && hasAccess(ac.EvalPermission(dashboardsnapshots.ActionSnapshotsRead))`.
  **Upstream grew exactly the hook Lagoon patched in.** **(d)/(b)** — the plan gate becomes
  "don't grant `snapshots:create` to non-PRO orgs", which is cleaner and survives future upgrades.
  Note also that the live share path in 13.2.1 is
  `dashboard-scene/sharing/ShareButton/ShareMenu.tsx` + `share-snapshot/ShareSnapshot.tsx`, which
  is what 11.6.5 already patches; the old `components/ShareModal/ShareModal.tsx` still exists but
  is largely vestigial.
- `pkg/api/accesscontrol.go` still declares the public-dashboard-writer role with
  `{Action: publicdashboards.ActionDashboardsPublicWrite, Scope: dashboards.ScopeDashboardsAll}`
  at line 507 — the action moved to the `publicdashboards` package. **(b)**, one-line.
- `pkg/api/images.go` is a self-contained new file. `pkg/api/api.go` route registration still
  exists in the same shape. The handler uses `ioutil.ReadAll` (removed style, still compiles but
  deprecated) and `models.ReqContext` → `contextmodel.ReqContext`. **(b)**.
  Two notes worth raising: it does `fmt.Println(req.URL.String())` — printing a signed URL to
  stdout — and it uses misleading error keys (`"org.organizationNotFound"` for a non-200 from the
  linker). Worth cleaning up during the port rather than carrying forward.

**Dependencies.** `pkg/lagoon` is a **prerequisite** for the frontendsettings patch, the navtree
patch, the ShareModal patch and the Branding customer-logo fetch. Port it first, alone, then the
four consumers can go in parallel. The image-link API depends on the Branding logo fetch only by
convention (they are two halves of one feature) — they should be done by the same agent.

---

### Group C — Access control and multi-tenancy hardening

Four separate changes that all exist because Lagoon runs many customer orgs in one Grafana and
OSS Grafana leaks across org boundaries in places.

**C1. Hide SORACOM operators from customers.** PRs **#11** / **#37** (`soracom-add-admin-user-filtering`,
2 files, +63). Adds `filterAdminUsers` to both `pkg/api/org_users.go` and
`pkg/services/accesscontrol/resourcepermissions/api.go`: when the caller is not a Grafana admin,
strip any DTO whose role is `Admin` or whose login is in the comma-separated
`LAGOON_ADMIN_USERNAMES` env var. Frontend counterpart in `AddPermission.tsx` filters `Admin` out
of the built-in-role picker. **Why:** so SORACOM's own support/ops accounts, which are members of
every customer org, don't show up in customer permission lists.

13.2.1: `pkg/api/org_users.go` still exists but `getOrgUsersHelper` is gone — the helpers are now
`searchOrgUsersHelper` (line 346) and there are two k8s-backed variants
(`searchOrgUsersUsingK8s`, `searchOrgUsersPageUsingK8s`) that bypass the old path entirely.
`resourcepermissions/api.go` still has `getPermissions` at line 228. **(b) for the permissions
side, (c) for the org-users side** — the k8s/apiserver migration means there is now more than one
code path returning org users and the filter has to cover all of them, or move down into the
service layer. **Flagging for Shogo (Q2).** Note that upstream's own `dtos.IsHiddenUser(login,
signedInUser, cfg)` (`pkg/api/dtos/models.go:141`) + `[users] hidden_users`
(`conf/defaults.ini:720`) does almost exactly this job and may be the
better vehicle — worth evaluating before re-applying the patch.

**C2. Users from other orgs must not be assignable.** PR **#22** partly, and
`pkg/services/accesscontrol/resourcepermissions/service.go` (+13/−2): `validateUser` used
`GetSignedInUser`, which outer-joins and therefore happily returns a user belonging to a different
org; the patch compares `user.OrgID != orgID` and rejects. Test added in `api_test.go`
("should return http 400 when user is not part of the org").

13.2.1: `service.go` still exists. **(b)**, likely small. This is one of the seven items **not**
in 11.6.5.

**C3. Teams API e-mail leak.** PR **#45** (`codex-vuln-fix-2025-10`, closed 2025-12-16, based on
`soracom-release-9.3.9`). `pkg/api/team_members.go` (+34): `GetTeamMembers` now fetches all org
users, builds a `userByID` map and drops team members that are not in the caller's org;
`AddTeamMember` refuses to add a user who isn't an org member (400). 86 lines of test changes
including "Organisation admins cannot add users from other organisations" and "Access control
denies adding users outside the organisation".

**Why:** a team could contain users from another org, and `GetTeamMembers` returned their e-mail
addresses (via `GetGravatarUrl(member.Email)` and the DTO) to a customer admin. This is the
"Teams API email leak fix" the brief mentions.

13.2.1: `pkg/api/team_members.go` is **gone** — moved to
`pkg/services/team/teamapi/team_members.go`, with `getTeamMembers` / `addTeamMember` on a
`TeamAPI` receiver, using `c.GetOrgID()`, `team.TeamMemberDTO`, `member.AvatarURL` (capitalised),
and `dtos.GetGravatarUrl(cfg, email)`. There is also a **second** implementation at
`pkg/registry/apis/iam/team/rest_members.go` for the apiserver path. **(b), but do both paths.**
This is a security fix and it exists **only** on the 9.3.9 line — it must not be lost.

**C4. Don't let the last Admin be removed.** `Permissions.tsx` (+24): `okToChangeOrRemove` counts
`Admin` permissions in the list and blocks removal/downgrade of the last one, with a
`window.alert('Cannot remove last Admin')`.

13.2.1: `Permissions.tsx` still exists with `onRemove` (line 89) and `onChange` (line 104).
**(a)/(b)**. Worth replacing the raw `alert()` with a proper Grafana notification during the port.

**Dependencies.** C1's frontend half depends on nothing. C1/C2/C3 are independent of each other in
file terms and can be done in parallel — but they're conceptually one review, so one agent doing
all four is probably better than four agents.

---

### Group D — Alerting

**D1. `ALERT_DISABLED` label stops evaluation.** PRs **#13**(closed)/**#14**/**#39**.
`pkg/services/ngalert/store/alert_rule.go`: `GetAlertRulesForScheduling` gets
`AND A.labels NOT LIKE '%ALERT_DISABLED%'` bolted onto both the folders subquery and the rule
query, plus an info log of how many rules were found.

**Why:** PR #14's body — "Adding a label `ALERT_DISABLED` to an alert rule will stop it from being
scheduled for execution." The `precheck.sh` build guard says more: *"make sure we are disabling
alerts that were migrated from lagoon v2"*. So this exists to keep migrated-but-unwanted Lagoon 2
alert rules in the database without paying to evaluate them.

13.2.1: `GetAlertRulesForScheduling` still exists (`alert_rule.go:1564`) but the body was rewritten
— it no longer builds raw SQL strings the same way, and now validates and converts rules with
error logging. **(b)/(c)** — the intent (a scheduling-time filter on a label) is still expressible
but the injection point differs. A cleaner 13.x approach might be `is_paused`, which upstream now
supports natively on alert rules; that would make this **(d)**. **Flagging for Shogo (Q3)** — a
one-off data migration setting `is_paused` on rules labelled `ALERT_DISABLED` may be better than
carrying the SQL patch forever.

**D2. LINE Notify EOL.** PRs **#26**(closed)/**#27**(closed)/**#28**/**#42**. Adds an
`Alert []string` field to `NotifierPlugin` (`channels_config/plugin.go`), guts the LINE notifier's
option list, renames it `LINE (EOL)` with description "This channel is no longer available", and
puts a bilingual EOL message plus `https://notify-bot.line.me/closing-announce` in the new field.
Frontend `ChannelSubForm.tsx` (+17) renders the array in an `Alert` banner, URL-detecting each line.
`public/app/types/alerting.ts` gains `alert?: string[]`.

13.2.1: `channels_config/` is **gone**; notifier definitions come from `github.com/grafana/alerting`
and are reshaped in `pkg/api/alerting.go`. But upstream grew its own deprecation machinery:
`NotifierDTO.deprecated`, `versions[].canCreate`, and
`public/app/features/alerting/unified/utils/notifier-versions.ts` with `isDeprecated()` /
`canCreateNotifier()` / `isLegacyVersion()`, consumed by `ChannelSubForm.tsx:229`. There is also a
native `notifier.dto.info` rendered in an `Alert severity="info"` banner at line 362.
**(d) for the mechanism, (b) for the content** — no custom field needed; set `deprecated` and put
the message in `info`. The bilingual-message-plus-URL shape doesn't fit `info` (a single string)
cleanly, so expect a small compromise. Note LINE still exists as a notifier type upstream in
v13.2.1 (it appears in the notifier snapshots), so it does need to be suppressed somehow.

**D3. Delete confirmations.** PRs **#31**/**#44**. `AlertRuleForm.tsx` and
`RuleActionsButtons.tsx` get `confirmationText="DELETE"` and "Type DELETE to confirm" in the body;
`UnsavedChangesModal.tsx` and `SaveLibraryPanelModal.tsx` change the Discard button to
`fill="outline"`. In response to a productboard request (`sc-128449`) — customers were deleting
alert rules by accident and confusing Discard with Delete.

13.2.1: `ConfirmModal` still accepts `confirmationText` (`ConfirmModal.tsx:31`) and upstream itself
now uses it in several alerting modals (`folder-actions/DeleteModal.tsx:52`,
`notification-policies/components/Modals.tsx:75`). `RuleActionsButtons.tsx` still exists;
`AlertRuleForm.tsx` moved to `rule-editor/alert-rule-form/AlertRuleForm.tsx`;
`UnsavedChangesModal.tsx` and `SaveLibraryPanelModal.tsx` are gone (11.6.5 already retargeted to
`FormPrompt.tsx`, `dashboard-scene/saving/DashboardPrompt.tsx`,
`dashboard-scene/panel-edit/SaveLibraryVizPanelModal.tsx`, `rule-viewer/DeleteModal.tsx`).
**(b) from 11.6.5**, and check whether upstream already added confirmation to the rule-delete path —
if it did, this becomes **(d)**.

**D4. External alert-rule write removed from the Editor role.** `pkg/services/ngalert/accesscontrol.go`
comments out the `ActionAlertingRuleExternalWrite` grant. Not covered by any PR body I found; the
intent is presumably to stop Lagoon editors writing rules to external (non-Grafana) rulers, since
Lagoon only has Harvest.

13.2.1: the file moved to `pkg/services/ngalert/accesscontrol/roles.go` and the grant is at line 63.
**(b)**, one hunk. The 11.6.5 version is nicer (leaves the block commented with an explanatory note
rather than deleting).

**D5. Redis HA alerting backport.** PR **#23** (`soracom-add-redis-alerting-backport`, 9 files,
+834/−15): `redis_peer.go` (595), `redis_channel.go` (65), `redis_channel_test.go` (64),
`multiorg_alertmanager.go` refactor (+51/−21), six `HARedis*` settings, `conf/defaults.ini` and
`conf/sample.ini` entries, `go.mod` gaining `redis/go-redis/v9` and `miniredis/v2`.

13.2.1: **fully native.** `git log --diff-filter=A` on `redis_peer.go` in the v13.2.1 history gives
`bc11a484ed9 Alerting: Add support for running HA using Redis (#65267)`. v13.2.1 has every
`ha_redis_*` key the backport added *plus* `ha_redis_cluster_mode_enabled`,
`ha_redis_sentinel_mode_enabled`, sentinel master/username/password, `ha_redis_max_conns`, and a
full `ha_redis_tls_*` block. **(d) — drop ~700 lines, keep the ini values.** This is the single
biggest deletion available.

**D6. Screenshot render timeout.** PR **#46** (`sc-158732`): `pkg/services/ngalert/image/service.go`
hardcoded `screenshotTimeout = 10 * time.Second` → `20`.

13.2.1: `screenshotTimeout` is now a field read from `cfg.UnifiedAlerting.Screenshots.CaptureTimeout`
(`image/service.go:97`), configured by `[unified_alerting.screenshots] capture_timeout`
(`conf/defaults.ini:1708`, default `10s`). **Important caveat:** `setting_unified_alerting.go:536`
enforces a **maximum of 30s** (`screenshotsMaxCaptureTimeout`), so 20s is fine but anything higher
would be rejected at startup. **(d) — becomes a one-line ini setting.**

**D7. Alert-rule quota off-by-one.** `pkg/services/quota/quotaimpl/quota.go` (+6/−2): for the
`ngalert:alert_rule:org` target only, the check becomes `u > limit` instead of `u >= limit`.
Not covered by a PR body. My read is that Lagoon's `org_alert_rule = 10` was effectively giving
customers 9 rules and someone fixed it in the least invasive place; that is an inference, not a
documented reason.

13.2.1: `CheckQuotaReached` still exists (`quotaimpl/quota.go:194`) with the same shape. **(a)/(b)**.
Worth reconsidering — bumping the ini limit to 11 would be less surprising than a per-target
comparison special case.

**D8. Webhook/e-mail send logging + drop the placeholder address.**
`pkg/services/notifications/notifications.go` (+22): logs every outgoing notification webhook URL
and e-mail address+subject at INFO, and `removeDefaultEmail` silently drops anything addressed to
`example@email.com` (returning an error if that leaves the recipient list empty).

13.2.1: `notifications.go` still exists. **(a)/(b)**. Note the `example@email.com` filter is a
guard against Grafana's own placeholder contact point spamming a real address; check whether
13.2.1 still ships that default before porting.

**Dependencies.** D2 needs the alerting-form work done; D5/D6 are deletions and can be done first
and independently. D1 is the riskiest and should be settled with Shogo before anyone codes it.

---

### Group E — Data, dashboards and panel UX

**E1. `Series joined by time` as the default Inspect → Data view.** PRs **#18** / **#35**.
One line: `InspectDataTab.tsx` `selectedDataFrame: 0` → `DataTransformerID.joinByField`.
From shortcut story 91611 — customers exporting CSV got one series per file instead of a joined
table.

13.2.1: `InspectDataTab.tsx` still exists; `selectedDataFrame: number | DataTransformerID` at
line 48, initialised to `0` at line 61, and `joinByField` is handled at lines 88 and 166.
**(a) — a genuinely one-line re-apply.**

**E2. Query-variable regex meta-flag.** PRs **#25** / **#41**. `public/app/features/variables/query/reducer.ts`
(+59/−5) adds a `MetaFlag` enum (`name` / `id` / none) and `stringToMetaFlagAndRegex`, so a query
variable's regex can be written `name/.*sim.*/` to match against the display text rather than the
value (default, and `id/`, match the value). 56 lines of table-driven tests.

**Why:** Harvest resources have an opaque id (`d-bv172aeaukdipr6kdt9a`) as the value and a
human name as the text; Grafana's regex only ever matched the value, so customers couldn't filter
their device list by name.

13.2.1: `metricNamesToVariableValues` still exists (`reducer.ts:105`) with `stringToJsRegex` at
110 and `getAllMatches(value, regex)` at 127 — structurally identical. **(a)/(b).** The one thing
to check is whether the *scenes* variable path still routes through this reducer, or whether
`@grafana/scenes` has its own regex handling that would also need the flag. Unverified — worth a
check before assuming (a). **Flagging as a porting-time verification, not a blocker.**

**E3. Inject Harvest template variables into every new dashboard.** PRs **#30** / **#43**.
`initDashboard.ts` (+76): the new-dashboard model gains four chained query variables against
`harvest-backend-datasource` — `resource_types`, `groups`, `resources`
(`$resource_types?group=$groups`), `properties` (`$resource_types||$resources`).

**Why:** PR #30's body — "This obviates the need for our customers to each create their own
template variables for relatively common queries."

13.2.1: `initDashboard.ts` is **gone** (scenes). The equivalent is
`public/app/features/dashboard-scene/serialization/buildNewDashboardSaveModel.ts`, which already
builds a `variablesList` and appends adhoc/groupby variables under a feature toggle — a natural
insertion point. PR #43's body says the 11.6.x version was "re-written for the 11.6.x merge-base
to fit the new method of dashboard initialization. Only applied for v1 schema dashboards, as v2
schema dashboards are still experimental in this release." **In v13.2.1 the v2 schema is no longer
experimental** — `buildNewDashboardSaveModel.ts` imports `Spec as DashboardV2Spec` from
`@grafana/schema/apis/dashboard.grafana.app/v2` and there is a
`dashboardAPIVersionResolver`. **(c)** — the v2 path now has to be covered too, which PR #43
explicitly did not do. This is the largest genuinely-new frontend work in the port.

**E4. Resample point cap.** `pkg/expr/commands.go` (+22): a package-level `ResampleMaxPoints = 2500`
overridable by `LAGOON_RESAMPLE_MAX_POINTS`, and `NewResampleCommand` now rejects a window that
would produce more points than that over the selected range.

**Why** (inferred): a customer setting a 1s resample window over 30 days would OOM the server.

13.2.1: `NewResampleCommand` still exists (`expr/commands.go:229`) but the signature changed —
`downsampler` is now `mathexp.ReducerID` and `upsampler` is `mathexp.Upsampler`, not strings.
**(b)**, small.

**E5. TimeSeries series-index fix.** `packages/grafana-ui/src/components/TimeSeries/utils.ts`
(−5) plus `public/app/plugins/panel/timeseries/utils.ts` (+18) and a test (+16), moving
`seriesIndex` assignment out of the plot-config builder into a `setClassicPaletteIdxs` pass.

13.2.1: `setClassicPaletteIdxs` is **upstream**, exported from
`public/app/plugins/panel/timeseries/utils.ts:288` with a `skipFieldIdx` parameter and
identity-keyed handling for comparison series. `git log -S` identifies the origin as
`b2c01757776 TimeSeries: Fix legend and tooltip colors changing after data refreshes (#63823)` —
and one of the three upstream commits SORACOM pulled onto the release branch is its 9.3.x
backport `#63870`. **(d) — pure upstream backport, drop it.**

**E6. Password-migration hack.** `pkg/services/sqlstore/user.go` (+14/−8): if
`CreateUserCommand.Password` starts with the magic string `lagoon-migrate:salt10:` the next 10
chars are taken as the salt and the rest as an already-encoded password, bypassing
`util.EncodePassword`.

**Why:** carrying Lagoon 2 password hashes into Lagoon 3 without forcing every customer to reset.

13.2.1: `pkg/services/sqlstore/user.go:88` still calls `util.EncodePassword(string(args.Password), usr.Salt)`
— note `args.Password` is now a typed `user.Password`, not a string. **(b)**, small. But this is
**(e)** in a bigger sense: is a Lagoon-2→4 password migration still needed at all in 2026, or is
this dead weight? **Flagging for Shogo (Q5).**

**E7. Public-dashboard hidden-query handling.** `pkg/services/publicdashboards/service/query.go`
(+12/−13): removes the `if hideAttr, exists := query.CheckGet("hide"); !exists || !hideAttr.MustBool()`
guard so hidden queries are included.

**Why** (inferred): a panel using an expression needs its hidden source queries executed, and
upstream's blanket skip broke those panels on public dashboards.

13.2.1: the file moved to `pkg/services/publicdashboards/internal/service/query.go`, and
`extractQueriesFromPanels` at line 332 now reads
`if !hasExpression && query.Get("hide").MustBool() { continue }` — **upstream fixed exactly this
case properly**, with the comment "the expression handler will take care later of removing hidden
queries which could be necessary to calculate the value of other queries". **(d)** — drop the
patch, but verify the behaviour on a real Lagoon expression panel before declaring victory.

**E8. `gsutil.go` path change.** `pkg/build/gcloud/storage/gsutil.go` (+1/−1): `filepath.Join(destPath, file.PathTrimmed)`
→ `file.PathTrimmed`. This is in Grafana's own release-tooling package, which Lagoon doesn't use.
Almost certainly incidental. **(e) — recommend dropping, but confirm nobody depends on it.**

---

### Group F — Logging and operations

**F1. Firehose log destination.** PRs **#8** / **#33**. New `pkg/infra/log/firehose.go` (163 lines):
a `FirehoseWriter` implementing `io.Writer` that buffers records on a channel, flushes every 15s
or at 500 records via `PutRecordBatch`, and a `case "firehose"` in `ReadLoggingConfig` reading
`stream` and `region` from a new `[log.firehose]` ini section (added to `conf/defaults.ini`).
Feeds SORACOM's Lochlog.

13.2.1: `pkg/infra/log/log.go` `ReadLoggingConfig` still has the identical
`switch mode { case "console" / "file" / "syslog" }` structure at lines 470–500 — the new case
slots straight in. **(b), close to (a).**

The dependency is the catch. `firehose.go` imports `github.com/aws/aws-sdk-go/...` (SDK **v1**).
In v13.2.1's `go.mod`, `github.com/aws/aws-sdk-go v1.55.8` is present but marked `// indirect`;
the *direct* AWS dependencies are all `aws-sdk-go-v2` (`v1.42.1` and friends), and there is no
`service/firehose` module in the list. So the port has two options: promote v1 to a direct
requirement (compiles today, but v1 is not where AWS is investing — **check the current v1 support
status before committing to it, don't take my word for it**), or rewrite ~40 lines against
`aws-sdk-go-v2/service/firehose`. I'd recommend v2. **(b), with a dependency decision.**

Also note 11.6.5's version of this patch bundles an unrelated change: it rewrites
`ConcreteLogger.log` to wrap every call in `gokitlog.With(&cl.SwapLogger, "timestamp", ...)`,
reverting an upstream optimisation. v13.2.1's `log.go:217` has the lean upstream version. That
timestamp rewrite is a per-log-call allocation and I would not carry it forward without
understanding why it was added (the vestigial `TimestampLogHandler` type in `firehose.go`, whose
`Log` method is a pass-through with a TODO, suggests the intent was to rename the `time` key to
`timestamp` for Firehose/Athena and it was never finished). **(e) — flagging (Q6).**

**F2. Plugin logs at INFO.** `grpcplugin/log_wrapper.go` (+2/−2): `hclog.Debug` and
`logWrapper.Debug` both route to `Info` — "we want to output all plugin logs as INFO".
`grpc_plugin.go` (+4) logs a diagnostic whenever `getPluginClient` finds a dead client.

**Why:** SORACOM's plugins (harvest-backend etc.) log at debug, and Lagoon runs at info in
production; without this, plugin logs never reach Lochlog.

13.2.1: both files still exist at the same paths. **(a)/(b)**. Consider replacing with a
per-logger level filter in config instead — `[log] filters` supports this — which would be less
invasive. Not in 11.6.5, so it must come from the 9.3.9 line.

**F3. Org quota bypass in middleware.** `pkg/middleware/quota.go` (+3): when `targetSrv == "org"`
and the quota is reached, return without erroring. Effectively disables the org quota at the
middleware layer while leaving it enforced elsewhere.

13.2.1: `pkg/middleware/quota.go:25` still has the same `c.JsonApiErr(403, ...)` line. **(a)**.
But this is **(e)** on intent: with `[quota] org_user = 5` etc. in `production.ini` and
`user_org = -1`, it isn't obvious what this bypass is protecting. **Flagging (Q7).**
Not in 11.6.5.

---

### Group G — Upstream fixes backported by SORACOM

Both are now upstream in 13.2.1 and should simply be dropped.

**G1. PR #22 — dashboard delete removes permissions from other orgs.**
`soracom-9.3-fix-backports`, `pkg/services/dashboards/database/database.go` (+26/−8). A backport of
grafana/grafana#71225, for shortcut story 102539 "User permission is deleted unintentionally by
removing the same UID dashboard in a different org". Replaces `DELETE FROM permission WHERE scope = ?`
with a scoped select+delete joined on `role.org_id`.

13.2.1: the store moved but the fix is there —
`pkg/services/dashboards/service/dashboard_service.go:2433 func (dr *DashboardServiceImpl) deleteResourcePermissions(sess *db.Session, orgID int64, resourceScope string) error`.
**(d).**

**G2. E5 above** (TimeSeries series index). **(d).**

---

### Group H — Build, deployment and developer environment

PRs **#4** / **#29** / **#32** (`add_deployment_stuff` 28 files +1769;
`soracom-v11.6.2/development-and-deployment` 36 files +3182) and **#24**
(`soracom-dev-tools`, 22 files +1547).

**What it does.**

- `Dockerfile.lagoon` (102 lines on 9.3.9) — a three-stage build (node js-builder, go go-builder,
  node runtime) from `public.ecr.aws/docker/library/*`, pinning node 16-alpine3.15 and
  golang 1.19.3-alpine3.15, with `ARG CONFIG_FILE=production.ini` selecting which conf to install
  as `/etc/grafana/grafana.ini`, and `COPY ./scripts/build-soracom/plugins/. ${GF_PATHS_PLUGINS}/`.
- `buildspec.yml` (53 lines) — AWS CodeBuild: pulls six deploy-key pairs from SSM Parameter Store,
  writes them to `scripts/build-soracom/deploy_keys/<plugin>/id_rsa`, logs into ECR, computes an
  image tag `G9-<7charsha>` (or `G9-master-<sha>` on master), runs `fetch_plugins.sh`, builds and
  pushes.
- `scripts/build-soracom/fetch_plugins.sh` (154 lines) — clones the private SORACOM plugin repos
  **by pinned commit** over SSH with per-repo deploy keys (`clone_private_repo soracom-harvest-backend
  1191b9585160af84d5cabccdc7194496caf3bfbd`), pulls three others as versioned zips from
  `s3://lagoon-plugins/`, runs each repo's `signplugin.sh`, and `rm -rf`s the `.git` dirs so they
  don't land in the image. Also copies `pre-built-plugins/` (the vendored grafana-clock-panel).
- `scripts/build-soracom/precheck.sh` — a build-time guard that greps the source for
  `ALERT_DISABLED` and `filterAdminUsers` and fails the build if either is missing. A blunt but
  effective regression tripwire for two patches that would silently disappear on a bad rebase.
- `.devcontainer/` (Dockerfile, devcontainer.json, README, checkenv) — Go 1.21 bookworm base
  (comment: "Using 1.21 because a wire used by Grafana sigsegvs on 1.22 —
  https://github.com/google/wire/issues/400"), node 16, bind mounts for `LAGOON_HOST_DATA_DIR`
  and `LAGOON_HOST_PLUGINS_DIR`, plus the Claude Code devcontainer feature and `~/.claude` mounts.
- `.vscode/launch.json`, `.bra.toml`, `Makefile` `gen-cue` tweak.

**Why the commit pinning exists** — PR #29's body is explicit: "to prevent cases where features
merged into the master branch of given plug-ins are blocking the release of hot-fixes or
bug-fixes due to documentation or change-logs not being ready."

**Porting assessment: (b) overall, and much better than it looks.** The 11.6.5 branch already
rewrote `Dockerfile.lagoon` from 102 lines to 228 and restructured it to mirror upstream's own
`Dockerfile` — ARG-driven, with `alpine-base` / `ubuntu-base` / `go-builder-base` / `js-builder-base`
stages, exactly the shape v13.2.1's `Dockerfile` still has. That means the 13.2.1 port is largely
a matter of bumping ARGs and re-applying the plugin COPY and CONFIG_FILE arg.

**Version bumps required (checked against the v13.2.1 tree, not recalled):**

| thing | Lagoon 11.6.5 | upstream v13.2.1 | source |
|---|---|---|---|
| Go | `golang:1.24.6-alpine` | `golang:1.26.6-alpine` | `v13.2.1:Dockerfile:18`; `go.mod` says `go 1.26.6` |
| Node (build) | `node:22-alpine` | `node:24-alpine` | `v13.2.1:Dockerfile:19`; `.nvmrc` is `v24.11.0`; `package.json` engines `">= 22 <25"` |
| alpine | `alpine:3.21.3` | `alpine:3.24.1` | `v13.2.1:Dockerfile:16` |
| ubuntu | `ubuntu:22.04` | `ubuntu:24.04` | `v13.2.1:Dockerfile:17` |
| yarn | — | `yarn@4.17.1` | `v13.2.1:package.json` `packageManager` |

The devcontainer is the worst-affected: Go 1.21 and Node 16 are both far below what v13.2.1 needs,
and the wire/Go-1.22 workaround comment is three years stale. It needs rebuilding rather than
porting. Also note v13.2.1 adds a `distroless/static-debian13` stage that Lagoon's runtime image
(currently `node:alpine3.15`, which is odd for a Go server) may want to adopt.

`buildspec.yml` and `fetch_plugins.sh` are Lagoon-owned and carry over unchanged except for the
image-tag prefix (`G9-` → presumably `G13-`) and the plugin commit pins, which all need to be
re-resolved against plugin versions that actually work with Grafana 13's plugin API. **That last
point is a whole separate risk that this task does not cover** — see Q8.

---

### Group I — Config defaults and DB migrations

**I1. `conf/development.ini` and `conf/production.ini`** (1166 + 1163 lines, new files).
These are **copies of an older upstream `sample.ini`** (they still describe `lockingMigration`,
`https://grafana.net`, and Grafana 9-era angular wording), with a set of values changed. Diffed
against the release branch's own `sample.ini`, the Lagoon-specific settings are:

*production.ini:* `[database] type = mysql`, `name = lagoon`; `[snapshots] external_enabled = false`;
`[users] editors_can_admin = true`; `[quota] enabled = true` with `org_user = 5`,
`org_dashboard = 3`, `org_data_source = 2`, `org_api_key = 0`, `org_alert_rule = 10`,
`user_org = -1`; `[unified_alerting] enabled = true`, **`execute_alerts = false`**;
`[unified_alerting.screenshots] capture = true`, `max_concurrent_screenshots = 5`,
`upload_external_image_storage = true`; `[alerting] execute_alerts = false`; `[log] level` commented.

*development.ini:* `app_mode = development`, sqlite3, `data = /grafana/data`,
`plugins = /grafana/plugins`, `[quota] enabled = false` plus `global_file = 1000`, same alerting
block.

`execute_alerts = false` in the production config is worth a second look — it means the instance
this config is for does not evaluate alert rules, which implies a separate alerting instance (or
that alerting evaluation is genuinely off). **(e)** — I could not determine which from the repo.
**Flagging (Q9).**

**Porting: (c) for the files, (a) for the values.** Do not carry these files forward. Regenerate
them from v13.2.1's `conf/sample.ini` and re-apply the ~25 settings above — otherwise Lagoon 4
ships with three years of stale comments and misses every new setting. This is also the natural
home for `ha_redis_*` (replacing the D5 backport) and `capture_timeout = 20s` (replacing D6).

**I2. `[log.firehose]` section** in `conf/defaults.ini` (+7). Goes with F1. **(a)**

**I3. Soracom DB migration.** `pkg/services/sqlstore/migrations/soracom_mig.go` (8 lines) — two
raw SQL migrations renaming the `harvest-backend-datasource` datasource from `Harvest` to
`Soracom` and the matching `secrets.namespace`, hooked in from `migrations.go` (+3).

13.2.1: `migrations.go` still has `func (oss *OSSMigrations) AddMigration(mg *Migrator)` at line 36
with the same `xxx.AddMigration(mg)` call pattern. **(a)/(b)** — mechanically easy. But **(e) on
whether it's still wanted**: these migrations ran once against Lagoon 3 databases, and whether
Lagoon 4 inherits that database or starts fresh determines whether they're needed at all.
**Flagging (Q10).** Not in 11.6.5.

**I4. `go.mod` / `go.sum`.** 9.3.9 adds `redis/go-redis/v9`, `alicebob/miniredis/v2`,
`alicebob/gopher-json`, `yuin/gopher-lua`, and bumps `cespare/xxhash/v2`. All of that exists
purely to serve the Redis HA backport, which is obsolete (D5) — v13.2.1 already has
`redis/go-redis/v9 v9.19.0` and `miniredis/v2 v2.38.0` as direct deps. **(d) — nothing to port.**
The only real go.mod work is the Firehose AWS SDK decision (F1).

**I5. Misc.** `lerna.json` (formatting + version string), `CHANGELOG.md` (+6, a stub 9.3.8 entry),
`Makefile` `gen-cue` (`go generate CueSchemaFS` replacing four explicit `go generate` calls —
almost certainly a local hack; v13.2.1's codegen is completely different), `.gitignore`
(`/scripts/build-soracom/plugins`, `.cache/*`), `.bra.toml` and `.vscode/launch.json`
(point at `conf/development.ini`). All **(a)** or **(d)**; the Makefile one is **(d)**.

---

### Group J — Features that exist only as PRs and are NOT in production

Verified by content against the 9.3.9 release-branch diff, not by branch ancestry.

| PR | branch | size | in prod? | notes |
|---|---|---|---|---|
| #1 | `add_dashboard_org_apis` | — | no | closed 2022-04-04, WIP, empty description |
| #2 | `add_live_snapshots` | 11 files, +444/−13 | **no** | "snapshots using the same key … data dynamically updated by a lambda chrome instance"; `pkg/api/lagoon/lagoon.go` (227 lines, a *different* `pkg/…/lagoon` from the one in prod), `dashboardsnapshots` store/model/service changes, `ShareSnapshot.tsx` (+88). Still open. |
| #3 | `securejson_db_migration` | 1 file, +10/−6 | **no** | comments out upstream datasource types and adds `soracom-harvest-datasource` to the CLI secure-json re-encryption migration, mapping `password`→`authKey`. PR body: **"NOT REQUIRED ANY MORE because we are launching as new service, not upgrading existing."** |
| #7 | `soracom-add-permission-fix` | 4 files, +29/−9 | **no** | Lagoon 2-era viewer-scoping. PR title literally "[Not needed?]"; body says superseded by RBAC. |
| #9 | `soracom-disable-notifications-test-patch` | 2 files, +16/−4 | **no** | `LAGOON_SEND_NOTIFICATIONS` env gate. Title "[Not needed?]". Confirmed absent: `git grep -l LAGOON_SEND_NOTIFICATIONS origin/soracom-release-9.3.9` → nothing. |
| #19 | `soracom-add-japanese-localisation` | 3 files, +541/−1 | **no** | `public/locales/ja-JP/grafana.json` (533 lines) + `internationalization/constants.ts` + parser config |
| #20 | `soracom-temp-add-japanese-9.3` | — | no | closed, "Hackathon version" |
| #21 | `add-codeowners` | — | no | closed; superseded — the 11.6.x branches all trim `.github/CODEOWNERS` by 840 lines |

**PR #19 is now obsolete: (d).** v13.2.1 ships `ja-JP` natively —
`packages/grafana-i18n/src/constants.ts:8 export const JAPANESE_JAPAN = 'ja-JP'`,
`languages.ts:43 { code: JAPANESE_JAPAN, name: '日本語' }`, and a full
`public/locales/ja-JP/grafana.json`. Grafana went from 7 `public/locales/*/grafana.json` files in upstream v11.6.5 to 19 in v13.2.1. What
remains is only the **Lagoon-specific** strings, which is a much smaller job — and the 11.6.5
branch's locale edits show the shape of it.

**PRs #2 and #3 need a decision. (e).** #2 is a real feature (live-updating snapshots backed by a
Lambda Chrome instance) that never shipped; #3 is self-declared unnecessary.
**Flagging (Q11, Q12).**

---

## 5. Dependency graph

```
pkg/lagoon (plan model)                    ← prerequisite
   ├── frontendsettings (min refresh, public dashboards gate)
   ├── navtree (snapshots nav)
   ├── ShareModal / ShareMenu (snapshot tab)
   └── Branding.MenuLogo (customer logo)  ──┐
                                            ├── same feature, one agent
       pkg/api/images.go (logo upload API) ─┘

Branding & identity (Group A)              ← independent, no prerequisites
   └── i18n / Lagoon-specific ja-JP strings depends on it (same strings)

Build & deployment (Group H)               ← independent, but gates *testing*
   └── nothing can be run end-to-end until Dockerfile + fetch_plugins work
       └── plugin compatibility with Grafana 13 plugin API   ← UNSCOPED RISK

conf/*.ini regeneration (I1)               ← absorbs D5 (ha_redis) and D6 (capture_timeout)

Access control (Group C)                   ← independent of everything
Alerting (Group D)                         ← D2 touches the same files as A's notifier branding
Data/panel UX (Group E)                    ← E3 is the big one, independent
Logging (Group F)                          ← F1 needs an AWS SDK decision first
```

The only hard ordering constraint is `pkg/lagoon` before its four consumers. Everything else is
parallelisable; the collisions to watch are Group A and D2 both editing `ChannelSubForm.tsx`, and
Group A and Group B both editing `Branding.tsx` and the share modal.

---

## 6. What is already obsolete — the deletions available

Summarised for convenience; details in the groups above. All verified against the v13.2.1 tree.

| item | evidence | lines dropped |
|---|---|---|
| Redis HA alerting backport (PR #23) | upstream `bc11a484ed9 … (#65267)`; v13.2.1 has `ha_redis_*` + cluster + sentinel + TLS | ~700 + 4 go.mod deps |
| Render timeout hardcode (PR #46) | `[unified_alerting.screenshots] capture_timeout`, `conf/defaults.ini:1708`, max 30s | 1 (becomes config) |
| TimeSeries series index | upstream `b2c01757776 … (#63823)` | ~39 |
| Dashboard-delete permission fix (PR #22) | `dashboard_service.go:2433 deleteResourcePermissions` | ~26 |
| Japanese localisation (PR #19) | `grafana-i18n/src/languages.ts:43`, full `locales/ja-JP/` | ~533 |
| Public-dashboard `hide` handling | `internal/service/query.go:332` with `!hasExpression` guard | ~25 |
| Legacy alerting notifier branding | `pkg/services/alerting/` gone from v13.2.1 | ~14 |
| LINE `alert []string` mechanism | `utils/notifier-versions.ts`, `NotifierDTO.deprecated` | ~20 (content survives) |
| Public dashboards footer patch | `DashboardBrandingFooter.tsx` `text`/`logoUrl`/`linkUrl` props | ~6 (becomes config) |
| Snapshot plan gating mechanism | `config.snapshotEnabled` + `AccessControlAction.SnapshotsCreate` | ~10 (becomes RBAC) |
| go.mod redis additions | v13.2.1 has go-redis v9.19.0, miniredis v2.38.0 | 4 deps |

Roughly **1400 of the ~1500 real Lagoon lines in the 9.3.9 diff are either obsolete or already
ported to 11.6.5.** The genuinely new work for 13.2.1 is Group E3 (scenes dashboard init incl. v2
schema), the notifier-branding re-design (A), the k8s org-user filtering path (C1), and the build.

---

## 7. Proposed porting order

**Phase 0 — foundations (serial, one agent, blocks everything else)**

0.1 Stand up the lagoon4-poc repo on v13.2.1, with `Dockerfile.lagoon`, `buildspec.yml`,
`fetch_plugins.sh`, `precheck.sh` and a rebuilt `.devcontainer` (Go 1.26.6, Node 24, yarn 4.17.1).
Regenerate `conf/production.ini` / `conf/development.ini` from v13.2.1's `sample.ini` with the
values from §I1, plus `ha_redis_*` and `capture_timeout = 20s`.
0.2 Port `pkg/lagoon/lagoon.go` on its own, with tests.

Nothing downstream can be *verified* until 0.1 builds, so this is genuinely blocking.

**Phase 1 — five parallel workstreams**

| # | agent | scope | files it owns |
|---|---|---|---|
| 1 | branding | Group A minus notifiers | `setting.go`, `index.go`, `Branding.tsx`, `Footer.tsx`, `MegaMenuHeader.tsx`, `SingleTopBar.tsx`, `index.html`, `Welcome.tsx`, `home.json`, `public/img/*`, `emails/**`, `public/emails/**` |
| 2 | plan gating | Group B consumers | `frontendsettings/`, `navtree.go`, `ShareMenu.tsx`, `share-snapshot/`, `accesscontrol.go`, `images.go`, `api.go` |
| 3 | access control | Group C (all four) | `teamapi/team_members.go`, `iam/team/rest_members.go`, `org_users.go`, `resourcepermissions/{api,service}.go`, `Permissions.tsx`, `AddPermission.tsx` |
| 4 | alerting | Group D minus D5/D6 (obsolete) | `ngalert/store/alert_rule.go`, `ngalert/accesscontrol/roles.go`, `ChannelSubForm.tsx`, `RuleActionsButtons.tsx`, `alert-rule-form/`, `quotaimpl/quota.go`, `notifications.go` |
| 5 | data & panels | Group E | `InspectDataTab.tsx`, `variables/query/reducer.ts`, `buildNewDashboardSaveModel.ts`, `expr/commands.go`, `sqlstore/user.go` |

**Phase 2 — needs Phase 1 landed or a decision**

- Logging (F1/F2/F3) — needs the AWS SDK decision (Q6) and touches `log.go`, which nothing else does.
- Notifier branding re-design (A, the `grafana/alerting` module part) — needs Q4 answered.
- Soracom DB migration (I3) — needs Q10 answered.
- Lagoon-specific ja-JP strings — needs workstream 1 landed (same strings).

**Phase 3**

- `precheck.sh` grep guards updated to whatever the new function/constant names are. Do this last,
  and extend it: the existing two guards caught exactly the two patches most likely to be lost in a
  rebase, and there are now more of those.

Collision management: workstreams 1 and 2 both touch `Branding.tsx` and the share path; workstreams
1 and 4 both touch `ChannelSubForm.tsx`. Give `Branding.tsx` to 1 and have 2 consume it; give
`ChannelSubForm.tsx` to 4 and have 1 stay out of alerting UI entirely.

---

## 8. Open questions for Shogo

Numbered so they can be answered in one reply.

**Q1 — public dashboards plan gate.** The `publicDashboards` feature toggle no longer exists in
v13.2.1 (public dashboards went GA; only `publicDashboardsEmailSharing` remains, and there's a
`[public_dashboards] enabled` config). The current per-org bootdata override has nothing to
override. Options: (a) grant/withhold `dashboards.public:write` per org via RBAC — cleanest,
survives upgrades; (b) keep a bootdata mutation against a different key; (c) drop plan gating on
public dashboards. Which?

**Q2 — hiding SORACOM operators from customers.** `getOrgUsersHelper` is gone; v13.2.1 has
`searchOrgUsersHelper` plus two k8s/apiserver-backed paths. Do we re-apply `filterAdminUsers`
across all three, push it into the org service, or switch to upstream's own
`[users] hidden_users` + `dtos.IsHiddenUser` mechanism (`pkg/api/dtos/models.go:141`,
`conf/defaults.ini:720`), which does nearly the same thing?

**Q3 — `ALERT_DISABLED`.** This was written to stop paying for Lagoon 2 alert rules that were
migrated but unwanted. Grafana now supports `is_paused` on alert rules natively (`ngalert/models/alert_rule.go:380`, queryable at `store/alert_rule.go:1193`). Can we replace
the SQL patch with a one-off migration that sets `is_paused` on anything labelled `ALERT_DISABLED`?
If not, what else relies on the label?

**Q4 — notifier branding.** Slack/Discord/Google Chat/VictorOps footers currently say
`"Lagoon v3 - <version>"` with a Lagoon icon. Those notifiers now live in the
`github.com/grafana/alerting` Go module, not in the Grafana tree. Options: fork the module (ongoing
cost), find a template/config override, or accept Grafana-branded notifier footers in Lagoon 4.
How much does the branding there matter to us?

**Q5 — `lagoon-migrate:salt10:` password import.** Is a Lagoon 2 → Lagoon 4 password migration
still in scope in 2026, or can this go?

**Q6 — Firehose logger.** `pkg/infra/log/firehose.go` uses AWS SDK **v1**, which v13.2.1 carries
only as an indirect dependency. Rewrite against `aws-sdk-go-v2/service/firehose`, or promote v1 to
direct? Separately: the 11.6.5 branch pairs the firehose patch with a rewrite of
`ConcreteLogger.log` that wraps every log call in `gokitlog.With(..., "timestamp", ...)`, reverting
an upstream optimisation. The half-finished `TimestampLogHandler` type suggests the goal was
renaming the `time` key to `timestamp` for Lochlog/Athena. Is that still needed, and is there a
cheaper way?

**Q7 — org quota bypass.** `pkg/middleware/quota.go` silently succeeds when the `org` quota is
reached. With `[quota] user_org = -1` and `org_user = 5` already in `production.ini`, it isn't
obvious what this is for. Do we still need it?

**Q8 — plugin compatibility (out of scope for this task, but it gates everything).**
`fetch_plugins.sh` pins `soracom-harvest-backend` and `soracom-plot-panel` by commit and pulls
`soracom-dynamic-image-panel` 2.1.0, `soracom-image-panel` 2.0.1, `soracom-map-panel` 2.0.0 from
S3, plus a vendored `grafana-clock-panel`. None of these have been checked against Grafana 13's
plugin API. Should a stream be opened for that? Nothing in Lagoon 4 can be run end-to-end until
it is.

**Q9 — `execute_alerts = false` in `production.ini`.** Both `[alerting]` and `[unified_alerting]`
have it set to false in the production config. Does the production Lagoon 3 config actually run
with alerting evaluation off, or is this config file not the one in use (e.g. overridden by env
vars in ECS)? It matters for whether the Redis HA work is needed at all in Lagoon 4.

**Q10 — `soracom_mig.go`.** The two raw-SQL migrations rename the Harvest datasource to `Soracom`.
Does Lagoon 4 inherit the Lagoon 3 database, or start fresh? If fresh, these can go.

**Q11 — PR #2, live snapshotting.** 444 lines, never shipped, still open, depends on a Lambda
Chrome instance. Given the image renderer was split out into `soracom/lagoon-image-renderer`
(default branch `lambda-fy-render`), is this superseded, still wanted, or dead?

**Q12 — PRs #3, #7, #9.** All three are self-declared unnecessary in their own descriptions
("NOT REQUIRED ANY MORE", "[Not needed?]" x2). Confirm they can be closed and left out of the
inventory of things to port?

**Q13 — rendering.** The brief says rendering was split into `soracom/lagoon-image-renderer`.
Nothing in the 9.3.9 diff touches `pkg/rendering` or the renderer settings, so I found no
renderer-side Lagoon patches in this repo — but I have not looked at that repo. Is anything needed
from the Grafana side beyond `[rendering] server_url` config and the `capture_timeout` bump?

---

## 9. What I could not verify

Stated plainly rather than glossed:

- **Why** several patches exist. `pkg/middleware/quota.go`, `quotaimpl/quota.go`'s
  `ngalert:alert_rule:org` special case, `pkg/expr/commands.go`'s resample cap, the
  `publicdashboards/service/query.go` change, `pkg/build/gcloud/storage/gsutil.go`, and the
  `ConcreteLogger.log` timestamp rewrite have no PR, no issue reference and no explanatory commit
  message. Where I've offered a reason above I've marked it as inferred.
- **Whether the scenes variable path still routes through `variables/query/reducer.ts`** (E2). The
  file and function are unchanged in v13.2.1, but `@grafana/scenes` may have its own regex
  handling that would also need the meta-flag. Unverified.
- **Whether v13.2.1 still ships an `example@email.com` default contact point** (D8). Not checked.
- **Plugin compatibility** with Grafana 13 (Q8). Entirely out of scope here and entirely unverified.
- **Anything in `soracom/lagoon-image-renderer`** (Q13). Not examined.
- **Whether `soracom-release-11.6.5` builds or was ever deployed.** I read its tree; I did not
  build it. Its last commits are Dockerfile fixes, which suggests it was being actively debugged
  when work stopped in September 2025.
- **Current AWS SDK for Go v1 support status** (F1/Q6). v13.2.1 carries `v1.55.8` as an indirect
  dependency — that is the only fact I verified. Someone should check AWS's current position
  before choosing v1 over v2 rather than relying on any of our recollections.

---

## Appendix A — PR → feature → 11.6.x branch → classification

Every PR in soracom/grafana, open and closed. "In prod" = content present in the
`v9.3.9...origin/soracom-release-9.3.9` file diff, not branch ancestry.

| PR | state | title | feature / section | 9.3.9-era branch | 11.6.x PR / branch | in prod | class |
|---|---|---|---|---|---|---|---|
| #1 | closed | [WIP] Add dashboard org apis | — | `add_dashboard_org_apis` | — | no | drop |
| #2 | open | Add live snapshotting | §J | `add_live_snapshots` | — | no | (e) Q11 |
| #3 | open | [WIP] Internal use util change | §J | `securejson_db_migration` | — | no | (e) Q12 |
| #4 | open | Add deployment stuff | §H | `add_deployment_stuff` | #32 `soracom-v11.6.2/development-and-deployment` | yes | (b) |
| #5 | open | Add lagoon email changes | §A | `soracom_add_email_templates` | #40 `.../modify-email-templates` | yes | (b) |
| #6 | open | Soracom add logos and branding | §A | `soracom_add_logos_and_branding` | #34 `.../add-logos-and-branding` | yes | (b) |
| #7 | open | [Not needed?] Modify the permission system | §J | `soracom-add-permission-fix` | — | no | (e) Q12 |
| #8 | open | Add firehose logging destination | §F1 | `soracom-add-firehose-logging` | #33 `.../add-firehose-logging` | yes | (b) |
| #9 | open | [Not needed?] Disable sending notifications | §J | `soracom-disable-notifications-test-patch` | — | no | (e) Q12 |
| #10 | open | Allow editors to publish dashboards | §B | `soracom-enable-editors-to-publish-public-dashboards` | folded into #36 | yes | (b) |
| #11 | open | Filter users in the permission list | §C1 | `soracom-add-admin-user-filtering` | #37 `.../add-admin-user-filtering` | yes | (b)/(c) Q2 |
| #12 | open | Soracom add lagoon settings | §B | `soracom-add-lagoon-settings` | #36 `.../add-lagoon-settings` | yes | (b)/(c) Q1 |
| #13 | closed | Disable alerts with label (superseded) | §D1 | `soracom-add-ability-to-disable-alerts-with-label` | — | superseded by #14 | — |
| #14 | open | Disable alert execution with label | §D1 | `soracom-disable-alerts-with-label` | #39 `.../disable-alerts-with-label` | yes | (b)/(c) Q3 |
| #15 | open | Email Templates | §A | `soracom-modify-email-templates` | #40 | yes | (b) |
| #16 | open | Add image link api | §B | `soracom-add-image-link` | #38 `.../add-image-link` | yes | (b) |
| #17 | open | Change icons and text for all alerts | §A/§D | `soracom-add-lagoon-icons-to-alerts` | — | yes | (c) Q4 |
| #18 | open | Make join by field the default | §E1 | `soracom-make-inspect-tab-joinbyfield-default` | #35 `.../make-csv-joinbyfield-default` | yes | (a) |
| #19 | open | Add Japanese Translation | §J | `soracom-add-japanese-localisation` | — | **no** | (d) |
| #20 | closed | Hackathon version | — | `soracom-temp-add-japanese-9.3` | — | no | drop |
| #21 | closed | Replace with soracom's CODEOWNERS | §H | `add-codeowners` | 11.6.x branches trim CODEOWNERS | no | (b) |
| #22 | open | Permission fix deleting dashboards with same UID | §G1 | `soracom-9.3-fix-backports` | — | yes | (d) |
| #23 | open | Add redis alerting backport | §D5 | `soracom-add-redis-alerting-backport` | — | yes | **(d)** |
| #24 | open | Add devcontainer and developer tooling | §H | `soracom-dev-tools` | folded into #32 | yes | (b) rebuild |
| #25 | open | Regex meta-flag for query variables | §E2 | `soracom-regex-meta-flag` | #41 `.../regex-meta-flag` | yes | (a)/(b) |
| #26 | closed | LINE Notify EOL alert | §D2 | `soracom-add-line-deprecation-message` | — | superseded by #28 | — |
| #27 | closed | Soracom add line deprecation message | §D2 | same branch | — | superseded by #28 | — |
| #28 | open | Soracom add line deprecation message | §D2 | `soracom-add-line-deprecation-message` | #42 `.../add-line-deprecation-message` | yes | (d)/(b) |
| #29 | closed | Fetch plug-ins by commit ID | §H | `add_deployment_stuff` → `...-new-deployment-logic` | folded into #32 | yes | (a) |
| #30 | open | Customize dashboard initialization template | §E3 | `soracom-customize-dashboard-initialization` | #43 `.../customize-dashboard-initialization` | yes | **(c)** |
| #31 | open | Discard/Delete distinction | §D3 | `soracom-clarify-delete-vs-discard-distinction` | #44 `.../clarify-delete-vs-discard-distinction` | yes | (b) |
| #32–#44 | open | the 11.6.x port | — | — | see rows above | n/a | reference |
| #45 | closed | Teams API/access-control e-mail leak | §C3 | `codex-vuln-fix-2025-10` | — | yes | **(b) security** |
| #46 | closed | Bump render timeout 10→20s | §D6 | `sc-158732-adjust-lagoon-render-timeout` | — | yes | **(d)** |

### Changes in the 9.3.9 diff with no PR at all

These have no PR, no issue link and no explanatory commit message. Reasons given elsewhere in this
document are inferred.

| files | what | section |
|---|---|---|
| `pkg/middleware/quota.go` | org quota bypass | §F3, Q7 |
| `pkg/services/quota/quotaimpl/quota.go` | `ngalert:alert_rule:org` off-by-one | §D7 |
| `pkg/expr/commands.go` | resample point cap + `LAGOON_RESAMPLE_MAX_POINTS` | §E4 |
| `pkg/services/publicdashboards/service/query.go` | include hidden queries | §E7 |
| `pkg/services/sqlstore/user.go` | `lagoon-migrate:salt10:` password import | §E6, Q5 |
| `pkg/services/sqlstore/migrations/soracom_mig.go` | Harvest → Soracom datasource rename | §I3, Q10 |
| `pkg/services/ngalert/accesscontrol.go` | drop `ActionAlertingRuleExternalWrite` from Editor | §D4 |
| `pkg/services/notifications/notifications.go` | send logging + drop `example@email.com` | §D8 |
| `pkg/plugins/backendplugin/grpcplugin/*` | plugin logs at INFO | §F2 |
| `pkg/build/gcloud/storage/gsutil.go` | path join removed | §E8 |
| `packages/grafana-ui/.../TimeSeries/utils.ts` + `panel/timeseries/utils.ts` | series index backport | §E5 |
| `Makefile` | `go generate CueSchemaFS` | §I5 |
| `.bra.toml`, `.vscode/launch.json`, `.gitignore`, `lerna.json`, `CHANGELOG.md` | dev ergonomics | §I5 |

---

## Appendix B — every file in the 9.3.9 Lagoon diff, and whether its path still exists in v13.2.1

Generated with:

```bash
git diff --name-only v9.3.9...origin/soracom-release-9.3.9 \
  | grep -vE '^(\.yarn/|scripts/build-soracom/(plugins|pre-built-plugins)/)' \
  | while read f; do
      git cat-file -e v13.2.1:"$f" 2>/dev/null && echo "PRESENT $f" || echo "GONE    $f"
    done
```

143 paths checked: **68 PRESENT, 75 GONE**. The GONE list includes the Lagoon-owned files that were never upstream
in the first place (`.devcontainer/*`, `Dockerfile.lagoon`, `buildspec.yml`,
`conf/{development,production}.ini`, `scripts/build-soracom/*`, `pkg/lagoon/lagoon.go`,
`pkg/api/images.go`, `pkg/infra/log/firehose.go`, `soracom_mig.go`, `public/img/*lagoon*`) — those
are expected. The upstream files that moved or were deleted:

| gone from v13.2.1 | where it went |
|---|---|
| `pkg/api/frontendsettings.go` | `pkg/api/frontendsettings/frontendsettings.go` |
| `pkg/api/team_members.go` (+test) | `pkg/services/team/teamapi/team_members.go`, plus `pkg/registry/apis/iam/team/rest_members.go` |
| `pkg/services/dashboards/database/database.go` | `pkg/services/dashboards/service/dashboard_service.go` |
| `pkg/services/publicdashboards/service/query.go` | `pkg/services/publicdashboards/internal/service/query.go` |
| `pkg/services/ngalert/accesscontrol.go` | `pkg/services/ngalert/accesscontrol/roles.go` |
| `pkg/services/ngalert/notifier/channels/*` | `github.com/grafana/alerting` module |
| `pkg/services/ngalert/notifier/channels_config/*` | ditto; reshaped in `pkg/api/alerting.go` |
| `pkg/services/alerting/notifiers/*` | deleted — legacy alerting removed |
| `pkg/build/gcloud/storage/gsutil.go` | release tooling restructured |
| `packages/grafana-ui/src/components/TimeSeries/utils.ts` | `public/app/core/components/TimeSeries/utils.ts` (upstream `c6e27e00b4f Chore: Move internal GraphNG+Timeseries components into core (#77525)`); a legacy copy also survives at `packages/grafana-ui/src/graveyard/TimeSeries/utils.ts` |
| `public/views/index-template.html` | `public/views/index.html` |
| `public/app/core/components/NavBar/NavBarItemIcon.tsx` | `public/app/core/components/AppChrome/**` |
| `public/app/features/dashboard/state/initDashboard.ts` | `dashboard-scene/serialization/buildNewDashboardSaveModel.ts` |
| `.../rule-editor/AlertRuleForm.tsx` | `.../rule-editor/alert-rule-form/AlertRuleForm.tsx` |
| `.../rule-editor/rule-types/GrafanaManagedAlert.tsx` | the whole `rule-types/` directory is gone; rule-type selection was reworked. Not located — needs a look during the port |
| `.../PublicDashboardFooter/PublicDashboardsFooter.tsx` | `.../PublicDashboard/DashboardBrandingFooter.tsx` |
| `.../SaveDashboard/UnsavedChangesModal.tsx` | `dashboard-scene/saving/DashboardPrompt.tsx` / `FormPrompt.tsx` |
| `.../SaveLibraryPanelModal/SaveLibraryPanelModal.tsx` | `dashboard-scene/panel-edit/SaveLibraryVizPanelModal.tsx` |
| `public/app/types/alerting.ts` | `public/app/features/alerting/unified/types/alerting.ts` |
| `emails/templates/layouts/default.html`, `reset_password.html` | `emails/templates/partials/layout/*.mjml`, `reset_password.mjml` |
| `pkg/services/ngalert/notifier/redis_{peer,channel}.go` | **still present** — upstream's own copies (SORACOM's backport of the same feature) |

**PRESENT** (68 paths), i.e. same path in v13.2.1, notably: `pkg/setting/setting.go`,
`pkg/setting/setting_unified_alerting.go`, `pkg/api/{accesscontrol,api,index,org_users}.go`,
`pkg/expr/commands.go`, `pkg/infra/log/log.go`, `pkg/middleware/quota.go`,
`pkg/plugins/backendplugin/grpcplugin/*`, `pkg/services/accesscontrol/resourcepermissions/*`,
`pkg/services/navtree/navtreeimpl/navtree.go`, `pkg/services/ngalert/image/service.go`,
`pkg/services/ngalert/notifier/multiorg_alertmanager.go`,
`pkg/services/ngalert/store/alert_rule.go`, `pkg/services/notifications/notifications.go`,
`pkg/services/quota/quotaimpl/quota.go`, `pkg/services/sqlstore/{user.go,migrations/migrations.go}`,
`public/app/core/components/{AccessControl/*,Branding/Branding.tsx,Footer/Footer.tsx,ForgottenPassword/*}`,
`public/app/features/alerting/unified/components/{receivers/form/ChannelSubForm.tsx,rules/RuleActionsButtons.tsx}`,
`public/app/features/dashboard/components/ShareModal/ShareModal.tsx`,
`public/app/features/inspector/InspectDataTab.tsx`,
`public/app/features/profile/UserProfileEditForm.tsx`,
`public/app/features/variables/query/reducer.ts`,
`public/app/plugins/panel/{timeseries/utils.ts,welcome/Welcome.tsx}`,
`public/dashboards/home.json`, all of `public/emails/*` except the mjml sources,
`conf/{defaults,sample}.ini`, `go.mod`, `go.sum`, `Makefile`, `.gitignore`, `.vscode/launch.json`,
`lerna.json`, `CHANGELOG.md`.
