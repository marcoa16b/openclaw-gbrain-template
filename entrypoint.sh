#!/usr/bin/env bash
# Entrypoint for openclaw-gbrain (self-hosted, PGLite engine).
#
# Runs on every container start. The expensive step (gbrain init schema +
# skills seed) is idempotent and short-circuits on reboots via the
# config.json sentinel on the persistent disk. Failures here exit non-zero
# so the platform surfaces the problem instead of starting AlphaClaw
# against a half-initialized brain.

set -euo pipefail

log() { echo "[entrypoint] $*"; }

# ---------------------------------------------------------------------------
# 1. Validate required environment.
# ---------------------------------------------------------------------------
require_env() {
  if [ -z "${!1:-}" ]; then
    log "ERROR: $1 is not set. See README.md for required env vars."
    exit 1
  fi
}

require_env OPENROUTER_API_KEY
require_env ALPHACLAW_ROOT_DIR
require_env GBRAIN_HOME

# ANTHROPIC_API_KEY is OPTIONAL when using OpenRouter for everything else.
# GBrain's subagent infrastructure (takes extract, autopilot/dream-cycle)
# hard-pins to Anthropic-direct for stable tool_use_id across crashes/
# replays, and rejects OpenRouter-routed Anthropic calls at submit time.
# Without a direct key those specific features stay disabled; embeddings,
# query expansion, and the OpenClaw agent itself work fine on OpenRouter
# alone.
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  log "WARNING: ANTHROPIC_API_KEY not set. GBrain subagent features (takes"
  log "  extract, autopilot dream-cycle) will stay disabled — they refuse"
  log "  OpenRouter-routed Anthropic calls by design. Everything else"
  log "  (embeddings, query expansion, the OpenClaw agent) runs fine on"
  log "  OPENROUTER_API_KEY alone."
fi

mkdir -p "$ALPHACLAW_ROOT_DIR"
mkdir -p "$ALPHACLAW_ROOT_DIR/skills"

# gbrain treats GBRAIN_HOME as a parent dir and appends '.gbrain' itself.
# Create the resolved configDir so first-run writes never race a missing dir.
mkdir -p "$GBRAIN_HOME/.gbrain"

# ---------------------------------------------------------------------------
# 2. Initialize the GBrain brain (idempotent: safe to re-run).
#    PGLite runs Postgres in-process (WASM via @electric-sql/pglite) against
#    a single file on the persistent disk. pgvector and pg_trgm ship with
#    PGLite as bundled extensions, so no external Postgres or CREATE
#    EXTENSION step is needed.
#
#    Config and the brain file both live under $GBRAIN_HOME/.gbrain on
#    /data, so they persist across deploys/restarts.
# ---------------------------------------------------------------------------
if [ ! -f "$GBRAIN_HOME/.gbrain/config.json" ]; then
  log "Running first-time gbrain init (PGLite engine, OpenRouter embeddings)..."
  # gbrain's env auto-detection only recognizes OPENAI_API_KEY /
  # ZEROENTROPY_API_KEY / VOYAGE_API_KEY, not OPENROUTER_API_KEY, so the
  # OpenRouter embedding model must be passed explicitly.
  gbrain init --pglite --non-interactive \
    --embedding-model "openrouter:openai/text-embedding-3-small"

  # Route query-expansion / chat calls through OpenRouter too. Skipped
  # automatically if this gbrain build doesn't expose chat_model as a
  # config key — check `gbrain config list` / current docs if this errors.
  gbrain config set chat_model "openrouter:anthropic/claude-haiku-4.5" || \
    log "WARNING: could not set chat_model via OpenRouter; check 'gbrain config list' for the current key name."
else
  log "gbrain config found at $GBRAIN_HOME/.gbrain/config.json, skipping init."
fi

# ---------------------------------------------------------------------------
# 3. Seed the GBrain skill pack into the AlphaClaw skills directory.
#    Only copy on first boot or when the seed adds new skills (cp -n never
#    overwrites user edits, so updates to existing skills require an explicit
#    operator action).
# ---------------------------------------------------------------------------
if [ -d /app/skills-seed ]; then
  log "Seeding GBrain skills into $ALPHACLAW_ROOT_DIR/skills..."
  cp -rn /app/skills-seed/* "$ALPHACLAW_ROOT_DIR/skills/" || true
fi

# ---------------------------------------------------------------------------
# 4. Hand off to AlphaClaw.
# ---------------------------------------------------------------------------
log "Starting AlphaClaw..."
exec "$@"