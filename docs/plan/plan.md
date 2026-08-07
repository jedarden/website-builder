# website-builder Plan

## Overview

CI builder image for static-site builds on Argo Workflows (iad-ci): `node:22`
with git and a pinned wrangler baked in, published to
`ghcr.io/jedarden/website-builder`, consumed digest-pinned by the shared
`website-build` WorkflowTemplate. Goal: remove the fixed per-build tax
(measured ~30s of every ~100s build) that the stock `node:22` image pays on
apt-get and the `npx wrangler@latest` download.

## Architecture

- **This repo** holds only the Dockerfile and docs — no site code, no secrets.
- **Build/publish** happens on iad-ci via a `website-builder-release`
  WorkflowTemplate in `jedarden/declarative-config` (adapted from
  `miroir-release`): Kaniko build → push `ghcr.io/jedarden/website-builder`
  with the git tag → GitHub Release carrying the image digest in its notes.
  GH Actions stay disabled (house rule).
- **Consumption**: `website-build-workflowtemplate.yml` references the image by
  digest. Bumping = one-line declarative-config commit naming the release it
  came from; rollback = revert that commit.
- **Hosting**: Forgejo-primary (`git.ardenone.com/jedarden/website-builder`),
  GitHub read-only push-mirror. Releases are cut on GitHub (where ghcr and the
  audience live), matching the forge/NEEDLE/miroir pattern.

## Components

- `Dockerfile` — base `node:22` pinned by digest; git; `wrangler@4.119.0`
  global; CI-hygiene env (no telemetry/update-notifier).
- `scripts/check-freshness.sh` — baked as
  `/usr/local/bin/check-builder-freshness`; the consuming template runs it
  first and the build errors on stale pins (drift budgets and cadence data in
  `docs/research/component-pins-and-cadence.md`; constraints in
  `docs/notes/constraints-and-features.md`).
- `website-builder-release` WorkflowTemplate (lives in declarative-config, not
  here) — tag-triggered or manually submitted.

## Data Models

None — the artifact is an OCI image. Version scheme: semver tags `vX.Y.Z`;
patch = pin bumps (wrangler/base digest), minor = new baked component,
major = base image major change.

## Implementation Phases

- [x] Phase 1: Repo scaffold + Dockerfile (this repo)
- [ ] Phase 2: `website-builder-release` WorkflowTemplate in declarative-config;
      first release `v1.0.0` pushed to ghcr; digest recorded in the GitHub
      Release notes
- [ ] Phase 3: `website-build` template adopts the digest (drop `apt-get`,
      switch deploy to baked `wrangler`); verify a jedarden.com build lands
      ~65–70s
- [ ] Phase 4 (separate effort): lockfile-keyed `node_modules` +
      `node_modules/.astro` cache PVC in the template — targets the remaining
      `npm ci` (~23s) and part of the Astro image work (~10–15s)

## Open Questions

- `node:22-slim` base (−~850MB image) — only after auditing every
  website-build consumer (mobile-gaming runs a level-generation suite that may
  need the full toolchain).
- Tag-push webhook trigger for releases vs. manual workflow submission —
  manual is fine at this change frequency.
