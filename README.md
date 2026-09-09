# 🤖 Hermes Agent on Railway — Free VPS + Telegram Bot

Repo gabungan: **Hermes Agent (Nous Research)** yang berjalan di atas **Free VPS (Ubuntu 22.04 + XFCE4 desktop + noVNC)** yang di-deploy di **Railway**.

Dengan repo ini kamu dapat 2 hal sekaligus:

1. **VPS Ubuntu dengan desktop** (akses dari browser lewat noVNC) — punya terminal root sendiri.
2. **Hermes Agent langsung jalan & bisa chat dari Telegram** (pakai `@BotFather`, tinggal chat di HP).

---

## 🚀 Cara Deploy (Langkah 1–4)

### 1) Fork repo ini ke akun GitHub kamu
Buka <https://github.com/Lyvelia/free-vps-railway> → tombol **Fork** di kanan atas.

> Repo ini isi ulang (Hermes + VPS + Telegram). Kalau mau 100% isi asli Lyvelia, fork langsung tanpa perubahan dan ikuti cara manual di README aslinya.

### 2) Deploy ke Railway (2 service dari 1 repo)
1. Buka **<https://railway.app>** → login pakai **GitHub**.
2. Klik **New Project** → **Deploy from GitHub repo** → pilih hasil fork kamu.
3. Railway otomatis baca `railway.json` & `Dockerfile` → **service utama** (VPS + Hermes) ter-deploy. Tunggu sampai status **Active/Healthy**.
4. **Tambah service 9Router**: di canvas project → klik **+ New** → **Empty Service** → pilih service baru itu → tab **Settings**:
   - **Source** → **Docker Image** → isi `decolua/9router:latest`
   - **Networking → Generate Domain** → isi `20128` sebagai port → dapat URL `https://xxx.up.railway.app` (ini untuk dashboard 9Router, nanti kamu akses dari dalam VPS via browser)
5. Kembali ke **service utama** (VPS): **Settings → Networking → Generate Domain** → dapat URL noVNC.
6. **Settings → Region**: pilih **Singapore** untuk kedua service (biar koneksi dari Indonesia kencang & komunikasi antar service cepat via private network).

