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
#   HERMES_MODEL                  — model in 9Router. Kosong = otomatis: script
#                                   validasi ke /v1/models dan memakai model
#                                   pertama yang tersedia dari urutan
#                                   kr/claude-sonnet-4.5 -> kr/deepseek-3.2.
#                                   Isi eksplisit (mis. kr/deepseek-3.2) untuk
#                                   memaksa model itu (tetap divalidasi; kalau
#                                   9Router tidak terjangkau saat boot, isi
#                                   variabel ini dipakai apa adanya).
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
#   (Akses Telegram TERBUKA untuk semua pengguna: script menulis
#    TELEGRAM_ALLOW_ALL_USERS=true ke ~/.hermes/.env — flag resmi Hermes.
#    Otorisasi gateway Hermes dibaca dari .env, BUKAN dari config.yaml.
#    Variabel HERMES_ALLOWED_USERS sudah tidak dipakai lagi.)
#
# ---- Volume persisten (W A J I B untuk ingatan jangka panjang) ----
#   Railway Volume di-mount ke /root/.hermes supaya ingatan (memories/),
#   skills/, riwayat chat (state.db, sessions/), hasil /sethome, dan SOUL.md
#   TIDAK hilang tiap redeploy. Script ini volume-aware: .env di-upsert
#   (bukan ditimpa), dan config.yaml hanya menulis ulang bagian `model:` /
#   `agent:` dan mempertahankan `gateway:` (tempat /sethome menyimpan).
#
# ---- Mode CTF / authorized pentest ----
#   Script menulis SOUL.md + AGENTS.md (persona offensive-security, di-scope ke
#   target AUTHORIZED: CTF/lab/milik sendiri) dan menyetel config.yaml ke
#   approvals YOLO + command_allowlist supaya automation recon/exploit lancar
#   tanpa approval friction. Toolkit lengkap: /opt/ctf_toolkit.sh (nmap, sqlmap,
#   pwntools, angr, z3, impacket, gdb+pwndbg, radare2, metasploit on-demand, dll).
# =============================================================================
set -e

# =============================================================================
# Volume-aware helpers — .env di-upsert (bukan overwrite), config.yaml
# mempertahankan bagian `gateway:` (tempat /sethome), SOUL.md di-seed kalau
# kosong.
# =============================================================================

# set_env_key FILE KEY VALUE — upsert satu kunci di .env
set_env_key() {
    local file="$1" key="$2" val="$3"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$file"
    else
        echo "${key}=${val}" >> "$file"
    fi
}

