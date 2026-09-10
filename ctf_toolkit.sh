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
#   bash /opt/ctf_toolkit.sh wordlist <target>
#   bash /opt/ctf_toolkit.sh privesc [linux|win]
#   bash /opt/ctf_toolkit.sh flags [dir]
#   bash /opt/ctf_toolkit.sh writeup <target>
#   bash /opt/ctf_toolkit.sh multi [-j N] [-f list] <targets...>
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
# wordlist — build a target-specific wordlist from recon output
# ---------------------------------------------------------------------------
do_wordlist() {
    local target="${1:-}"
    [ -z "$target" ] && { c_red "usage: $0 wordlist <target> [outdir]"; return 1; }
    ensure_dirs
    local out="${2:-$WORK_BASE/$target}"
    local wl="$out/wordlist.txt"
    mkdir -p "$out"

    c_blue "[*] Building custom wordlist for $target ..."
    : > "$wl"

    {
        echo "$target" | tr '.' '\n'
        echo "$target"
        [ -f "$out/nmap.txt" ] && {
            grep -oE '(http|ssh|ftp|smtp|dns|mysql|postgres|redis|mongodb)[a-z0-9._-]*' "$out/nmap.txt"
            grep -E '^[0-9]+/tcp' "$out/nmap.txt" | awk '{print $1}' | tr -d '/tcp'
            grep -iE 'host:|server:' "$out/nmap.txt" | awk '{print $2}'
        }
        [ -f "$out/gobuster.txt" ] && awk -F/ '{print $1}' "$out/gobuster.txt" 2>/dev/null
        [ -f "$out/http_headers.txt" ] && grep -iE 'server:|x-powered-by:' "$out/http_headers.txt" \
            | tr ' /;' '\n' | grep -vE '^$|^server|^x-powered'
    } 2>/dev/null | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9._-' \
        | awk 'length>=3 && length<=30' | sort -u > "$wl"

    if [ -s "$wl" ]; then
        awk '{print $0; print $0"1"; print $0"123"; print $0"2025"}' "$wl" \
            | sort -u > "$wl.mut"
        sort -u "$wl.mut" -o "$wl"; rm -f "$wl.mut"
    fi
    local n; n=$(wc -l < "$wl" 2>/dev/null || echo 0)
    c_green "[+] wordlist: $wl ($n entries)"
}

# ---------------------------------------------------------------------------
# privesc — fetch linpeas/winpeas for post-exploitation
# ---------------------------------------------------------------------------
do_privesc() {
    local os="${1:-linux}"
    ensure_dirs
    local dir="$WORK_BASE/privesc"; mkdir -p "$dir"
    c_blue "[*] Preparing privesc helper ($os) in $dir"

    case "$os" in
        linux|lin|peas|linpeas)
            if [ ! -s "$dir/linpeas.sh" ]; then
                curl -fsSL -o "$dir/linpeas.sh" \
                    https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh \
                    || { c_red "[!] download linpeas gagal"; return 1; }
                chmod +x "$dir/linpeas.sh"
            fi
            c_green "[+] linpeas: $dir/linpeas.sh"
            echo "    Transfer:  ./linpeas.sh -a 2>&1 | tee /tmp/lp.txt"
            ;;
        win|windows|winpeas)
            if [ ! -s "$dir/winPEASx64.exe" ]; then
                curl -fsSL -o "$dir/winPEASx64.exe" \
                    https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx64.exe \
                    || { c_red "[!] download winPEAS gagal"; return 1; }
            fi
            c_green "[+] winPEAS: $dir/winPEASx64.exe"
            ;;
        *) c_red "usage: $0 privesc [linux|win]"; return 1 ;;
    esac
    echo "[i] GTFOBins: https://gtfobins.github.io/"
}

# ---------------------------------------------------------------------------
# flags — search loot for flag{...} patterns
# ---------------------------------------------------------------------------
do_flags() {
    local dir="${1:-$WORK_BASE}"
    [ -d "$dir" ] || { c_red "usage: $0 flags [dir]"; return 1; }
    c_blue "[*] Scanning $dir for flags ..."
    local hits
    hits=$(grep -RaoE '[A-Za-z0-9_]{2,20}\{[^}]{1,120}\}' "$dir" 2>/dev/null \
        | grep -iE '(flag|htb|thm|pico|ctf|ductf|ractf|csr)' | sort -u)
    hits="$hits"$'\n'"$(grep -RaoE '[A-Za-z0-9_]{2,20}\{[0-9a-fA-F]{16,64}\}' "$dir" 2>/dev/null | sort -u)"
    hits=$(echo "$hits" | grep -vE '^\s*$' | sort -u)
    if [ -n "$hits" ]; then
        c_green "[+] Flags found:"; echo "$hits"
        echo "$hits" > "$dir/FLAGS_FOUND.txt"
    else
        c_blue "[=] No flags yet in $dir — unzip loot or search deeper"
    fi
}

