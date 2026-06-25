from __future__ import annotations

from datetime import datetime

from telethon import Button

from app.db.crud.cryptopayments import get_user_crypto_stats
from app.db.crud.services import ServiceCRUD
from app.db.crud.transactions import TransactionCRUD
from app.db.crud.user import UserCRUD, get_user_status
from app.telegram.state import get_step


async def build_user_step_admin_lines(user_id: int) -> str:
    """Format DB status, Redis flow step, and temp state keys for admin panels."""
    from app.telegram.state.store import get_all_user_state

    db_status = await get_user_status(user_id)
    flow_step = await get_step(user_id)

    lines = [
        f"📋 **مرحله جاری:** `{flow_step or '—'}`",
        f"🗄️ **وضعیت حساب:** `{db_status or '—'}`",
    ]

    state = await get_all_user_state(user_id)
    temp_keys = [key for key in state if key != "_current"]
    if temp_keys:
        preview = ", ".join(f"`{key}`" for key in temp_keys[:10])
        if len(temp_keys) > 10:
            preview += f" … (+{len(temp_keys) - 10})"
        lines.append(f"📦 **کلیدهای Redis:** {preview}")

    return "\n".join(lines) + "\n"


async def display_user_info_admin(event, user_id_to_check):
    """Render the admin user-info panel."""
    reduser = await UserCRUD().read_user(user_id=user_id_to_check)
    manual_stats = await TransactionCRUD().get_user_transaction_stats(user_id_to_check, "manual")
    auto_stats = await TransactionCRUD().get_user_transaction_stats(user_id_to_check, "auto")
    crypto_stats = await get_user_crypto_stats(user_id_to_check)
    total_purchases = manual_stats["count"] + auto_stats["count"] + crypto_stats["count"]
    total_amount_spent = manual_stats["total_amount"] + auto_stats["total_amount"] + crypto_stats["total_amount"]

    user_services = await ServiceCRUD().get_services_reverse(user_id_to_check)
    active_services = [service for service in user_services if service.enable]
    total_volume = sum(service.package_size or 0 for service in user_services)

    ref_user = None
    if reduser.ref:
        ref_user = await UserCRUD().read_user(reduser.ref)
    join_date = "نامشخص"
    if reduser.time_s:
        join_date = datetime.fromtimestamp(reduser.time_s).strftime("%Y/%m/%d %H:%M")

    total_volume_gb = total_volume / (1024**3) if total_volume else 0

    buttons = [[Button.inline("بازگشت", data=f"BackToUserManagement:{user_id_to_check}")]]

    if reduser.tested:
        reset_test_button = Button.inline(
            "🔄 ریست تست",
            f"ResetTest:{user_id_to_check}",
        )
        buttons.insert(1, [reset_test_button])

    transaction_details = ""
    if manual_stats["count"] > 0:
        transaction_details += (
            f"💳 کارت به کارت دستی: {manual_stats['count']} عدد - {manual_stats['total_amount']:,} تومان\n"
        )
    if auto_stats["count"] > 0:
        transaction_details += (
            f"💳 کارت به کارت معمولی: {auto_stats['count']} عدد - {auto_stats['total_amount']:,} تومان\n"
        )
    if crypto_stats["count"] > 0:
        transaction_details += (
            f"💰 تراکنش‌های ارزی: {crypto_stats['count']} عدد - {crypto_stats['total_amount']:,} تومان\n"
        )

    if not transaction_details:
        transaction_details = "هیچ تراکنش موفقی ثبت نشده\n"

    step_lines = await build_user_step_admin_lines(user_id_to_check)

    await event.edit(
        f"👤 **شناسه کاربر:** `{reduser.id}` | [پروفایل کاربر](tg://user?id={reduser.id})\n"
        f"{step_lines}"
        f"⏱️ **زمان عضویت:** `{join_date}`\n"
        f"🔢 **شماره تلفن:** {reduser.number or 'ثبت نشده'}\n"
        f"💰 **موجودی:** `{reduser.amount:,} تومان`\n"
        f"👥 **تعداد دعوت ها:** `{reduser.invite}`\n"
        f"📊 **آمار تراکنش‌ها:**\n{transaction_details}"
        f"🛒 **مجموع خرید موفق:** `{total_purchases} عدد`\n"
        f"💳 **مجموع مبلغ خرید شده:** `{total_amount_spent:,} تومان`\n\n"
        f"📦 **تعداد کل سرویس‌ها:** `{len(user_services)}`\n"
        f"✅ **سرویس‌های فعال:** `{len(active_services)}`\n"
        f"📊 **مجموع حجم سرویس‌ها:** `{total_volume_gb:.2f} گیگابایت`\n"
        f"👤 **ارجاع دهنده:** {f'`{ref_user.id}`' if ref_user else 'ندارد'}\n"
        f"🌐 **زبان:** `{'فارسی' if reduser.language == 'fa' else 'انگلیسی'}`\n"
        f"🧪 **کانفیگ تست:** `{'قبلا گرفته' if reduser.tested else 'هنوز تست رو نگرفته'}`",
        buttons=buttons,
    )
