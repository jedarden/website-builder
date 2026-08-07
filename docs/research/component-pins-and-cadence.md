# Component pins, upstream cadence, and build-path facts

Research gathered 2026-08-07, before the first image release. Sources: npm
registry metadata, nodejs.org dist index, Docker Hub API, timestamped pod logs
recovered from VictoriaLogs on the CI cluster.

## Measured build-time baseline (why this image exists)

Five production `website-build` runs on 2026-08-07, phase-timed from pod logs
(consistent within ±5s across all five):

| Phase | Time |
|---|---|
| pod start, `apt-get install git`, clone | ~9s |
| `npm ci` (455 packages) | 22–25s |
| OG-card script | ~6s |
| Astro build (64 pages) | 26–31s |
| verify + Pagefind | ~1s |
| `npx wrangler@latest` download | ~21s |
| wrangler upload/deploy | ~7s |
| **Total** | **~85–101s** |

The image eliminates the apt-get and wrangler-download rows (~30s). `npm ci`
and the Astro image-transform cache are a runtime cache-PVC problem, not an
image problem (plan Phase 4). Notably: Playwright browsers are **not**
downloaded during `npm ci` in this pipeline (zero download lines in logs), so
no browser-skip provisions are needed.

## wrangler release cadence (drives the freshness-gate default)

From npm registry `time` metadata, 2026-02 → 2026-08: **68 stable releases, 58
distinct minor versions in ~6 months** — a new minor every **2–3 days**
(4.112 → 4.119 spanned July 17 → Aug 5 alone). Consequences:

- "Error when 1 minor behind" ⇒ CI red-bars roughly twice a week and demands
  an image release each time. That converts the gate from a safety net into a
  pager.
- Wrangler's minors are semver-inflated feature drips; the deploy surface
  (`pages deploy`) is stable across them.
- Default chosen: **drift budget of 10 minors (≈ 3–4 weeks)** before the gate
  errors; majors error immediately. Strictness is an env knob
  (`WRANGLER_MINOR_DRIFT_MAX`), so policy changes are a template edit, not an
  image rebuild.

## node 22 line cadence

nodejs.org dist index: 22.23.2 (2026-07-28), 22.23.1 (06-22), 22.23.0
(06-17), 22.22.3 (05-13) — a minor roughly **monthly**, usually carrying
security fixes. A strict minor-behind error here is a sane forcing function
and doubles as the security-refresh cadence for the whole image. Gate: any
minor-behind on the 22 line ⇒ ERROR.

## Base image

`node:22` full variant (not `-slim`): the image serves the *generic*
`website-build` template; other consumers (mobile-gaming's level-generation
suite) may rely on toolchain the slim variant drops. Digest at scaffold time:
`sha256:0557ac14e0d45d02ed563067b82856ca5e7aa3437fa28d98d4350ea9c3d9494a`.
Revisit `-slim` (−~850MB, faster cold-node pulls on spot) only after auditing
every consumer.

## Build & publish path (reuse, not invention)

- `miroir-release` WorkflowTemplate on the CI cluster already implements the
  full pattern to copy: Kaniko build → `ghcr.io/jedarden/<name>` with semver
  tags → GitHub Release. It authenticates via an existing `.dockerconfigjson`
  secret plus the GH token secret; `--cache-repo=<registry>/cache` gives
  Kaniko layer caching inside ghcr.
- ghcr.io/jedarden is established (miroir, trace-collector, trace-flusher),
  and argocd-image-updater is already configured for the ghcr API.
- ghcr over Docker Hub for the pull path: spot-node churn means fresh pulls,
  and Docker Hub 429 rate-limiting has bitten this estate before.

## Freshness-check mechanics

- The workflow template sets `command: [sh, -c]`, which **bypasses
  ENTRYPOINT** — the gate must be invoked explicitly as the template's first
  line (`check-builder-freshness`). Baked ENTRYPOINT wiring would silently
  never run.
- Lookups (`npm view wrangler version`, nodejs.org dist index) happen at build
  time inside the CI pod, which has network. Lookup failure = WARN not ERROR:
  an npm outage must not block deploys.
- `SKIP_FRESHNESS_CHECK=1` is the emergency bypass (outage-day deploys).
