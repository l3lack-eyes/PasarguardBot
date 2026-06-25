# PasarguardBot

ربات تلگرام Pasarguard — نصب Docker با MariaDB و Redis.

## نصب سریع (سرور لینوکس)

```bash
curl -fsSL https://raw.githubusercontent.com/AmirKenzo/PasarguardBot/main/scripts/pasarguardbot.sh -o /tmp/pasarguardbot.sh
chmod +x /tmp/pasarguardbot.sh
sudo /tmp/pasarguardbot.sh
```

یا بعد از نصب:

```bash
pasarguardbot
```

## مسیرها

| مسیر | توضیح |
|------|--------|
| `/opt/pasarguardbot` | فایل `.env`، لاگ‌ها، session و docker-compose |
| `/var/lib/pasarguardbot` | سورس کلون‌شده از GitHub |

## منوی مدیریت

| گزینه | عملکرد |
|-------|--------|
| 1 | نصب — کلون، ساخت image، راه‌اندازی |
| 2 | حذف — کانتینر / volume / فایل‌ها |
| 3 | بروزرسانی — git pull + rebuild |
| 4 | لاگ‌ها |
| 5 | ویرایش `.env` |
| 6 | ریستارت کامل |
| 7 | وضعیت سرویس‌ها |

## پیش‌نیازها

- Linux (Ubuntu / Debian / CentOS / Rocky)
- root یا sudo
- Docker و Docker Compose (در صورت نبود، نصب خودکار می‌شود)

## پورت‌های پیش‌فرض

| سرویس | پورت | دسترسی |
|--------|------|--------|
| FastAPI | 6160 | public |
| phpMyAdmin | 6163 | public |
| Redis | 6161 | localhost only |
| MariaDB | 6162 | localhost only |

## توسعه محلی

```bash
cp .env.example .env
# ویرایش .env
docker compose up -d --build
```

## لایسنس

AGPL-3.0
