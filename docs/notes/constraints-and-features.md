# Constraints and features

## Features

- **Zero per-build toolchain tax**: git and wrangler are baked, eliminating
  the measured ~30s of apt-get + `npx wrangler@latest` on every build.
- **Pinned everything**: base image by digest, wrangler by exact version. A
  version bump is a *release of this image*, visible in git history and a
  GitHub Release — never a silent drift.
- **Freshness gate** (`/usr/local/bin/check-builder-freshness`): the consuming
  template runs it first; the build ERRORS when the baked toolchain is stale,
  and the error text is the remediation runbook (bump pin → tag → release →
  digest bump). The failure persists until a new image ships — staleness
  surfaces as red CI, not silent rot.
  - wrangler: major behind ⇒ error; > `WRANGLER_MINOR_DRIFT_MAX` minors
    behind ⇒ error (default 10 ≈ 3–4 weeks; wrangler ships minors every 2–3
    days — see research doc — so budget 1 would red-bar CI twice weekly; set
    the env to 1 in the template for strict mode).
  - node 22 line: any minor behind ⇒ error (~monthly; doubles as the
    security-refresh forcing function).
  - registry lookup failure ⇒ WARN and continue (npm outage must not block
    deploys).
  - `SKIP_FRESHNESS_CHECK=1` ⇒ emergency bypass, for outage-day deploys only.
- **CI-quiet defaults**: wrangler telemetry off, npm update-notifier/fund/
  audit chatter off.

## Constraints

- **No secrets in the image, ever.** GH and CF tokens enter at runtime via the
  WorkflowTemplate env. The Dockerfile must never need them.
- **Consumers pin by digest, never by tag** (house rule: no `:latest`, no
  floating tags in manifests). The GitHub Release notes carry the digest.
- **This image serves the generic `website-build` template** — all its
  consumers (jedarden.com, morejoyfulyou, mobile-gaming, …), not just one
  site. Nothing site-specific goes in (no site deps, no `-slim` until every
  consumer is audited).
- **GH Actions stay disabled** — the image is built by an Argo
  WorkflowTemplate in declarative-config (`website-builder-release`, adapted
  from `miroir-release`), not by this repo's own CI.
- **k8s `command:` bypasses ENTRYPOINT** — the freshness gate only runs
  because the template calls it explicitly. Any future baked check must
  follow the same contract; ENTRYPOINT wiring is dead code here.
- **Hosting**: Forgejo-primary, GitHub read-only push-mirror; releases cut on
  GitHub (ghcr + audience live there), matching forge/NEEDLE/miroir. Never
  force-push.

## Decisions

- **ghcr.io over Docker Hub** for the pull path: ghcr.io/jedarden is already
  established (miroir, trace-*), auth/secrets exist on the CI cluster, and
  Docker Hub 429s have bitten spot-node pulls before.
- **Full `node:22` base, not `-slim`**: generic-template blast radius beats
  the ~850MB size win until consumers are audited (open question in plan.md).
- **Drift budget defaults live in the template env, not the image**: policy
  tightening (e.g. strict minor gating) is a declarative-config edit + ArgoCD
  sync, not an image rebuild.
