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

### 2) Deploy ke Railway
1. Buka **<https://railway.app>** → login pakai **GitHub**.
2. Klik **New Project** → **Deploy from GitHub repo** → pilih hasil fork kamu.
3. Railway otomatis baca `railway.json` & `Dockerfile`. Tunggu **Build & Deploy** ± 3–7 menit sampai status **Active/Healthy**.
4. **Settings → Networking → Generate Domain** → dapat URL seperti `https://xxx.up.railway.app`.
5. **Settings → Region**: pilih **Singapore** biar koneksi dari Indonesia kencang.

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
| `OPENROUTER_API_KEY` | `sk-or-v1-...` | ✅ | API key LLM (OpenRouter) |
| `HERMES_MODEL` | `openrouter/openai/gpt-4o-mini` | opsional | Model bawaan Hermes |
| `HERMES_ALLOWED_USERS` | `123456789,987654321` | opsional | Whitelist ID Telegram (kosongkan = semua orang bisa chat bot) |
| `VNC_PASSWORD` | `rahasia123` | opsional | Password akses desktop VPS |

Cara dapat **ID Telegram**: chat ke **[@userinfobot](https://t.me/userinfobot)** → lihat angka `Id`.

Setelah menambah variabel → tab **Deployments** → klik **Redeploy** agar variabel baru dipakai.

> Saat pertama kali jalan, install Hermes butuh ± 2–5 menit lagi. Cek log di **Deployments → View Logs** sampai muncul pesan `Hermes bootstrap done` atau buka chat bot kamu.

---

## ✉️ Pakai Hermes dari Telegram

- Buka bot kamu di Telegram → **Start** → langsung chat.
- Contoh perintah:
  - `/help` — daftar perintah
  - `/new` — mulai sesi baru
  - `/model` — ganti model (kalau versi mendukung)
  - Kirim **voice note** → otomatis ditranskrip.
- Hermes punya **memori permanen** dan bisa **membuat skill sendiri** — makin sering dipakai makin pintar.

> Kalau bot tidak membalas: pastikan `TELEGRAM_BOT_TOKEN` benar, tombol **Start** sudah ditekan di bot, dan cek log `hermes_gateway.log`.

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
├── hermes_setup.sh       # Install Hermes & jalankan gateway Telegram (opsional)
├── railway.json          # Konfigurasi deploy Railway
├── docker-compose.yml    # Testing lokal
├── .github/workflows/keep_alive.yml  # Ping 24/7 via GitHub Actions
├── README.md             # Dokumen ini
└── .gitignore
```

---

## 🛠️ Testing Lokal (Opsional)

Sudah install Docker? Jalankan dari folder ini:

```bash
docker compose up --build
```

Lalu buka `http://localhost:6080` di browser.

Untuk tes otomatis Hermes (kasih token dulu di variabel environment):
```bash
HERMES_AUTOSTART=true TELEGRAM_BOT_TOKEN=xxx OPENROUTER_API_KEY=yyy docker compose up --build
```

---

## 🔐 Keamanan

- `VPS_URL` dan `VPS_PASSWORD` hanya untuk kamu — jangan share.
- Set `HERMES_ALLOWED_USERS` supaya cuma ID Telegram tertentu yang bisa pakai bot.
- Jangan commit token bot / API key ke GitHub.

---

## 🧾 Kredit

- Repo VPS asli: [Lyvelia/free-vps-railway](https://github.com/Lyvelia/free-vps-railway)
- Hermes Agent: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) · MIT License
- Dokumentasi Hermes: <https://hermes-agent.nousresearch.com/docs/>