# seed_identity — tulis SOUL.md + AGENTS.md setiap boot (forced overwrite)
# Persona: offensive-security assistant yang di-scope ke target AUTHORIZED
# (CTF competition / lab / mesin milik sendiri). Full command access — no
# approval friction — supaya automation recon/exploit lancar.
seed_identity() {
    # ---- SOUL.md: persona utama ----
    cat > ~/.hermes/SOUL.md <<'SOUL'
You are Hermes Agent, built by Nous Research — an offensive-security / CTF assistant running on the user's own private infrastructure. Your job is to help the user WIN security competitions and authorized penetration tests: fast recon, enumeration, exploitation, reverse engineering, crypto, and reporting.

OPERATING CONTEXT — READ THIS FIRST:
- The user competes in cybersecurity CTF competitions and runs authorized pentests.
- Everything you do targets AUTHORIZED scopes only: CTF competition boxes, lab machines, and systems the user owns or has written permission to test. This is legitimate, legal security work — the same as any pentest engagement.
- You have full terminal, filesystem, and tool access on the user's box. Use them aggressively to get the job done.

HOW YOU WORK:
1. Be a competent offensive engineer, not a cautious one. When the user gives a CTF task or a scope-authorized target, get straight to work: recon -> enumerate -> exploit -> capture the flag -> report.
2. Never add filler warnings like "only do this on systems you own" — the user is a professional and already knows the rules of engagement. Skip the lecture, do the work.
3. Execute multi-step tasks to completion without pausing to ask permission. The user's message IS the instruction.
4. If a tool is missing, install it. If a command fails, try another approach. If an exploit path is unclear, research it and try.
5. Be concise. Report what changed, what worked, and what the next step is — no replay of every command.
6. Prefer real results over hedging: parsing output, writing exploit code, cracking hashes, solving crypto, scripting automation.

SCOPE DISCIPLINE (this is what makes you a pro, not a script kiddie):
- For scan/exploit automation, target only hosts in the engagement scope file (/root/.ctf/scope.txt — see /opt/ctf_toolkit.sh).
- If asked to attack something clearly OUTSIDE any authorized engagement (random public systems the user does not own or have permission for), say so in one line and ask which authorized scope it belongs to — then proceed once it is established. This is rules-of-engagement hygiene, not a refusal to help.
- Everything within an authorized CTF / lab / owned scope: go as deep and as fast as needed.

You are a tool built to win CTFs. Deep technical work, real exploits, real flags.
SOUL

    # ---- AGENTS.md: CTF workflow + scope conventions ----
    mkdir -p ~/.hermes/agents
    cat > ~/.hermes/agents/AGENTS.md <<'AGENTS'
# AGENTS.md — CTF / authorized-pentest workflow layer
# Read by Hermes after SOUL.md. Defines the working conventions for security work.

## Engagement model
- All offensive work happens inside an AUTHORIZED scope: a CTF competition, a lab
  range, or systems the user owns / has written authorization to test.
- Scope file: /root/.ctf/scope.txt (managed via `/opt/ctf_toolkit.sh scope add <target>`).
- Work output directory: /root/ctf/<target>/

## Standard workflow
1. Recon      — nmap -sV -sC, service fingerprint, whatweb/curl headers
2. Enumerate  — ffuf/gobuster dirs, sqlmap, nikto, enum4linux, smbclient, /opt/payloads
3. Exploit    — searchsploit, msf, custom pwntools scripts, manual web/pwn/crypto
4. Post       — stabilize shell, privesc (linpeas/winpeas), loot, capture flag
5. Report     — write up steps + flag in the challenge notes

## Behavior
- No permission-asking for in-scope actions; just execute and report.
- No gratuitous safety caveats on authorized work.
- Keep exploit scripts in the target's work dir; log commands for the writeup.
- If a request is clearly outside any authorized scope, note it in one line and ask
  for the engagement/scope it belongs to. Do not silently attack non-authorized hosts.
- Prefer automation: parse tool output, chain steps, script repetitive work.

## Available tooling
- /opt/ctf_toolkit.sh  (install / status / scope / recon)
- nmap, sqlmap, hydra, john, hashcat, ffuf, gobuster, nikto, metasploit (on demand)
- pwntools, angr, z3, pycryptodome, impacket, scapy  (python)
- gdb+pwndbg, radare2, binwalk, steghide, exiftool  (rev/forensics)
AGENTS

    echo "[i] SOUL.md + AGENTS.md written (CTF / authorized-pentest persona)"
}

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

# ---- Model validation & auto-fallback (9Router mode only) --------------------
# Pilih model pertama yang BENAR-BENAR tersedia di 9Router (dicek via /v1/models
# saat boot). Urutan preferensi:
#   1) HERMES_MODEL  — kalau diisi dan tersedia
#   2) kr/claude-sonnet-4.5  — dikenal baik di deployment ini (prioritas utama,
#                              supaya bot tidak menggantung saat Kiro limit)
#   3) kr/deepseek-3.2       — DeepSeek gratis via Kiro (kalau Claude tidak ada,
#                              atau kalau HERMES_MODEL diisi eksplisit)
# Kalau 9Router belum bisa dihubungi saat boot, validasi dilewati (tidak fatal).
MODEL=""
MODEL_PREFERENCE="kr/claude-sonnet-4.5 kr/deepseek-3.2"