### 3) Buat token Telegram bot
1. Buka Telegram, cari **[@BotFather](https://t.me/BotFather)**.
2. Ketik `/newbot` → ikuti instruksi (nama bebas, username harus diakhiri `bot`, misal `hermes_saya_bot`).
3. BotFather kasih **token** seperti `7123456789:AAF...`. Simpan baik-baik.
4. (Disarankan) Cari bot kamu lalu tekan **Start** dan kirim pesan apa pun, supaya bot bisa chat kamu duluan.

### 4) Set variabel environment
Di Railway: buka service kamu → tab **Variables** → tambahkan:

| Nama | Contoh | Wajib? | Fungsi |
|---|---|---|---|
| `HERMES_AUTOSTART` | `true` | ✅ | Menyalakan auto-install Hermes di VPS |
| `TELEGRAM_BOT_TOKEN` | `7123456789:AAF...` | ✅ | Token bot dari BotFather |
| `HERMES_LLM_MODE` | `nine_router` | ❌ (default) | Otak LLM: `nine_router` (gratis) atau `openrouter` |
| `HERMES_NINEROUTER_BASE_URL` | `http://nine-router.railway.internal:20128/v1` | ❌ (default) | Alamat 9Router lewat private networking Railway |
| `HERMES_NINEROUTER_API_KEY` | `9r_xxxxxxxx` | ✅ (mode 9Router) | API key dari dashboard 9Router (lihat bawah) |
| `HERMES_MODEL` | `kr/claude-sonnet-4.5` | opsional | Model 9Router yang dipakai Hermes |
| `OPENROUTER_API_KEY` | `sk-or-v1-...` | ❌ | Hanya untuk mode `openrouter` |
| `HERMES_ALLOWED_USERS` | `123456789,987654321` | opsional | Whitelist ID Telegram (kosongkan = semua orang bisa chat bot) |
| `VNC_PASSWORD` | `rahasia123` | opsional | Password akses desktop VPS |

Cara dapat **ID Telegram**: chat ke **[@userinfobot](https://t.me/userinfobot)** → lihat angka `Id`.

Setelah menambah variabel → tab **Deployments** → klik **Redeploy** agar variabel baru dipakai.

> Saat pertama kali jalan, install Hermes butuh ± 2–5 menit lagi. Cek log di **Deployments → View Logs** sampai muncul pesan `Hermes bootstrap done` atau buka chat bot kamu.

---

## 🧠 Otak LLM Gratis: 9Router (default)

Bot ini default-nya pakai **[9Router](https://github.com/decolua/9router)** — router AI gratis yang menyambungkan Hermes ke **Claude / GPT / Gemini / Kimi / Qwen & 100+ model lain** lewat provider gratis & langgananmu. Hermes tidak butuh `OPENROUTER_API_KEY` sama sekali di mode ini.

**Cara kerja di Railway:** 9Router jalan sebagai container kedua di dalam project yang sama. Hermes memanggilnya lewat **private networking** Railway: `http://nine-router.railway.internal:20128/v1` — tanpa biaya, tanpa terpapar ke internet. Kamu mengatur provider-nya lewat **dashboard 9Router dari browser di dalam desktop VPS**.

### Setup 9Router (sekali saja, ± 5 menit)

1. Deploy project ini di Railway & buka URL noVNC-nya (desktop Ubuntu di browser).
2. Di desktop VPS, buka **Web Browser** → alamat `http://localhost:20128`.
3. Login dashboard 9Router (password awal `123456` — **ganti di Settings setelah login**).
4. **Providers → Connect** — hubungkan provider yang kamu punya (mis. akun **b.ai**), atau provider gratis tanpa kartu: **Kiro** (Claude 4.5), **iFlow** (Kimi K2, Qwen, GLM), **OpenCode Free**.
5. **Settings → API Keys → copy** API key kamu (format `9r_...`).
6. Di Railway → **Variables** → tambahkan `HERMES_NINEROUTER_API_KEY = 9r_...` → **Redeploy**.
7. Cek log sampai muncul `Hermes bootstrap done` → chat bot dari Telegram. 🎉

> Model default yang diminta Hermes dari 9Router: `kr/claude-sonnet-4.5`. Ganti lewat variabel `HERMES_MODEL` — daftar lengkap model ada di dashboard 9Router (`cc/...`, `kr/...`, `if/...`, `qw/...`, dll). Kalau satu model limit, 9Router otomatis fallback ke model berikutnya.

> ⚠️ Jangan menghapus container 9Router di Railway. Kalau dashboard 9Router belum kamu login / belum ada provider aktif, bot Telegram akan diam — buka dashboard-nya dari desktop VPS dulu.

---

## 🔄 Pakai OpenRouter saja (mode lama)

Mau tetap pakai API key `sk-or-...`? Set di Railway:

```
HERMES_LLM_MODE = openrouter
OPENROUTER_API_KEY = sk-or-v1-...
```

Lalu **Redeploy**. Tidak perlu variabel 9Router di mode ini.

---

## ✉️ Pakai Hermes dari Telegram

- Buka bot kamu di Telegram → **Start** → langsung chat.
- Contoh perintah:
  - `/help` — daftar perintah
  - `/new` — mulai sesi baru
  - `/model` — ganti model (kalau versi mendukung)
  - Kirim **voice note** → otomatis ditranskrip.
- Hermes punya **memori permanen** dan bisa **membuat skill sendiri** — makin sering dipakai makin pintar.

> Kalau bot tidak membalas:
> 1. Cek log Railway (`Deployments → View Logs`) — cari `Hermes bootstrap done` (sukses) atau pesan `[!]`.
> 2. Kalau muncul `HERMES_NINEROUTER_API_KEY is not set`, ikuti langkah **Setup 9Router** di atas dulu.
> 3. Pastikan dashboard 9Router sudah login & ada provider aktif.
> 4. Pastikan tombol **Start** sudah ditekan di bot Telegram.

---

## 🖥️ Akses Desktop VPS dari Browser

- Buka URL Railway kamu → halaman **noVNC** langsung tampil → klik **Connect**.
- Kamu masuk ke **desktop Ubuntu XFCE4** dengan terminal **root**.
- Untuk kontrol manual Hermes, buka terminal di desktop lalu:
  ```bash
  # Lihat status / log Hermes
  tail -f /var/log/hermes_gateway.log

  # Setup ulang interaktif (provider, telegram, dll)
  hermes setup

  # Chat langsung di terminal VPS (bukan via Telegram)
  hermes
  ```
- Struktur file penting di dalam VPS:
  - `~/.hermes/config.yaml` — konfigurasi Hermes
  - `/var/log/hermes_setup.log` — log bootstrap
  - `/var/log/hermes_gateway.log` — log gateway

---

## ⏰ Biar VPS Tidak "Sleep"

Railway mematikan container kalau tidak ada traffic. Opsi:

**A. GitHub Actions (sudah tersedia di repo hasil fork)**
1. Di repo GitHub kamu: **Settings → Secrets and variables → Actions → New repository secret**.
2. **Name**: `VPS_URL`, **Secret**: URL Railway kamu.
3. Workflow `.github/workflows/keep_alive.yml` akan ping otomatis.

**B. Uptime monitor gratis**
Daftar di **cron-job.org** / **UptimeRobot.com** → monitor URL Railway tiap 2–5 menit.

> Catatan: kalau pake **trial gratis Railway**, ingat triknya — project bisa di-**backup** (Settings → backup atau export) lalu dibuat akun baru.

---

## 📁 Struktur File

```text
Hermes Raywal/
├── Dockerfile            # Ubuntu 22.04 + XFCE4 + noVNC (+ curl & python3-venv)
├── startup.sh            # Xvfb + desktop + x11vnc + noVNC + panggil hermes_setup
├── hermes_setup.sh       # Install Hermes & jalankan gateway Telegram (LLM: 9Router/OpenRouter)
├── railway.json          # Konfigurasi deploy Railway (service utama: hermes)
├── docker-compose.yml    # Testing lokal: hermes-free-vps + 9router
├── .github/workflows/keep_alive.yml  # Ping 24/7 via GitHub Actions
├── README.md             # Dokumen ini
└── .gitignore
```

> ⚠️ **PENTING untuk deploy Railway**: Railway cuma menjalankan **satu** Dockerfile per service. Deploy **2 service terpisah** dari repo yang sama (lihat bagian Railway di atas). `docker-compose.yml` di file ini khusus **testing lokal** (menjalankan keduanya sekaligus).

---

## 🛠️ Testing Lokal (Opsional)

Sudah install Docker + Docker Compose? Jalankan dari folder ini:

```bash
docker compose up --build
```

- VPS (noVNC): buka `http://localhost:6080` di browser
- Dashboard 9Router: buka `http://localhost:20128` di browser

Untuk tes Hermes + 9Router (isikan token di file `docker-compose.yml` atau via env):
```bash
TELEGRAM_BOT_TOKEN=xxx HERMES_NINEROUTER_API_KEY=9r_xxx docker compose up --build
```

---

## 🔐 Keamanan

- `VPS_URL` dan `VPS_PASSWORD` hanya untuk kamu — jangan share.
- Set `HERMES_ALLOWED_USERS` supaya cuma ID Telegram tertentu yang bisa pakai bot.
- Jangan commit token bot / API key ke GitHub. Untuk mode 9Router, jangan share `HERMES_NINEROUTER_API_KEY` atau `INITIAL_PASSWORD` dashboard-nya.
- Ganti password 9Router setelah login pertama dari dashboard.

---

## 🧾 Kredit

- Repo VPS asli: [Lyvelia/free-vps-railway](https://github.com/Lyvelia/free-vps-railway)
- Hermes Agent: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) · MIT License
- AI Router: [decolua/9router](https://github.com/decolua/9router) · MIT License
- Dokumentasi Hermes: <https://hermes-agent.nousresearch.com/docs/>
- Dokumentasi 9Router: <https://9router.github.io>
