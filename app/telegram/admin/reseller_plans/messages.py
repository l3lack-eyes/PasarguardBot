"""Message handlers for admin reseller plans."""

import contextlib

from telethon import Button, events
from telethon.tl.custom import Message

from app import Kenzo
from app.db.crud.reseller_plans import ResellerPlanManager
from app.telegram.admin.reseller_plans import states
from app.telegram.admin.reseller_plans.callbacks import _finalize_new_plan, is_number
from app.telegram.admin.reseller_plans.service import (
    format_reseller_plan_detail,
    plan_manage_buttons,
    reseller_plan_display_buttons,
    reseller_plan_display_config_text,
)
from app.telegram.keyboards.common import extract_custom_emoji_document_id
from app.telegram.state import get_data, get_step, set_data, set_step
from config import ADMIN_ID


async def _show_plan_after_edit(event: Message, plan_id: int) -> None:
    plan = await ResellerPlanManager().get_plan(plan_id)
    if not plan:
        await event.respond("پلن یافت نشد.")
        return
    await Kenzo.send_message(
        event.sender_id,
        await format_reseller_plan_detail(plan),
        buttons=plan_manage_buttons(plan_id, plan.panel_code),
        parse_mode="markdown",
    )


async def message_handler_reseller_plans(event: Message):
    if not event.is_private or event.sender_id not in ADMIN_ID:
        return
    msg = (event.message.text or "").strip()
    user_id = event.sender_id

    if msg == states.RESELLER_PLAN_MENU_MESSAGE:
        buttons = [
            [Button.inline("➕ ساخت پلن نمایندگی", data="ResellerPlanAddPanel")],
            [Button.inline("📋 مدیریت پلن‌ها", data="ResellerPlanManagePanel")],
            [Button.inline("❌ بستن", data="ResellerPlanCancel")],
        ]
        await Kenzo.send_message(user_id, "منوی پلن‌های نمایندگی:", buttons=buttons)
        return

    step = await get_step(user_id)

    if step == "reseller_plan_add_price" and is_number(msg):
        await set_data(user_id, "reseller_plan_price", msg.replace(",", ""))
        await set_step(user_id, "reseller_plan_add_data_limit")
        await event.respond("سقف ترافیک (گیگ — 0 برای نامحدود):")
        return

    if step == "reseller_plan_add_unit_price" and is_number(msg):
        await set_data(user_id, "reseller_plan_unit_price", msg.replace(",", ""))
        mode = await get_data(user_id, "reseller_plan_mode")
        if mode in ("per_gb", "per_tb"):
            await set_step(user_id, "reseller_plan_add_min_volume")
            await event.respond("حداقل حجم (گیگ/ترابایت بسته به پلن):")
            return
        if mode == "usage":
            await set_data(user_id, "reseller_plan_price", "0")
        elif mode == "hourly":
            await set_data(user_id, "reseller_plan_price", msg.replace(",", ""))
        await set_step(user_id, "reseller_plan_add_data_limit")
        await event.respond("سقف ترافیک کل نماینده (گیگ — 0 نامحدود):")
        return

    if step == "reseller_plan_add_min_volume" and is_number(msg):
        await set_data(user_id, "reseller_plan_min_volume", msg.replace(",", ""))
        await set_step(user_id, "reseller_plan_add_max_volume")
        await event.respond("حداکثر حجم:")
        return

    if step == "reseller_plan_add_max_volume" and is_number(msg):
        await set_data(user_id, "reseller_plan_max_volume", msg.replace(",", ""))
        await set_step(user_id, "reseller_plan_add_data_limit")
        await event.respond("سقف ترافیک کل نماینده (گیگ — 0 نامحدود):")
        return

    if step == "reseller_plan_add_data_limit" and is_number(msg):
        await set_data(user_id, "reseller_plan_data_limit", msg.replace(",", ""))
        await set_step(user_id, "reseller_plan_add_max_users")
        await event.respond("سقف تعداد یوزر (0 نامحدود):")
        return

    if step == "reseller_plan_add_max_users" and is_number(msg):
        await set_data(user_id, "reseller_plan_max_users", msg.replace(",", ""))
        await set_step(user_id, "reseller_plan_add_duration")
        await event.respond("مدت اعتبار (روز — 0 نامحدود):")
        return

    if step == "reseller_plan_add_duration" and is_number(msg):
        await set_data(user_id, "reseller_plan_duration", msg.replace(",", ""))
        with contextlib.suppress(Exception):
            await event.delete()
        await _finalize_new_plan(event, user_id)
        return

    if step == "reseller_plan_edit_price" and is_number(msg):
        plan_id = await get_data(user_id, "reseller_edit_plan_id")
        plan = await ResellerPlanManager().get_plan(plan_id)
        if not plan:
            await event.respond("پلن یافت نشد.")
            return
        value = float(msg.replace(",", ""))
        if plan.pricing_mode == "fixed":
            await ResellerPlanManager().update_plan(plan_id, price=value)
        else:
            await ResellerPlanManager().update_plan(plan_id, unit_price=value)
        await set_step(user_id, "panel")
        with contextlib.suppress(Exception):
            await event.delete()
        await event.respond("✅ قیمت به‌روز شد.")
        await _show_plan_after_edit(event, int(plan_id))
        return

    if step == "reseller_plan_edit_btn_text":
        plan_id = int(await get_data(user_id, "reseller_edit_plan_id"))
        if msg.lower() == "/skip":
            await ResellerPlanManager().update_plan(plan_id, display_button_text=None)
        else:
            await ResellerPlanManager().update_plan(plan_id, display_button_text=msg)
        await set_step(user_id, "panel")
        with contextlib.suppress(Exception):
            await event.delete()
        plan = await ResellerPlanManager().get_plan(plan_id)
        if plan:
            await Kenzo.send_message(
                user_id,
                reseller_plan_display_config_text(plan),
                buttons=reseller_plan_display_buttons(plan_id, plan.panel_code),
                parse_mode="markdown",
            )
        return

    if step == "reseller_plan_edit_btn_icon":
        plan_id = int(await get_data(user_id, "reseller_edit_plan_id"))
        icon_id = extract_custom_emoji_document_id(event.message)
        if icon_id is None and msg.lstrip("-").isdigit():
            icon_id = int(msg)
        if icon_id is None:
            await event.respond("ایموجی پریمیوم یا شناسه عددی معتبر ارسال کنید.")
            return
        await ResellerPlanManager().update_plan(plan_id, button_icon=icon_id)
        await set_step(user_id, "panel")
        with contextlib.suppress(Exception):
            await event.delete()
        plan = await ResellerPlanManager().get_plan(plan_id)
        if plan:
            await Kenzo.send_message(
                user_id,
                reseller_plan_display_config_text(plan),
                buttons=reseller_plan_display_buttons(plan_id, plan.panel_code),
                parse_mode="markdown",
            )
        return


async def _filter(event: Message) -> bool:
    if event.sender_id not in ADMIN_ID or not event.is_private:
        return False
    msg = (event.message.text or "").strip()
    if msg == states.RESELLER_PLAN_MENU_MESSAGE:
        return True
    step = (await get_step(event.sender_id)) or ""
    if step == "reseller_plan_edit_btn_icon":
        return bool(msg) or bool(event.message.media)
    return step in states.ADMIN_INPUT_STEPS and bool(msg)


def register(client):
    client.add_event_handler(
        message_handler_reseller_plans,
        events.NewMessage(incoming=True, from_users=ADMIN_ID, func=_filter),
    )