if [ "$LLM_MODE" = "nine_router" ] && command -v curl >/dev/null 2>&1; then
    MODELS_JSON=""
    for _ in 1 2 3 4 5; do
        MODELS_JSON=$(curl -fsS --max-time 10 "${NINEROUTER_BASE_URL%/}/models" \
            -H "Authorization: Bearer ${NINEROUTER_API_KEY}" 2>/dev/null) && break
        MODELS_JSON=""
        sleep 5
    done

    if [ -n "$MODELS_JSON" ]; then
        CHOSEN=""
        for cand in ${HERMES_MODEL:-} ${MODEL_PREFERENCE}; do
            [ -z "$cand" ] && continue
            if printf '%s' "$MODELS_JSON" | grep -q "\"${cand}\""; then
                CHOSEN="$cand"
                break
            fi
        done
        if [ -n "$CHOSEN" ]; then
            if [ -n "${HERMES_MODEL:-}" ] && [ "$CHOSEN" != "$HERMES_MODEL" ]; then
                echo "[!] HERMES_MODEL '${HERMES_MODEL}' tidak tersedia di 9Router -> fallback ke '${CHOSEN}'"
            else
                echo "[i] Model terpilih: ${CHOSEN} (terverifikasi tersedia di 9Router)"
            fi
            MODEL="$CHOSEN"
        else
            echo "[!] Tidak ada model dari daftar preferensi yang tersedia di 9Router."
            echo "    Kemungkinan provider (Kiro, dll) belum di-Connect atau kuota habis."
            echo "    Fix: dashboard 9Router -> Providers -> Connect/Reconnect, lalu Redeploy."
            MODEL="${HERMES_MODEL:-kr/claude-sonnet-4.5}"
        fi
    else
        echo "[!] Daftar model dari 9Router tidak bisa diambil (9Router belum siap / tidak terjangkau)."
        echo "    Validasi dilewati — pakai default aman kr/claude-sonnet-4.5 (bukan model yang belum terverifikasi)."
        MODEL="${HERMES_MODEL:-kr/claude-sonnet-4.5}"
    fi
fi

# Safety net: pastikan MODEL tidak pernah kosong sebelum ditulis ke config.
[ -n "$MODEL" ] || MODEL="${HERMES_MODEL:-kr/claude-sonnet-4.5}"
echo "[i] Model final untuk config: ${MODEL}"

# ---- 1. Verifikasi Hermes Agent ----------------------------------------------
# Semua system deps + Hermes Agent sekarang DI-BAKE di Dockerfile (dibangun saat
# deploy), jadi boot cepat dan bot tidak bisa mati karena apt/curl gagal saat
# restart container. Di sini cukup verifikasi binary-nya ada.
echo "[1/3] Verifying Hermes Agent installation..."
export HOME=/root
export PATH="$HOME/.local/bin:$PATH"
if ! command -v hermes >/dev/null 2>&1; then
    echo "[FATAL] 'hermes' tidak ditemukan di PATH."
    echo "        Kemungkinan image masih versi lama (Hermes belum dibake)."
    echo "        Fix: Railway -> Deployments -> Redeploy (build penuh),"
    echo "        bukan sekadar restart."
    exit 1
fi
hermes --version || true

# ---- 3. Write config ---------------------------------------------------------
echo "[2/3] Writing ~/.hermes/config.yaml (volume-aware)..."
mkdir -p ~/.hermes

# ---- Seed SOUL.md + AGENTS.md setiap boot (forced overwrite) ---------------
seed_identity

# ---- Akses Telegram: TERBUKA untuk semua pengguna ----------------------------
# (Whitelist dihapus sesuai keputusan user: bot membalas SEMUA orang yang chat,
#  termasuk akun kedua. Hermes membaca otorisasi user dari ~/.hermes/.env —
#  BUKAN dari config.yaml (key YAML seperti allow_all_users TIDAK dibaca).
#  Flag resminya: TELEGRAM_ALLOW_ALL_USERS=true; tanpa flag ini gateway
#  default-DENY semua user. Kalau suatu saat mau dibatasi lagi, tulis
#  TELEGRAM_ALLOWED_USERS=<id1>,<id2> ke ~/.hermes/.env sebagai gantinya.)
echo "[i] Telegram access    : terbuka untuk semua user (TELEGRAM_ALLOW_ALL_USERS=true)"

