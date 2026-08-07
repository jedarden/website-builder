#!/bin/sh
# Freshness gate for the website-builder image (baked at
# /usr/local/bin/check-builder-freshness).
#
# The website-build WorkflowTemplate runs this as its FIRST step. It fails the
# build when the baked toolchain has drifted too far behind upstream, and the
# error tells the operator exactly how to cut a fresh image. It keeps failing
# until a new image ships — that is the point: staleness surfaces as a build
# error, not as silent rot.
#
# NOTE (k8s): the template sets `command:`, which bypasses ENTRYPOINT — this
# script only runs because the template invokes it explicitly. Do not rely on
# ENTRYPOINT wiring.
#
# Policy (see docs/research/component-pins-and-cadence.md for the measured
# cadence behind these defaults):
#   - wrangler MAJOR behind latest ............................ ERROR
#   - wrangler > $WRANGLER_MINOR_DRIFT_MAX minors behind ...... ERROR
#     (default 10 ≈ 3–4 weeks of drift; wrangler ships a minor every 2–3
#     days, so a budget of 1 would red-bar CI twice a week. Set the env to 1
#     in the template for strict mode.)
#   - node 22.x a MINOR behind the 22 line .................... ERROR
#     (~monthly cadence; doubles as the security-refresh forcing function)
#   - registry/network lookup failure ......................... WARN, continue
#     (an npm outage must not block deploys)
#   - SKIP_FRESHNESS_CHECK=1 .................................. skip entirely
#     (emergency hatch for outage-day deploys; use once, then rebuild)

set -u

if [ "${SKIP_FRESHNESS_CHECK:-0}" = "1" ]; then
  echo "[freshness] SKIPPED via SKIP_FRESHNESS_CHECK=1 — cut a fresh image before relying on this twice"
  exit 0
fi

DRIFT_MAX="${WRANGLER_MINOR_DRIFT_MAX:-10}"
FAIL=0

remediation() {
  cat <<'EOM'
[freshness] ── HOW TO CLEAR THIS ──────────────────────────────────────────
[freshness] 1. In jedarden/website-builder: bump the stale pin in Dockerfile
[freshness]    (wrangler version and/or node:22 base digest), commit, tag vX.Y.Z.
[freshness] 2. Run the website-builder-release workflow on iad-ci → pushes
[freshness]    ghcr.io/jedarden/website-builder and cuts a GitHub Release
[freshness]    with the new digest in the notes.
[freshness] 3. Update the image digest in declarative-config
[freshness]    k8s/iad-ci/argo-workflows/website-build-workflowtemplate.yml,
[freshness]    push, let ArgoCD sync.
[freshness] One-off bypass (emergencies only): SKIP_FRESHNESS_CHECK=1
[freshness] ───────────────────────────────────────────────────────────────
EOM
}

# ---- wrangler ---------------------------------------------------------------
BAKED_WRANGLER="$(wrangler --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
LATEST_WRANGLER="$(npm view wrangler version 2>/dev/null || true)"

if [ -z "$BAKED_WRANGLER" ]; then
  echo "[freshness] ERROR: wrangler not found in image — the image is broken, rebuild it"
  FAIL=1
elif [ -z "$LATEST_WRANGLER" ]; then
  echo "[freshness] WARN: could not query npm for latest wrangler (network/registry) — continuing"
else
  B_MAJ="${BAKED_WRANGLER%%.*}"; R="${BAKED_WRANGLER#*.}"; B_MIN="${R%%.*}"
  L_MAJ="${LATEST_WRANGLER%%.*}"; R="${LATEST_WRANGLER#*.}"; L_MIN="${R%%.*}"
  if [ "$L_MAJ" -gt "$B_MAJ" ]; then
    echo "[freshness] ERROR: baked wrangler $BAKED_WRANGLER is a MAJOR behind latest $LATEST_WRANGLER"
    FAIL=1
  elif [ "$L_MAJ" -eq "$B_MAJ" ] && [ "$((L_MIN - B_MIN))" -gt "$DRIFT_MAX" ]; then
    echo "[freshness] ERROR: baked wrangler $BAKED_WRANGLER is $((L_MIN - B_MIN)) minors behind latest $LATEST_WRANGLER (budget: $DRIFT_MAX)"
    FAIL=1
  elif [ "$L_MAJ" -eq "$B_MAJ" ] && [ "$L_MIN" -gt "$B_MIN" ]; then
    echo "[freshness] ok-ish: wrangler $BAKED_WRANGLER is $((L_MIN - B_MIN)) minor(s) behind $LATEST_WRANGLER (budget: $DRIFT_MAX) — drift is accruing"
  else
    echo "[freshness] ok: wrangler $BAKED_WRANGLER is current"
  fi
fi

# ---- node 22 line -----------------------------------------------------------
BAKED_NODE="$(node --version | sed 's/^v//')"
LATEST_NODE22="$(node -e '
  fetch("https://nodejs.org/dist/index.json")
    .then((r) => r.json())
    .then((a) => {
      const v = a.find((n) => n.version.startsWith("v22."));
      if (v) console.log(v.version.slice(1));
    })
    .catch(() => process.exit(9));
' 2>/dev/null || true)"

if [ -z "$LATEST_NODE22" ]; then
  echo "[freshness] WARN: could not query nodejs.org for the 22 line — continuing"
else
  BN_MIN="$(echo "$BAKED_NODE" | cut -d. -f2)"
  LN_MIN="$(echo "$LATEST_NODE22" | cut -d. -f2)"
  if [ "$LN_MIN" -gt "$BN_MIN" ]; then
    echo "[freshness] ERROR: baked node $BAKED_NODE is a minor behind the 22 line ($LATEST_NODE22) — base digest needs a bump"
    FAIL=1
  else
    echo "[freshness] ok: node $BAKED_NODE is current on the 22 line"
  fi
fi

if [ "$FAIL" -ne 0 ]; then
  remediation
  exit 1
fi
echo "[freshness] image is fresh"
