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

### 2) Deploy ke Railway (2 service dalam 1 project)

Kenapa **2 service**? Hermes (bot Telegram) dan 9Router (otak AI) jalan sebagai container terpisah. Hermes memanggil 9Router lewat **jaringan internal Railway** (`nama-service.railway.internal`) — gratis & tidak perlu domain publik. Tapi untuk **login dashboard 9Router**, kamu butuh domain publik service 9Router yang dibuka dari browser PC kamu.

**A. Buat Service 1 — VPS + Hermes (otomatis):**
1. Buka **<https://railway.app>** → login pakai **GitHub**.
2. **New Project** → **Deploy from GitHub repo** → pilih repo `heeeerrr` kamu.
3. Railway baca `railway.json` + `Dockerfile` → service pertama ter-deploy (VPS desktop + Hermes). Tunggu status **Active/Healthy**.
4. Klik judul service → rename jadi `hermes-free-vps` (biar rapi).
5. Di service ini: **Settings → Networking → Generate Domain** (port `6080`) → dapat URL noVNC `https://xxx.up.railway.app` — buat akses desktop VPS.

**B. Buat Service 2 — 9Router (manual):**
1. Klik tombol **+ New** di canvas project → pilih **Empty Service**.
2. Klik service baru → **Settings → Source** → pilih **Docker Image** → isi `decolua/9router:latest`.
3. Klik judul service → rename jadi **persis** `nine-router`.
   > ⚠️ Nama ini WAJIB. Hermes mencarinya di `http://nine-router.railway.internal:20128`. Kalau namanya beda, kamu harus isi sendiri variabel `HERMES_NINEROUTER_BASE_URL`.
4. Di panel service 9Router:
   - **Public Networking → Generate Domain** → isi port **`20128`** → dapat URL `https://9router-xxxx.up.railway.app`. **Catat URL ini** — dipakai login dashboard 9Router dari browser PC kamu.
   - **Volumes → Add Volume** → mount path **`/app/data`** (disarankan) — biar data provider & API key tidak hilang saat redeploy.
   - **Variables** → tambahkan:
     ```
     PORT = 20128
     INITIAL_PASSWORD = 123456
     REQUIRE_API_KEY = true
     NODE_ENV = production
     DATA_DIR = /app/data
     ```
     > Ganti `INITIAL_PASSWORD` dengan password kuat setelah login pertama di dashboard.
5. Di kedua service: **Settings → Region = Singapore** biar koneksi dari Indonesia kencang & komunikasi antar service cepat.
6. Lanjut set variabel bot di **Service 1 (`hermes-free-vps`)** — lihat bagian **4) Set variabel environment** di bawah.