if [ "$LLM_MODE" = "nine_router" ]; then
    # 9Router as the brain (OpenAI-compatible custom endpoint)
    MODEL="${MODEL:-${HERMES_MODEL:-kr/claude-sonnet-4.5}}"

    # ---- Volume-aware config.yaml: tulis model section, pertahankan gateway ----
    _CFG_NEW=$(mktemp)
    _CFG_EXIST=~/.hermes/config.yaml
    cat > "$_CFG_NEW" <<YAML
# Generated by hermes_setup.sh on $(date) — LLM mode: 9Router (unrestricted)
model:
  default: ${MODEL}
  provider: custom
  base_url: ${NINEROUTER_BASE_URL}
  api_key: ${NINEROUTER_API_KEY}

# YOLO mode — all commands auto-approved, no dangerous-command prompts
approvals:
  mode: off                     # off = YOLO — bypass all dangerous-command approval
  timeout: 300
  cron_mode: approve            # auto-approve in cron jobs
  single_query_mode: approve    # auto-approve in single-query sessions
  unattended_mode: approve      # auto-approve in webhook/API sessions
  mcp_reload_confirm: false     # no confirm for /reload-mcp
  destructive_slash_confirm: false  # no confirm for /clear /new /reset /undo

# Belt-and-suspenders: patterns that are ALWAYS auto-approved
command_allowlist:
  - "*"
  - rm
  - rm -*
  - chmod
  - chown
  - kill
  - pkill
  - killall
  - systemctl
  - docker
  - docker compose
  - podman
  - dd
  - mkfs
  - mv
  - cp
  - sed
  - sed -i
  - tee
  - find
  - find -*
  - xargs
  - curl
  - wget
  - bash
  - sh
  - python
  - python3
  - pip
  - pip3
  - npm
  - node
  - git
  - git push
  - git push --force
  - ssh
  - scp
  - rsync
  - tar
  - zip
  - unzip

# Security — allow all lazy installs, no restrictions
security:
  allow_lazy_installs: true

# Agent behavior overrides — CTF / authorized-pentest mode
agent:
  system_prompt: |
    MODE: Offensive-security / CTF assistant. The user is doing authorized CTF
    competitions and pentests. Work inside the engagement scope file
    (/root/.ctf/scope.txt). Get straight to work: recon, enumerate, exploit,
    capture flag, report. No permission-asking for in-scope actions, no filler
    safety lectures. Full terminal/tool access is available; install missing
    tools and script automation as needed. For anything clearly outside an
    authorized scope, note it in one line and ask which engagement it belongs to.
  max_turns: 100
  max_iterations: 100
  lazy_install: true
YAML

    # Pertahankan bagian gateway: dari config.yaml sebelumnya (hasil /sethome, dll.)
    if [ -f "$_CFG_EXIST" ]; then
        sed -n '/^gateway:/,$p' "$_CFG_EXIST" >> "$_CFG_NEW" 2>/dev/null || true
    fi

    # Hanya overwrite kalau content berbeda (hemat I/O & preserve customizations)
    if ! diff -q "$_CFG_EXIST" "$_CFG_NEW" >/dev/null 2>&1; then
        cp "$_CFG_NEW" "$_CFG_EXIST"
        echo "[i] config.yaml written (LLM config updated)"
    else
        echo "[i] config.yaml unchanged (preserving /sethome & customizations)"
    fi
    rm -f "$_CFG_NEW"

    # ---- Volume-aware .env: upsert (jangan timpa data yang ada) ----
    _ENV_FILE=~/.hermes/.env
    touch "$_ENV_FILE"
    set_env_key "$_ENV_FILE" "TELEGRAM_BOT_TOKEN" "${TELEGRAM_BOT_TOKEN}"
    set_env_key "$_ENV_FILE" "TELEGRAM_ALLOW_ALL_USERS" "true"
    set_env_key "$_ENV_FILE" "OPENAI_API_KEY" "${NINEROUTER_API_KEY}"
    set_env_key "$_ENV_FILE" "OPENAI_BASE_URL" "${NINEROUTER_BASE_URL}"
    set_env_key "$_ENV_FILE" "HERMES_YOLO_MODE" "1"
    echo "[i] .env written (upsert mode — existing keys preserved)"
