"""Top customers stats builder with tabbed views."""

import asyncio
from datetime import datetime

from app import CustomMarkdown
from app.db.crud.services import ServiceCRUD
from app.db.crud.transactions import TransactionCRUD
from app.utils.text.markdown import bold, code

tx_crud = TransactionCRUD()
service_crud = ServiceCRUD()

_MEDALS = {1: "🥇", 2: "🥈", 3: "🥉"}
_DIVIDER = "─────────────────"


def _fmt_ts(ts: int) -> str:
    try:
        return datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d %H:%M")
    except ValueError, OSError:
        return str(ts)


def _rank_line(rank: int, uid: int | None, detail: str) -> str:
    prefix = _MEDALS.get(rank, f"{rank}.")
    uid_str = code(str(uid)) if uid is not None else code("?")
    return f"  {prefix} {uid_str} — {detail}"


def _section(emoji: str, title: str) -> list[str]:
    return ["", f"{emoji} {bold(title)}"]


async def build_top_customers_message(view: str = "today") -> tuple[str, list]:
    """Build top customers text. Views: today, spend, recharge, config."""
    now = datetime.utcnow()
    today_start = datetime(now.year, now.month, now.day)
    today_ts = int(today_start.timestamp())

    if view == "spend":
        top = await tx_crud.get_top_customers_by_spend(10)
        lines = [f"🏆 {bold('برترین مشتریان — مبلغ خرید کل')}", code(_DIVIDER)]
        if not top:
            lines.append("  • داده‌ای موجود نیست")
        else:
            for i, (uid, total, cnt) in enumerate(top, 1):
                lines.append(_rank_line(i, uid, f"{code(f'{total:,}')} تومان · {cnt} شارژ"))

    elif view == "recharge":
        top = await tx_crud.get_top_customers_by_tx_count(10)
        lines = [f"🏆 {bold('برترین مشتریان — تعداد شارژ')}", code(_DIVIDER)]
        if not top:
            lines.append("  • داده‌ای موجود نیست")
        else:
            for i, (uid, cnt, total) in enumerate(top, 1):
                lines.append(_rank_line(i, uid, f"{cnt} شارژ · {code(f'{total:,}')} تومان"))

    elif view == "config":
        top = await service_crud.get_top_customers_by_config_count(10)
        lines = [f"🏆 {bold('برترین مشتریان — تعداد کانفیگ')}", code(_DIVIDER)]
        if not top:
            lines.append("  • داده‌ای موجود نیست")
        else:
            for i, (uid, cnt) in enumerate(top, 1):
                lines.append(_rank_line(i, uid, f"{cnt} کانفیگ"))

    else:
        (
            top_spenders,
            top_recharge,
            config_stats,
            most_today,
            oldest,
            newest,
        ) = await asyncio.gather(
            tx_crud.get_top_spenders_today(today_ts, 5),
            tx_crud.get_top_recharge_today(today_ts, 5),
            service_crud.get_today_config_stats(today_ts, 5),
            tx_crud.get_most_spender_today(today_ts),
            tx_crud.get_oldest_customer(),
            tx_crud.get_newest_customer(),
        )

        lines = [f"🏆 {bold('برترین‌های امروز')}", code(_DIVIDER)]

        lines.extend(_section("👑", "بیشترین خرید امروز"))
        if most_today:
            uid, amount = most_today
            lines.append(f"  • {code(str(uid))} → {code(f'{amount:,}')} تومان")
        else:
            lines.append("  • هنوز خریدی ثبت نشده")

        lines.extend(_section("💰", "برترین خریداران (مبلغ)"))
        if top_spenders:
            for i, (uid, total, cnt) in enumerate(top_spenders, 1):
                lines.append(_rank_line(i, uid, f"{code(f'{total:,}')} تومان · {cnt} تراکنش"))
        else:
            lines.append("  • —")

        lines.extend(_section("🔢", "بیشترین شارژ (تعداد)"))
        if top_recharge:
            for i, (uid, cnt, total) in enumerate(top_recharge, 1):
                lines.append(_rank_line(i, uid, f"{cnt} شارژ · {code(f'{total:,}')} تومان"))
        else:
            lines.append("  • —")

        lines.extend(_section("📦", f"خرید کانفیگ — {config_stats['total_today']:,} عدد"))
        if config_stats["top_buyers"]:
            for i, (uid, cnt) in enumerate(config_stats["top_buyers"], 1):
                lines.append(_rank_line(i, uid, f"{cnt} کانفیگ"))
        else:
            lines.append("  • امروز کانفیگی فروخته نشده")

        lines.extend(_section("📌", "سوابق"))
        if oldest:
            uid, ts = oldest
            lines.append(f"  • قدیمی‌ترین: {code(str(uid))} · {code(_fmt_ts(ts))}")
        else:
            lines.append("  • قدیمی‌ترین: —")
        if newest:
            uid, ts = newest
            lines.append(f"  • جدیدترین: {code(str(uid))} · {code(_fmt_ts(ts))}")
        else:
            lines.append("  • جدیدترین: —")

    text = "\n".join(lines)
    msg, entities = CustomMarkdown.parse(text)
    return msg, entities
