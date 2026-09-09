#!/bin/bash
# =============================================================================
# hermes_setup.sh — bootstrap Hermes Agent (Nous Research) inside the Railway
# "free VPS" container and start the Telegram messaging gateway.
#
# Triggered automatically by /startup.sh when HERMES_AUTOSTART=true, or run it
# manually from the desktop terminal:
#     bash /opt/hermes_setup.sh
#
# ---- Two LLM modes (set in Railway -> Variables) ----
#
# MODE A — 9Router (default / recommended):
#   HERMES_LLM_MODE=nine_router   (or unset — this is the default)
#   HERMES_NINEROUTER_BASE_URL    — http://nine-router.railway.internal:20128/v1 (default for Railway)
#   HERMES_NINEROUTER_API_KEY     — your 9Router API key (from dashboard)
#   HERMES_MODEL                  — model in 9Router (default: kr/claude-sonnet-4.5)
#   NO OPENROUTER_API_KEY NEEDED — 9Router is the brain, you connect providers
#      (b.ai, Kiro, iFlow, Qwen...) from its dashboard (http://localhost:20128
#      inside the VPS desktop browser).
#
# MODE B — OpenRouter / OpenAI (fallback):
#   HERMES_LLM_MODE=openrouter
#   OPENROUTER_API_KEY            — your OpenRouter API key
#   HERMES_MODEL                  — model id (default: openrouter/openai/gpt-4o-mini)
#
# ---- Shared ----
#   TELEGRAM_BOT_TOKEN            — bot token from @BotFather (always required)
#   HERMES_ALLOWED_USERS          — comma-separated Telegram user ids (optional)
# =============================================================================
set -e

LOG=/var/log/hermes_setup.log
exec > >(tee -a "$LOG") 2>&1

echo "=============================================="
echo " Hermes Agent bootstrap started: $(date)"
echo "=============================================="

# ---- Sanity checks ----------------------------------------------------------
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo "[!] TELEGRAM_BOT_TOKEN is not set. Skipping Hermes setup."
    echo "    Set it in Railway -> Variables, set HERMES_AUTOSTART=true, then redeploy."
    exit 0
fi

# ---- Detect LLM mode --------------------------------------------------------
LLM_MODE="${HERMES_LLM_MODE:-nine_router}"

if [ "$LLM_MODE" = "nine_router" ]; then
    NINEROUTER_BASE_URL="${HERMES_NINEROUTER_BASE_URL:-http://nine-router.railway.internal:20128/v1}"
    NINEROUTER_API_KEY="${HERMES_NINEROUTER_API_KEY:-}"
    if [ -z "$NINEROUTER_API_KEY" ]; then
        echo "[!] LLM mode = 9Router but HERMES_NINEROUTER_API_KEY is not set."
        echo "    1) Open the VPS desktop (noVNC) -> browser -> http://localhost:20128"
        echo "    2) Login (default password 123456), connect your provider (b.ai, Kiro, iFlow...)"
        echo "    3) Dashboard -> Settings -> API Keys -> copy the key"
        echo "    4) Set HERMES_NINEROUTER_API_KEY in Railway -> Variables -> Redeploy"
        echo "    Skipping Hermes gateway start (retry after setting the key)."
        exit 0
    fi
    echo "[i] LLM mode: 9Router  ->  ${NINEROUTER_BASE_URL}"
else
    if [ -z "$OPENROUTER_API_KEY" ]; then
        echo "[!] LLM mode = openrouter but OPENROUTER_API_KEY is not set. Skipping."
        exit 0
    fi
    echo "[i] LLM mode: OpenRouter"
fi

# ---- 1. System dependencies -------------------------------------------------
echo "[1/5] Installing system dependencies..."
apt-get update -y
apt-get install -y --no-install-recommends \
    curl \
    xz-utils \
    bzip2 \
    build-essential \
    libffi-dev \
    libssl-dev \
    python3-dev \
    ripgrep \
    ffmpeg \
    jq

# ---- 2. Install Hermes Agent (official installer) ----------------------------
echo "[2/5] Installing Hermes Agent..."
export HOME=/root
# Installer writes the 'hermes' launcher to ~/.local/bin and the repo to ~/.hermes/
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash || \
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"