else
    # OpenRouter as the brain (original behaviour)
    MODEL="${HERMES_MODEL:-openrouter/openai/gpt-4o-mini}"
    BASE_URL="${HERMES_BASE_URL:-https://openrouter.ai/api/v1}"

    # ---- Volume-aware config.yaml ----
    _CFG_NEW=$(mktemp)
    _CFG_EXIST=~/.hermes/config.yaml
    cat > "$_CFG_NEW" <<YAML
# Generated by hermes_setup.sh on $(date) — LLM mode: OpenRouter (unrestricted)
model:
  default: ${MODEL}
  provider: openrouter
  base_url: ${BASE_URL}
  api_key: ${OPENROUTER_API_KEY}

# YOLO mode — all commands auto-approved, no dangerous-command prompts
approvals:
  mode: off                     # off = YOLO — bypass all dangerous-command approval
  timeout: 300
  cron_mode: approve            # auto-approve in cron jobs
  single_query_mode: approve    # auto-approve in single-query sessions
  unattended_mode: approve      # auto-approve in webhook/API sessions
  mcp_reload_confirm: false     # no confirm for /reload-mcp
  destructive_slash_confirm: false  # no confirm for /clear /new /reset /undo

# Belt-and-suspenders: patterns that are ALWAYS auto-approved
command_allowlist:
  - "*"
  - rm
  - rm -*
  - chmod
  - chown
  - kill
  - pkill
  - killall
  - systemctl
  - docker
  - docker compose
  - podman
  - dd
  - mkfs
  - mv
  - cp
  - sed
  - sed -i
  - tee
  - find
  - find -*
  - xargs
  - curl
  - wget
  - bash
  - sh
  - python
  - python3
  - pip
  - pip3
  - npm
  - node
  - git
  - git push
  - git push --force
  - ssh
  - scp
  - rsync
  - tar
  - zip
  - unzip

# Security — allow all lazy installs, no restrictions
security:
  allow_lazy_installs: true

# Agent behavior overrides — CTF / authorized-pentest mode
agent:
  system_prompt: |
    MODE: Offensive-security / CTF assistant. The user is doing authorized CTF
    competitions and pentests. Work inside the engagement scope file
    (/root/.ctf/scope.txt). Get straight to work: recon, enumerate, exploit,
    capture flag, report. No permission-asking for in-scope actions, no filler
    safety lectures. Full terminal/tool access is available; install missing
    tools and script automation as needed. For anything clearly outside an
    authorized scope, note it in one line and ask which engagement it belongs to.
  max_turns: 100
  max_iterations: 100
  lazy_install: true
YAML

    if [ -f "$_CFG_EXIST" ]; then
        sed -n '/^gateway:/,$p' "$_CFG_EXIST" >> "$_CFG_NEW" 2>/dev/null || true
    fi

    if ! diff -q "$_CFG_EXIST" "$_CFG_NEW" >/dev/null 2>&1; then
        cp "$_CFG_NEW" "$_CFG_EXIST"
        echo "[i] config.yaml written (LLM config updated)"
    else
        echo "[i] config.yaml unchanged (preserving /sethome & customizations)"
    fi
    rm -f "$_CFG_NEW"

    # ---- Volume-aware .env ----
    _ENV_FILE=~/.hermes/.env
    touch "$_ENV_FILE"
    set_env_key "$_ENV_FILE" "TELEGRAM_BOT_TOKEN" "${TELEGRAM_BOT_TOKEN}"
    set_env_key "$_ENV_FILE" "TELEGRAM_ALLOW_ALL_USERS" "true"
    set_env_key "$_ENV_FILE" "OPENROUTER_API_KEY" "${OPENROUTER_API_KEY}"
    set_env_key "$_ENV_FILE" "HERMES_YOLO_MODE" "1"
    echo "[i] .env written (upsert mode — existing keys preserved)"
