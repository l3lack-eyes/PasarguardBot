# PasarguardBot

[![Python](https://img.shields.io/badge/Python-3.14-blue?logo=python&logoColor=white)](https://www.python.org/) 
[![License](https://img.shields.io/badge/License-AGPL--3.0-green)](LICENSE)  
[![Telethon](https://img.shields.io/badge/Telethon-1.44+-0088cc?logo=telegram)](https://github.com/LonamiWebs/Telethon)

---

## معرفی

ربات فروش وی پی ان مبتنی بر پنل [پاسارگارد پنل](https://github.com/PasarGuard/pasarguard) است. خرید، تمدید، شارژ کیف پول و پشتیبانی کاربران داخل تلگرام انجام می‌شود و ادمین از همان ربات پنل‌ها، پلن‌ها، کاربران، پرداخت‌ها و نمایندگان را مدیریت می‌کند.



---

## پیش‌نمایش


### کاربر

| منوی اصلی | خرید سرویس |
|:---:|:---:|
| ![منوی اصلی](https://ak6.ir/api/public/dl/67aRfm0d?inline=true) | ![خرید سرویس](https://ak6.ir/api/public/dl/tCu1TShF?inline=true) |

| مدیریت سرویس‌ها | افزایش موجودی |
|:---:|:---:|
| ![سرویس‌ها](https://ak6.ir/api/public/dl/RzyB703f?inline=true) | ![شارژ کیف پول](https://ak6.ir/api/public/dl/drSqBSmb?inline=true) |

---

## نصب سریع (لینوکس)

```bash
curl -fsSL https://raw.githubusercontent.com/AmirKenzo/PasarguardBot/main/scripts/pasarguardbot.sh -o /tmp/pasarguardbot.sh
chmod +x /tmp/pasarguardbot.sh
sudo /tmp/pasarguardbot.sh
```

بعد از نصب: `pasarguardbot`

| مسیر | توضیح |
|------|--------|
| `/opt/pasarguardbot` | `.env`، لاگ‌ها، session، docker-compose |
| `/var/lib/pasarguardbot` | سورس کلون‌شده |

---

## توسعه محلی

```bash
git clone https://github.com/AmirKenzo/PasarguardBot.git
cd PasarguardBot
cp .env.example .env
docker compose up -d --build
```

بدون Docker:

```bash
uv sync
cp .env.example .env
uv run alembic upgrade head
uv run main.py
```

---

## پیکربندی

| متغیر | توضیح |
|-------|--------|
| `API_ID` / `API_HASH` | [my.telegram.org](https://my.telegram.org/apps) |
| `BOT_TOKEN` | [@BotFather](https://t.me/BotFather) |
| `ADMIN_ID` | آیدی عددی ادمین‌ها |
| `SQLALCHEMY_DATABASE_URL` | MariaDB / MySQL |
| `CRYPTO_KEY` | کلید رمزنگاری |
| `REDIS_URL` | Redis |
| `FASTAPI_PORT` | پورت API (خالی = غیرفعال) |
| `WEBHOOK_SECRET` | سکرت وب‌هوک پنل |

جزئیات کامل: [`.env.example`](.env.example)

---

## پورت‌های پیش‌فرض

| سرویس | پورت | دسترسی |
|--------|------|--------|
| FastAPI | 6160 | Public |
| phpMyAdmin | 6163 | Public |
| Redis | 6161 | localhost |
| MariaDB | 6162 | localhost |

---

## Menu `pasarguardbot`

| # | عملکرد |
|---|--------|
| 1 | نصب |
| 2 | حذف |
| 3 | بروزرسانی |
| 4 | لاگ‌ها |
| 5 | ویرایش `.env` |
| 6 | ریستارت |
| 7 | وضعیت سرویس‌ها |

---

## لایسنس

[GNU AGPL-3.0](LICENSE)