### 3) Buat token Telegram bot
1. Buka Telegram, cari **[@BotFather](https://t.me/BotFather)**.
2. Ketik `/newbot` → ikuti instruksi (nama bebas, username harus diakhiri `bot`, misal `hermes_saya_bot`).
3. BotFather kasih **token** seperti `7123456789:AAF...`. Simpan baik-baik.
4. (Disarankan) Cari bot kamu lalu tekan **Start** dan kirim pesan apa pun, supaya bot bisa chat kamu duluan.

### 4) Set variabel environment

**Di service `hermes-free-vps`:** buka service → tab **Variables** → tambahkan:

| Nama | Contoh | Wajib? | Fungsi |
|---|---|---|---|
| `HERMES_AUTOSTART` | `true` | ✅ | Menyalakan auto-install Hermes di VPS |
| `TELEGRAM_BOT_TOKEN` | `7123456789:AAF...` | ✅ | Token bot dari BotFather |
| `HERMES_LLM_MODE` | `nine_router` | ❌ (default) | Otak LLM: `nine_router` (gratis) atau `openrouter` |
| `HERMES_NINEROUTER_BASE_URL` | `http://nine-router.railway.internal:20128/v1` | ❌ (default) | Alamat 9Router lewat private networking Railway |
| `HERMES_NINEROUTER_API_KEY` | `9r_xxxxxxxx` | ✅ (mode 9Router) | API key dari dashboard 9Router (lihat bawah) |
| `HERMES_MODEL` | `kr/claude-sonnet-4.5` (otomatis) | opsional | Kosong = script pilih otomatis via `/v1/models` dari urutan `kr/claude-sonnet-4.5` → `kr/deepseek-3.2` (yang pertama tersedia). Isi eksplisit mis. `kr/deepseek-3.2` untuk memaksa DeepSeek — typo juga otomatis dikoreksi ke model yang tersedia |
| `OPENROUTER_API_KEY` | `sk-or-v1-...` | ❌ | Hanya untuk mode `openrouter` |
| `VNC_PASSWORD` | `rahasia123` | opsional | Password akses desktop VPS |

**Di service `nine-router`:** buka service → tab **Variables** → tambahkan:

| Nama | Contoh | Wajib? | Fungsi |
|---|---|---|---|
| `PORT` | `20128` | ✅ | Port dashboard 9Router |
| `INITIAL_PASSWORD` | `123456` | opsional | Password login awal dashboard (default: `123456`) |
| `NODE_ENV` | `production` | opsional | Mode produksi |
| `DATA_DIR` | `/app/data` | opsional | Lokasi data (kalau pakai volume mount `/app/data`) |
| `REQUIRE_API_KEY` | `true` | opsional | Wajibkan API key untuk akses `/v1/*` (disarankan untuk deploy publik) |

> **Cara dapat ID Telegram:** chat ke **[@userinfobot](https://t.me/userinfobot)** → lihat angka `Id`.
>
> **Multi-user:** bot Hermes terbuka untuk **semua** pengguna — script menulis `TELEGRAM_ALLOW_ALL_USERS=true` ke `~/.hermes/.env` (flag otorisasi resmi Hermes; gateway membacanya dari `.env`, bukan `config.yaml`). Siapa pun yang chat ke bot akan dibalas, masing-masing punya chat sendiri. Tidak perlu whitelist ID lagi; variabel `HERMES_ALLOWED_USERS` sudah tidak dipakai.

Setelah menambah variabel → tab **Deployments** → klik **Redeploy** agar variabel baru dipakai.

> Saat pertama kali jalan, install Hermes butuh ± 2–5 menit lagi. Cek log di **Deployments → View Logs** sampai muncul pesan `Hermes bootstrap done` atau buka chat bot kamu.

---

## 🧠 Otak LLM Gratis: 9Router (default)

Bot ini default-nya pakai **[9Router](https://github.com/decolua/9router)** — router AI gratis yang menyambungkan Hermes ke **Claude / GPT / Gemini / Kimi / Qwen & 100+ model lain** lewat provider gratis & langgananmu. Hermes tidak butuh `OPENROUTER_API_KEY` sama sekali di mode ini.

**Cara kerja di Railway:** 9Router jalan sebagai **container terpisah** dalam project yang sama. Hermes memanggilnya lewat **private networking** Railway: `http://nine-router.railway.internal:20128/v1` — gratis & tidak terpapar ke internet. Untuk **login dashboard 9Router & hubungkan provider**, kamu buka **URL publik service 9Router** dari **browser PC kamu** (bukan dari dalam VPS). Untuk login pertama kali & ubah password, dashboard 9Router juga bisa dibuka dari **desktop VPS**.

### Setup 9Router (sekali saja, ± 5 menit)

> Sebelum memulai: pastikan **kedua service** sudah ter-deploy & status **Active** di Railway.

1. **Buka dashboard 9Router dari PC kamu:**
   - Buka **URL publik service 9Router** dari Railway → halaman login 9Router langsung tampil.
   - (Alternatif dari desktop VPS: buka noVNC → Web Browser → `http://localhost:20128`).

2. **Login:** masukkan password awal `123456` → **Login**.

3. **Ubah password (penting):** ke **Settings → Password** → ganti `123456` dengan password kuat.

4. **Hubungkan provider:** ke **Providers → Connect** → pilih salah satu:
   - **Gratis tanpa kartu:** **Kiro AI** (Claude 4.5 + GLM-5 + MiniMax), **OpenCode Free**, **Vertex AI** ($300 free credits)
   - **Punya akun:** **b.ai** / **iFlow** / provider lain yang sudah kamu miliki

5. **Buat & salin API key:** ke **Settings → API Keys → Create** → copy API key baru (format `9r_...`).

6. **Isi variabel di Railway:** kembali ke Railway → service `hermes-free-vps` → tab **Variables**:
   ```
   HERMES_NINEROUTER_API_KEY = 9r_xxxxxxxxxxxxxxxx
   ```
   Lalu klik **Deployments → Redeploy**.

7. **Tunggu & tes:**
   - Cek log service `hermes-free-vps`: cari tulisan `Hermes bootstrap done`.
   - Buka bot Telegram kamu → klik **Start** → mulai chat. 🎉

> Preferensi model saat boot (otomatis, via `/v1/models`): `kr/claude-sonnet-4.5` → `kr/deepseek-3.2` — yang pertama tersedia dipakai. Isi `HERMES_MODEL=kr/deepseek-3.2` kalau mau paksa DeepSeek. Daftar model ada di dashboard 9Router: `cc/...`, `kr/...`, `if/...`, `qw/...`, `glm/...` dll. Kalau satu model limit, 9Router otomatis fallback ke model berikutnya.
>
> Bot **bengong/diam**? Gateway Telegram sekarang dijalankan dengan **watchdog** (auto-restart kalau crash), dan 30 detik setelah start potongan log gateway di-`tail` ke **log deploy Railway** (Deployments → View Logs) — jadi penyebab bot diam bisa langsung dibaca dari situ tanpa buka noVNC. Hermes Agent + semua dependencies juga sudah **dibake ke image Docker** — kalau variabel berubah, klik **Redeploy** (build penuh), bukan Restart, supaya image baru terpakai.

### 🐬 Pakai DeepSeek (gratis via Kiro)

1. Pastikan provider **Kiro** masih **Connected** di dashboard 9Router.
2. Railway → service `hermes-free-vps` → **Variables** → set:
   ```
   HERMES_MODEL = kr/deepseek-3.2
   ```
3. **Redeploy** → tes chat bot.

> ⚠️ **Error "The model provider failed after retries"?** Itu artinya 9Router gagal mengeksekusi model yang diminta — biasanya karena: (1) model ID salah/typo (harus persis seperti di dashboard, dengan prefix `kr/`, `cc/`, dll), (2) **provider-nya belum di-Connect** di dashboard 9Router, (3) kuota provider habis, atau (4) OAuth token provider expired → dashboard 9Router → Providers → **Reconnect**. Detail error asli ada di log 9Router/dashboard, Hermes sengaja merangkumnya.
>
> DeepSeek **resmi** (API berbayar dari platform.deepseek.com): connect provider **DeepSeek** di dashboard 9Router dulu, lalu cek nama model persisnya lewat dashboard (atau endpoint `/v1/models`) sebelum diisi ke `HERMES_MODEL`.
>
> Tes cepat dari terminal VPS (lihat model DeepSeek yang benar-benar tersedia):
> ```bash
> source ~/.hermes/.env
> curl -s http://nine-router.railway.internal:20128/v1/models \
>   -H "Authorization: Bearer $OPENAI_API_KEY" | tr ',' '\n' | grep -i deepseek
> ```

> ⚠️ Jangan hapus service `nine-router` di Railway. Kalau dashboard belum login atau tidak ada provider aktif, bot Telegram akan diam — login dulu lewat URL publik 9Router dari PC kamu.

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
> 1. Cek log Railway (`Deployments → View Logs` pada service `hermes-free-vps`) — cari `Hermes bootstrap done` (sukses) atau pesan `[!]`.
> 2. Kalau muncul `HERMES_NINEROUTER_API_KEY is not set`, ikuti langkah **Setup 9Router** di atas dulu (login dashboard dari URL publik 9Router, connect provider, buat API key, isi variabel).
> 3. Pastikan service `nine-router` sudah **Active** di Railway.
> 4. Pastikan dashboard 9Router sudah login & ada provider aktif (buka URL publik 9Router dari PC kamu).
> 5. Pastikan tombol **Start** sudah ditekan di bot Telegram.

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
- Bot saat ini terbuka untuk semua pengguna (`TELEGRAM_ALLOW_ALL_USERS=true` di `~/.hermes/.env`). Kalau mau dibatasi ke ID Telegram tertentu saja, ganti flag itu menjadi `TELEGRAM_ALLOWED_USERS=<id1>,<id2>` di blok penulisan `.env` pada `hermes_setup.sh`.
- Jangan commit token bot / API key ke GitHub. Untuk mode 9Router, jangan share `HERMES_NINEROUTER_API_KEY` atau `INITIAL_PASSWORD` dashboard-nya.
- Ganti password 9Router setelah login pertama dari dashboard.

---

## 🧾 Kredit

- Repo VPS asli: [Lyvelia/free-vps-railway](https://github.com/Lyvelia/free-vps-railway)
- Hermes Agent: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) · MIT License
- AI Router: [decolua/9router](https://github.com/decolua/9router) · MIT License
- Dokumentasi Hermes: <https://hermes-agent.nousresearch.com/docs/>
- Dokumentasi 9Router: <https://9router.github.io>
