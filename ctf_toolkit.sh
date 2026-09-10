#!/bin/bash
# =============================================================================
# ctf_toolkit.sh — CTF / pentest toolkit installer + workflow helper
#
# PURPOSE: install additional security tooling on demand and provide a small
#          recon/enumeration harness for AUTHORIZED targets only — i.e. CTF
#          competition boxes, lab machines, or systems you own / have written
#          permission to test.
#
# SCOPE / SAFETY: every scan helper requires the target to appear in a scope
#          file (see `scope` command below). This is standard rules-of-
#          engagement practice and keeps runs provably authorized.
#
# USAGE:
#   bash /opt/ctf_toolkit.sh install        # install heavy tools on demand
#   bash /opt/ctf_toolkit.sh status         # show what is installed
#   bash /opt/ctf_toolkit.sh scope add IP/HOST
#   bash /opt/ctf_toolkit.sh scope list
#   bash /opt/ctf_toolkit.sh recon <target> [outdir]
#   bash /opt/ctf_toolkit.sh help
# =============================================================================
set -uo pipefail

SCOPE_FILE="${CTF_SCOPE_FILE:-/root/.ctf/scope.txt}"
WORK_BASE="${CTF_WORK_DIR:-/root/ctf}"

c_green() { printf '\033[32m%s\033[0m\n' "$*"; }
c_red()   { printf '\033[31m%s\033[0m\n' "$*"; }
c_blue()  { printf '\033[36m%s\033[0m\n' "$*"; }

ensure_dirs() {
    mkdir -p "$(dirname "$SCOPE_FILE")" "$WORK_BASE"
    [ -f "$SCOPE_FILE" ] || { echo "# CTF scope — one target (IP/host/CIDR) per line" > "$SCOPE_FILE"; }
}

# ---------------------------------------------------------------------------
# install — on-demand heavy tools (metasploit, seclists, wordlists, etc.)
# ---------------------------------------------------------------------------
do_install() {
    c_blue "[*] Installing heavy CTF tooling (may take a few minutes)..."
    export DEBIAN_FRONTEND=noninteractive

    apt-get update || true
    apt-get install -y --no-install-recommends \
        metasploit-framework \
        exploitdb \
        wfuzz \
        commix \
        responder \
        crackmapexec \
        enum4linux \
        smbclient \
        nikto \
        zaproxy \
        tmux \
        screen \
        vim \
        curl \
        wget \
        git \
        2>/dev/null || echo "[warn] some apt packages unavailable"

    # SecLists wordlists
    if [ ! -d /usr/share/seclists ]; then
        git clone --depth 1 https://github.com/danielmiessler/SecLists.git \
            /usr/share/seclists 2>/dev/null \
            && c_green "[+] SecLists installed at /usr/share/seclists" \
            || echo "[warn] SecLists clone failed"
    fi

    # Payloads reference
    [ -d /opt/payloads ] || \
        git clone --depth 1 https://github.com/swisskyrepo/PayloadsAllTheThings.git \
            /opt/payloads 2>/dev/null || true

    # pwndbg for gdb
    if command -v gdb >/dev/null 2>&1 && [ ! -d /opt/pwndbg ]; then
        git clone --depth 1 https://github.com/pwndbg/pwndbg /opt/pwndbg 2>/dev/null \
            && (cd /opt/pwndbg && ./setup.sh 2>/dev/null) \
            && c_green "[+] pwndbg installed" || echo "[warn] pwndbg setup skipped"
    fi

    c_green "[+] install pass selesai. Cek dengan: bash $0 status"
}

# ---------------------------------------------------------------------------
# status — what's available right now
# ---------------------------------------------------------------------------
do_status() {
    c_blue "== CTF toolkit status =="
    local tools=(nmap sqlmap hydra john hashcat masscan netcat nc socat
                 ffuf gobuster dirb nikto wfuzz msfconsole searchsploit
                 gdb radare2 r2 binwalk steghide exiftool tcpdump
                 crackmapexec enum4linux smbclient
                 python3 pip3 gcc g++ ruby go)
    for t in "${tools[@]}"; do
        if command -v "$t" >/dev/null 2>&1; then
            printf '  [OK] %-22s %s\n' "$t" "$(command -v "$t")"
        else
            printf '  [--] %-22s (not installed)\n' "$t"
        fi
    done
    echo
    c_blue "== Python libs =="
    python3 - <<'PY' 2>/dev/null || true
mods = ["pwn","requests","Crypto","z3","capstone","keystone","unicorn","ropper","angr","scapy","bs4","jwt","paramiko","impacket"]
for m in mods:
    try:
        __import__(m); print(f"  [OK] {m}")
    except Exception:
        print(f"  [--] {m} (missing)")
PY
    echo
    c_blue "== Wordlists =="
    [ -d /usr/share/seclists ] && echo "  [OK] /usr/share/seclists" || echo "  [--] SecLists not installed (run: $0 install)"
    [ -f /usr/share/wordlists/rockyou.txt ] && echo "  [OK] rockyou.txt" \
        || echo "  [--] rockyou.txt (install with: $0 install)"
}

