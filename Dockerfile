# website-builder — CI image for the `website-build` Argo WorkflowTemplate.
#
# Everything the workflow needs at container start is baked here so the
# per-build tax is zero: git for the clone, wrangler (pinned) for the deploy.
# Secrets are never baked — GH/CF tokens arrive at runtime via workflow env.
#
# Base pinned by digest (house rule: never :latest, never a floating tag).
# node:22 (full, not -slim) deliberately: this image serves the *generic*
# website-build template, and downstream sites may need the toolchain the slim
# image drops. Revisit -slim only with every consumer's build verified.
FROM node:22@sha256:0557ac14e0d45d02ed563067b82856ca5e7aa3437fa28d98d4350ea9c3d9494a

# git: the template's clone step. curl and zstd are explicit even though the
# base carries them today: curl signs the ARMOR S3 cache requests
# (--aws-sigv4, present since curl 7.75) and zstd backs `tar --zstd` — GNU
# tar shells out to the zstd binary, which the base does NOT include (probed
# 2026-08-26: tar 1.34 + no zstd = "zstd: not found"). Making them apt-pins
# keeps the template's script dependencies owned by this image, not by
# whatever buildpack-deps happens to ship. Clean apt lists to keep the layer
# lean.
RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends git curl zstd \
  && rm -rf /var/lib/apt/lists/*

# wrangler: pinned exactly. The deploy step calls `wrangler` from PATH —
# bumping this pin is a release of this image, not a per-build download.
RUN npm install -g wrangler@4.125.0 \
  && wrangler --version

# CI hygiene: no telemetry, no update-notifier chatter in build logs.
ENV WRANGLER_SEND_METRICS=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false

# Freshness gate: the website-build template runs this FIRST. It errors when
# the baked toolchain drifts past budget and prints how to cut a new image.
# (k8s `command:` bypasses ENTRYPOINT, so the template must call it — see the
# script header.)
COPY scripts/check-freshness.sh /usr/local/bin/check-builder-freshness
RUN chmod +x /usr/local/bin/check-builder-freshness

WORKDIR /workspace