echo "[3/5] Verifying install..."
hermes --version || true

# ---- 3. Write config ---------------------------------------------------------
echo "[4/5] Writing ~/.hermes/config.yaml ..."
mkdir -p ~/.hermes

ALLOWED="${HERMES_ALLOWED_USERS:-}"

# ---- Whitelist ID Telegram permanen -------------------------------------------
# ID di bawah ini SELALU boleh chat bot Hermes. Ia di-GABUNGKAN (bukan
# menimpa) dengan HERMES_ALLOWED_USERS dari Railway -> Variables, jadi ID
# Telegram lama tidak pernah hilang. Duplikat & spasi otomatis dibuang.
FORCED_ALLOWED_USERS="7597390816"

if [ -n "$ALLOWED" ]; then
    ALLOWED=$(printf '%s\n%s\n' "$ALLOWED" "$FORCED_ALLOWED_USERS" \
        | tr ',' '\n' \
        | sed 's/[[:space:]]//g' \
        | awk 'NF && !seen[$0]++' \
        | paste -sd ',' -)
    echo "[i] Telegram whitelist : ${ALLOWED}"
fi
# (Jika HERMES_ALLOWED_USERS kosong, config memakai allow_all_users: true,
#  artinya semua orang — termasuk ID di atas — bisa chat bot.)

if [ "$LLM_MODE" = "nine_router" ]; then
    # 9Router as the brain (OpenAI-compatible custom endpoint)
    MODEL="${HERMES_MODEL:-kr/claude-sonnet-4.5}"
    cat > ~/.hermes/config.yaml <<YAML
# Generated by hermes_setup.sh on $(date) — LLM mode: 9Router
model:
  default: ${MODEL}
  provider: custom
  base_url: ${NINEROUTER_BASE_URL}
  api_key: ${NINEROUTER_API_KEY}
YAML

    cat > ~/.hermes/.env <<ENV
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
OPENAI_API_KEY=${NINEROUTER_API_KEY}
OPENAI_BASE_URL=${NINEROUTER_BASE_URL}
ENV
else
    # OpenRouter as the brain (original behaviour)
    MODEL="${HERMES_MODEL:-openrouter/openai/gpt-4o-mini}"
    BASE_URL="${HERMES_BASE_URL:-https://openrouter.ai/api/v1}"
    cat > ~/.hermes/config.yaml <<YAML
# Generated by hermes_setup.sh on $(date) — LLM mode: OpenRouter
model:
  default: ${MODEL}
  provider: openrouter
  base_url: ${BASE_URL}
  api_key: ${OPENROUTER_API_KEY}
YAML

    cat > ~/.hermes/.env <<ENV
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
ENV
fi

if [ -n "$ALLOWED" ]; then
    cat >> ~/.hermes/config.yaml <<YAML

gateway:
  platforms:
    telegram:
      bot_token: ${TELEGRAM_BOT_TOKEN}
      allowed_users:
YAML
    # YAML list entries
    echo "${ALLOWED}" | tr ',' '\n' | while read -r uid; do
        [ -n "$uid" ] && echo "        - ${uid}"
    done >> ~/.hermes/config.yaml
else
    cat >> ~/.hermes/config.yaml <<YAML

gateway:
  platforms:
    telegram:
      bot_token: ${TELEGRAM_BOT_TOKEN}
      allow_all_users: true
YAML
fi

echo "Config written:"
sed -E 's/(api_key|bot_token): .*/\1: [REDACTED]/' ~/.hermes/config.yaml

# ---- 4. Start Telegram gateway ----------------------------------------------
echo "[5/5] Starting Hermes gateway..."
# First run may do first-time init; keep it alive in the background.
nohup hermes gateway > /var/log/hermes_gateway.log 2>&1 &
disown || true
sleep 5

echo "=============================================="
echo " Hermes bootstrap done: $(date)"
echo " Gateway log : /var/log/hermes_gateway.log"
echo " Setup log   : $LOG"
echo " Check       : tail -f /var/log/hermes_gateway.log"
echo "=============================================="