# ---------------------------------------------------------------------------
# scope — rules-of-engagement target list
# ---------------------------------------------------------------------------
do_scope() {
    ensure_dirs
    local sub="${1:-list}"; shift || true
    case "$sub" in
        add)
            [ -z "${1:-}" ] && { c_red "usage: $0 scope add IP_OR_HOST"; return 1; }
            if grep -qxF "$1" "$SCOPE_FILE" 2>/dev/null; then
                c_blue "[=] $1 sudah ada di scope"
            else
                echo "$1" >> "$SCOPE_FILE"; c_green "[+] $1 ditambahkan ke scope"
            fi
            ;;
        del|remove)
            [ -z "${1:-}" ] && { c_red "usage: $0 scope del IP_OR_HOST"; return 1; }
            sed -i "\|^${1}$|d" "$SCOPE_FILE"; c_green "[-] $1 dihapus dari scope"
            ;;
        list|*)
            c_blue "== Authorized CTF scope ($SCOPE_FILE) =="
            grep -v '^#' "$SCOPE_FILE" 2>/dev/null | grep -v '^$' || echo "  (kosong — tambah dengan: $0 scope add <target>)"
            ;;
    esac
}

in_scope() {
    local target="$1"
    [ -f "$SCOPE_FILE" ] || return 1
    grep -v '^#' "$SCOPE_FILE" 2>/dev/null | grep -v '^$' | while read -r entry; do
        if [ "$entry" = "$target" ] || [[ "$target" == $entry* ]]; then
            echo "match"; break
        fi
    done | grep -q match
}

# ---------------------------------------------------------------------------
# recon — scope-checked enumeration of an authorized target
# ---------------------------------------------------------------------------
do_recon() {
    local target="${1:-}"
    [ -z "$target" ] && { c_red "usage: $0 recon <target> [outdir]"; return 1; }
    ensure_dirs

    if ! in_scope "$target"; then
        c_red "[!] REFUSED: '$target' tidak ada di scope file ($SCOPE_FILE)."
        c_red "    CTF/lab targets only. Tambah dulu: $0 scope add $target"
        return 2
    fi

    local out="${2:-$WORK_BASE/$target}"
    mkdir -p "$out"
    c_green "[+] Authorized target: $target  ->  output: $out"

    c_blue "[1/4] Port & service scan (nmap -sV -sC)..."
    if command -v nmap >/dev/null 2>&1; then
        nmap -sV -sC -T4 -oN "$out/nmap.txt" "$target" 2>&1 | tee "$out/nmap_stdio.txt"
    else
        echo "  nmap tidak terinstall" | tee "$out/nmap.txt"
    fi

    c_blue "[2/4] Web fingerprint (whatweb / curl headers)..."
    if command -v whatweb >/dev/null 2>&1; then
        timeout 60 whatweb -a 3 "$target" > "$out/whatweb.txt" 2>&1 || true
    fi
    { curl -sSI "http://$target" ; curl -sSI "https://$target" ; } \
        > "$out/http_headers.txt" 2>&1 || true

    c_blue "[3/4] Directory brute (ffuf/gobuster, jika web up)..."
    local wl="/usr/share/seclists/Discovery/Web-Content/common.txt"
    [ -f "$wl" ] || wl="/usr/share/wordlists/dirb/common.txt"
    if [ -f "$wl" ]; then
        if command -v ffuf >/dev/null 2>&1; then
            ffuf -u "http://$target/FUZZ" -w "$wl" -mc 200,204,301,302,307,401,403 \
                 -of json -o "$out/ffuf.json" >/dev/null 2>&1 || true
        elif command -v gobuster >/dev/null 2>&1; then
            gobuster dir -u "http://$target" -w "$wl" \
                     -o "$out/gobuster.txt" >/dev/null 2>&1 || true
        fi
    else
        echo "  wordlist tidak ada — jalankan: $0 install" > "$out/dirb.txt"
    fi

    c_blue "[4/4] Summary"
    {
        echo "== CTF recon summary for $target =="
        echo "date: $(date)"
        echo
        echo "-- open ports --"
        grep -E '^[0-9]+/tcp' "$out/nmap.txt" 2>/dev/null || echo "(none parsed)"
    } | tee "$out/SUMMARY.txt"

    c_green "[+] Selesai. Hasil ada di: $out"
}

# ---------------------------------------------------------------------------
# help
# ---------------------------------------------------------------------------
do_help() {
    cat <<'HELP'
ctf_toolkit.sh — CTF / pentest toolkit + workflow helper

  install                 Install heavy tooling (metasploit, SecLists, pwndbg, ...)
  status                  Show installed tools, python libs, wordlists
  scope add <target>      Add an AUTHORIZED target to the scope file
  scope del <target>      Remove a target
  scope list              Show the scope file
  recon <target> [outdir] Run scope-checked recon (nmap + web + dirb)
  help                    This text

Env:
  CTF_SCOPE_FILE  (default /root/.ctf/scope.txt)
  CTF_WORK_DIR    (default /root/ctf)

NOTE: recon only runs against targets present in the scope file — CTF boxes,
lab machines, or hosts you own / have written authorization to test.
HELP
}

ensure_dirs
cmd="${1:-help}"; shift || true
case "$cmd" in
    install) do_install "$@" ;;
    status)  do_status  "$@" ;;
    scope)   do_scope   "$@" ;;
    recon)   do_recon   "$@" ;;
    help|-h|--help) do_help ;;
    *) c_red "unknown command: $cmd"; echo; do_help; exit 1 ;;
esac
