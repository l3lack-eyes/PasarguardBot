"""Text templates for admin backup."""

from app.telegram.admin.backup import states

BACKUP_MENU_TRIGGER = states.BACKUP_MENU_TRIGGER

NUMERIC_ONLY = "لطفاً فقط عدد صحیح ارسال کنید (مثال: 1 یا 24). عدد 0 بکاپ خودکار را خاموش می‌کند."
INTERVAL_SAVED_TEMPLATE = "✅ فاصله بکاپ خودکار روی هر `{hours}` ساعت تنظیم شد."
INTERVAL_DISABLED = "✅ بکاپ خودکار خاموش شد."
WORKING = "⏳ در حال تهیه بکاپ و ارسال به کانال…"


def menu_text(interval_hours: int, channel_configured: bool) -> str:
    interval_line = "⏸ بکاپ خودکار: خاموش" if interval_hours <= 0 else f"⏱ فاصله خودکار: هر `{interval_hours}` ساعت"
    channel_line = "✅ کانال بکاپ: تنظیم شده" if channel_configured else "❌ کانال بکاپ: تنظیم نشده (از مدیریت لاگ‌ها)"
    return (
        "🗄 **بکاپ ربات**\n\n"
        f"{interval_line}\n"
        f"{channel_line}\n\n"
        "محتوای بکاپ: `database.sql` + `.env`\n"
        "فایل به کانال لاگ «🗄 بکاپ ربات» ارسال می‌شود."
    )