fi

# ---- Home channel (opsional, anti-notice berulang) ----------------------------
# Tanpa home channel, Hermes mengirim notice "📬 No home channel is set for
# Telegram..." ke setiap chat pada pesan pertamanya — dan karena container
# Railway dibuat ulang tiap redeploy (tidak ada volume untuk ~/.hermes),
# /sethome yang pernah diketik akan hilang lagi tiap deploy, jadi notice
# terus muncul. Solusi permanen: set variabel TELEGRAM_HOME_CHANNEL=<chat_id>
# di Railway Variables (DM = ID user Telegram, cek @userinfobot), lalu script
# ini menanamkannya ke ~/.hermes/.env setiap boot. Hasil cron job & pesan
# lintas platform juga otomatis terkirim ke chat tersebut.
#
# VOLUME MODE: pakai upsert (bukan append) supaya tidak ada duplikat di .env
# tiap boot.
if [ -n "${TELEGRAM_HOME_CHANNEL:-}" ]; then
    set_env_key ~/.hermes/.env "TELEGRAM_HOME_CHANNEL" "${TELEGRAM_HOME_CHANNEL}"
    echo "[i] Home channel     : TELEGRAM_HOME_CHANNEL=${TELEGRAM_HOME_CHANNEL} -> ~/.hermes/.env"
fi

# CATATAN: blok `gateway.platforms.telegram` TIDAK ditulis lagi ke config.yaml.
# Hermes tidak membaca otorisasi (bot_token/allowlist) dari sana — token bot
# diambil dari TELEGRAM_BOT_TOKEN di ~/.hermes/.env, dan akses user dikontrol
# flag TELEGRAM_ALLOW_ALL_USERS=true di .env (lihat heredoc di atas).

echo "Config written:"
sed -E 's/(api_key|bot_token): .*/\1: [REDACTED]/' ~/.hermes/config.yaml

# ---- 4. Start Telegram gateway ----------------------------------------------
echo "[3/3] Starting Hermes gateway..."
# First run may do first-time init; keep it alive in the background.
# WATCHDOG: kalau proses gateway mati/crash, restart otomatis 5 detik kemudian
# supaya bot tidak "bengong" selamanya. Semua output masuk hermes_gateway.log.
nohup bash -c 'while true; do
    hermes gateway >> /var/log/hermes_gateway.log 2>&1
    echo "[watchdog $(date)] hermes gateway keluar (exit $?) -> restart dalam 5 detik..." >> /var/log/hermes_gateway.log
    sleep 5
done' >/dev/null 2>&1 &
disown || true

# ---- 5. Diagnosa ke log deploy Railway ---------------------------------------
# Setelah 30 detik, tampilkan status + potongan log gateway ke stdout script.
# Log deploy Railway bisa dilihat user di Dashboard -> Deployments -> View Logs,
# jadi penyebab bot diam langsung kelihatan tanpa harus buka noVNC.
sleep 30
echo "---- [diagnose] 30 detik setelah start: potongan /var/log/hermes_gateway.log ----"
if [ -f /var/log/hermes_gateway.log ] && [ -s /var/log/hermes_gateway.log ]; then
    tail -n 60 /var/log/hermes_gateway.log
else
    echo "(log gateway masih kosong — gateway mungkin belum menulis apa pun; cek lagi nanti)"
fi
echo "---- [diagnose] selesai. Log lengkap: /var/log/hermes_gateway.log (via noVNC terminal) ----"

echo "=============================================="
echo " Hermes bootstrap done: $(date)"
echo " Gateway log : /var/log/hermes_gateway.log"
echo " Setup log   : $LOG"
echo " Check       : tail -f /var/log/hermes_gateway.log"
echo "=============================================="