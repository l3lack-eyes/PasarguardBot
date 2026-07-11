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
## نصب

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AmirKenzo/PasarguardBot/main/scripts/pasarguardbot.sh)
```

بعد از نصب: `pasarguardbot`

---

## پیکربندی

| متغیر | توضیح |
|-------|--------|
| `API_ID` / `API_HASH` | اختیاری — اگر خالی بماند، مقادیر پیش‌فرض ست می‌شود |
| `BOT_TOKEN` | [@BotFather](https://t.me/BotFather) |
| `ADMIN_ID` | آیدی عددی ادمین‌ها (با کاما جدا کنید) |
| `SQLALCHEMY_DATABASE_URL` | در نصب Docker به‌صورت خودکار ست می‌شود |
| `CRYPTO_KEY` | کلید رمزنگاری |
| `REDIS_URL` | در نصب Docker به‌صورت خودکار ست می‌شود |
| `FASTAPI_PORT` | پورت API (پیش‌فرض `6160`) |
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
| 3 | بروزرسانی ربات (تگ release) |
| 4 | لاگ‌ها |
| 5 | ویرایش `.env` |
| 6 | ریستارت |
| 7 | وضعیت سرویس‌ها |
| 8 | نمایش webhook و URLها |
| 9 | آپدیت اسکریپت مدیریت |

---

## لایسنس

[GNU AGPL-3.0](LICENSE)
