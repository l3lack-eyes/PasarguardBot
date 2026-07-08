"""Centralized reseller activity logging to the configured log channel."""

from __future__ import annotations

from typing import TYPE_CHECKING

from app.db.crud.panels import PanelsManager
from app.db.crud.reseller_plans import ResellerPlanManager
from app.logger import LogType
from app.services.billing.reseller_pricing import pricing_mode_label
from app.telegram.shared.utils.logging import send_log_message
from app.utils.formatting.dates import timestamp_to_persian_expiry
from app.utils.formatting.traffic import format_size

if TYPE_CHECKING:
    from app.db.models.reseller_accounts import ResellerAccount


async def _account_context_lines(account: ResellerAccount) -> list[str]:
    panel = await PanelsManager().get_panel_by_code(code=account.panel_code)
    panel_name = panel.name if panel else "—"
    plan = await ResellerPlanManager().get_plan(account.plan_id) if account.plan_id else None

    lines = [
        f"👤 <b>کاربر:</b> <code>{account.telegram_id}</code>",
        f"🎫 <b>کد نمایندگی:</b> <code>{account.code}</code>",
        f"🏢 <b>یوزر ادمین:</b> <code>{account.username}</code>",
        f"📛 <b>پنل:</b> {panel_name} (<code>{account.panel_code}</code>)",
        f"📋 <b>نوع پلن:</b> {pricing_mode_label(account.pricing_mode)}",
        f"📊 <b>وضعیت:</b> <code>{account.status}</code>",
    ]
    if plan:
        lines.append(f"📦 <b>پلن:</b> #{plan.id}")
    if account.purchased_volume:
        lines.append(f"📦 <b>حجم خرید:</b> {account.purchased_volume:g}")
    if account.data_limit:
        lines.append(f"📥 <b>سقف ترافیک:</b> {format_size(account.data_limit)}")
    if account.max_users:
        lines.append(f"👥 <b>سقف یوزر:</b> {account.max_users}")
    if account.expiration_time:
        lines.append(f"⏰ <b>انقضا:</b> {timestamp_to_persian_expiry(account.expiration_time)}")
    return lines


async def send_reseller_log(
    title: str,
    *,
    account: ResellerAccount | None = None,
    actor_id: int | None = None,
    actor_role: str | None = None,
    extra_lines: list[str] | None = None,
) -> None:
    parts = [f"<b>{title}</b>", ""]
    if actor_id is not None:
        role = actor_role or "کاربر"
        parts.append(f"👮 <b>انجام‌دهنده:</b> <code>{actor_id}</code> ({role})")
        parts.append("")
    if account is not None:
        parts.extend(await _account_context_lines(account))
        parts.append("")
    if extra_lines:
        parts.extend(line for line in extra_lines if line)

    message = "\n".join(parts).strip()
    await send_log_message(LogType.RESELLER, message=message, parse_mode="html")
