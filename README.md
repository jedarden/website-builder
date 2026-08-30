# website-builder

> **Internal tooling, public for reference.** This image is built for the
> author's Argo Workflows deployment and is not a general-purpose static-site
> builder distribution.

CI builder image for static-site builds on Argo Workflows — `node:22` with git
and a pinned wrangler baked in, published to `ghcr.io/jedarden/website-builder`
and consumed digest-pinned by the `website-build` WorkflowTemplate.

## Why

The stock `node:22` pipeline paid a fixed tax on every single build, measured
across five production runs (2026-08-07, timestamped pod logs):

| Phase | Stock `node:22` | With this image |
|---|---|---|
| `apt-get install git` | ~5–9s | 0 (baked) |
| `npx wrangler@latest` download | ~21s | 0 (baked, pinned) |
| `npm ci` | ~23s | unchanged (cache PVC is the follow-up) |
| Astro build (64 pages) | ~26–31s | unchanged |
| **Total build** | **~100s** | **~65–70s** |

## What's baked in

- `git` (clone step needs it; stock image ships without it)
- `wrangler` pinned globally (`npm install -g wrangler@<version>`) — the deploy
  step calls `wrangler pages deploy` directly instead of `npx wrangler@latest`
- `WRANGLER_SEND_METRICS=false`, npm update-notifier off — no first-run
  interactive noise in CI logs

- **Freshness gate**: `/usr/local/bin/check-builder-freshness`, run as the
  consuming template's first step. The build **errors** when the baked
  toolchain is stale — wrangler a major behind, wrangler more than
  `WRANGLER_MINOR_DRIFT_MAX` minors behind (default 10 ≈ 3–4 weeks; wrangler
  ships a minor every 2–3 days, so set 1 only if you want red CI twice a
  week), or node a minor behind the 22 line (~monthly). The error text is the
  remediation runbook, and it keeps failing until a fresh image ships.
  Registry outages WARN instead of blocking; `SKIP_FRESHNESS_CHECK=1` is the
  emergency bypass.

Secrets are **never** baked: GitHub and Cloudflare tokens enter at runtime via
the WorkflowTemplate's env, exactly as before.

## Versioning & distribution

- Source of truth: this repo (Forgejo-primary, GitHub read-only mirror).
- Releases: git tag `vX.Y.Z` → CI builds with Kaniko → pushes
  `ghcr.io/jedarden/website-builder:vX.Y.Z` → GitHub Release with the **image
  digest** in the notes.
- Consumers reference the image **by digest, never by tag** (house rule):
  `ghcr.io/jedarden/website-builder@sha256:…` in
  `declarative-config/k8s/iad-ci/argo-workflows/website-build-workflowtemplate.yml`.
- Rollback = revert the one-line digest bump in declarative-config.

## Maintenance cadence

Rebuild (patch bump) when: the wrangler pin needs a bump, or the `node:22` base
digest moves for a security fix. Both are one-line Dockerfile changes. There is
no scheduled rebuild — this image changes when its pins change, not on a timer.

## Structure

- `Dockerfile` — the image; every pin is by digest or exact version
- `docs/notes/` — features, constraints, design decisions
- `docs/research/` — external reference material and prior art
- `docs/plan/plan.md` — complete plan