# ---------------------------------------------------------------------------
# writeup — generate markdown writeup from recon data
# ---------------------------------------------------------------------------
do_writeup() {
    local target="${1:-}"
    [ -z "$target" ] && { c_red "usage: $0 writeup <target> [outdir]"; return 1; }
    local out="${2:-$WORK_BASE/$target}"
    [ -d "$out" ] || { c_red "[!] run recon first: $out"; return 1; }
    local wu="$out/WRITEUP.md"
    c_blue "[*] Generating writeup -> $wu"
    {
        echo "# CTF Writeup — $target"; echo
        echo "- Date: $(date)"
        echo "## 1. Recon"
        echo '```'; grep -E '^[0-9]+/tcp|^[0-9]+/udp' "$out/nmap.txt" 2>/dev/null \
            | head -50 || true; echo '```'
        [ -s "$out/http_headers.txt" ] && { echo "### HTTP headers"; echo '```'; head -30 "$out/http_headers.txt"; echo '```'; }
        echo; echo "## 2. Enumeration"; echo "_(see ffuf.json / gobuster.txt)_"
        echo; echo "## 3. Exploitation"; echo "_(fill: vuln + payload)_"
        echo; echo "## 4. Privesc"; echo "_(linpeas/winpeas findings)_"
        echo; echo "## 5. Flag"; echo '```'
        [ -s "$out/FLAGS_FOUND.txt" ] && cat "$out/FLAGS_FOUND.txt" || echo "<flag>"
        echo '```'
    } > "$wu"
    do_flags "$out" 2>/dev/null || true
    c_green "[+] writeup: $wu"
}

# ---------------------------------------------------------------------------
# multi — parallel recon over several in-scope targets
# ---------------------------------------------------------------------------
do_multi() {
    ensure_dirs
    local jobs=4 targets=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -j|--jobs) jobs="$2"; shift 2 ;;
            -f|--file) while IFS= read -r l; do
                          l="${l%%#*}"; l="$(echo "$l" | xargs)"
                          [ -n "$l" ] && targets+=("$l")
                       done < "$2"; shift 2 ;;
            *) targets+=("$1"); shift ;;
        esac
    done
    if [ ${#targets[@]} -eq 0 ]; then
        while IFS= read -r l; do
            l="${l%%#*}"; l="$(echo "$l" | xargs)"
            [ -n "$l" ] && targets+=("$l")
        done < <(grep -v '^#' "$SCOPE_FILE" 2>/dev/null)
    fi
    [ ${#targets[@]} -eq 0 ] && { c_red "[!] no targets. $0 scope add <t>"; return 1; }

    c_blue "[*] Parallel recon: ${#targets[@]} targets, max-jobs=$jobs"
    local pids=()
    for t in "${targets[@]}"; do
        in_scope "$t" || { c_red "  skip (out of scope): $t"; continue; }
        bash "$0" recon "$t" & pids+=("$!")
        while [ "$(jobs -r | wc -l)" -ge "$jobs" ]; do sleep 0.5; done
    done
    for p in "${pids[@]}"; do wait "$p" 2>/dev/null; done
    c_green "[+] All recon done. Results in $WORK_BASE/<target>/"
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
  wordlist <target>       Build a target-specific wordlist from recon output
  privesc [linux|win]     Fetch linpeas/winPEAS for post-exploitation
  flags [dir]             Search loot/recon output for flag{...} patterns
  writeup <target>        Generate a markdown writeup from the work dir
  multi [-j N] [-f list] <t...>  Parallel recon over several in-scope targets
  help                    This text

Env:
  CTF_SCOPE_FILE  (default /root/.ctf/scope.txt)
  CTF_WORK_DIR    (default /root/ctf)

NOTE: recon/wordlist/multi only run against targets present in the scope file —
CTF boxes, lab machines, or hosts you own / have written authorization to test.
HELP
}

ensure_dirs
cmd="${1:-help}"; shift || true
case "$cmd" in
    install)  do_install  "$@" ;;
    status)   do_status   "$@" ;;
    scope)    do_scope    "$@" ;;
    recon)    do_recon    "$@" ;;
    wordlist) do_wordlist "$@" ;;
    privesc)  do_privesc  "$@" ;;
    flags)    do_flags    "$@" ;;
    writeup)  do_writeup  "$@" ;;
    multi)    do_multi    "$@" ;;
    help|-h|--help) do_help ;;
    *) c_red "unknown command: $cmd"; echo; do_help; exit 1 ;;
esac
