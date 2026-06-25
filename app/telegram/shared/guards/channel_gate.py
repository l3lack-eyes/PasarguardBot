"""Mandatory channel membership checks shared by middleware and handlers."""

from __future__ import annotations

from telethon import Button, events

from app import Kenzo
from app.db.crud.channels import ChannelManager
from app.db.crud.user import UserCRUD, add_user
from app.logger import get_logger
from app.telegram.shared.utils.channels import check_user_channels
from app.utils.formatting.dates import Time_Date

logger = get_logger(__name__)

BOT_LANGUAGE = "fa"

# Deep-link params that must pass channel gate before shop/balance/trial handlers run.
RESERVED_START_PARAMS = frozenset({"buy", "free", "charge"})

CHANNEL_JOIN_MESSAGE = "برای استفاده از ربات باید در کانال‌های زیر عضو شوید:\n<blockquote expandable>{date}</blockquote>"

try:
    from telethon.tl.types import MessageActionBotStart
except ImportError:  # pragma: no cover
    MessageActionBotStart = None  # type: ignore[misc, assignment]


def get_message_text(event) -> str:
    message = getattr(event, "message", None)
    if message is None:
        return ""
    return (getattr(message, "text", None) or getattr(message, "message", None) or "").strip()


def parse_start_param(msg: str) -> str | None:
    """Extract /start payload from message text, ignoring optional @botname suffix."""
    text = (msg or "").strip()
    if not text.lower().startswith("/start"):
        return None
    parts = text.split(maxsplit=1)
    if len(parts) < 2:
        return None
    return parts[1].strip() or None


def extract_start_param(event) -> str | None:
    """Read deep-link payload from /start text or MessageActionBotStart."""
    param = parse_start_param(get_message_text(event))
    if param:
        return param

    message = getattr(event, "message", None)
    action = getattr(message, "action", None) if message is not None else None
    if MessageActionBotStart is not None and isinstance(action, MessageActionBotStart):
        start_param = getattr(action, "start_param", None)
        if start_param:
            return str(start_param).strip() or None
    return None


def is_reserved_start_param(param: str | None) -> bool:
    if not param:
        return False
    return param.strip().lower() in RESERVED_START_PARAMS


def is_reserved_start_deeplink(event) -> bool:
    return is_reserved_start_param(extract_start_param(event))


def build_channel_join_buttons(not_joined_channels: list) -> list:
    buttons = [[Button.url(channel["title"], url=channel["link"])] for channel in not_joined_channels]
    buttons.append([Button.inline("✅ عضو شدم", data="Check_join")])
    return buttons


async def get_not_joined_channels(user_id: int) -> list:
    channels = await ChannelManager().get_all_channels()
    if not channels:
        return []
    return await check_user_channels(user_id, Kenzo, channels)


async def ensure_channel_membership(event, *, is_callback: bool = False) -> bool:
    """Return True when the user may proceed; otherwise show join prompt and return False."""
    user_id = event.sender_id
    not_joined_channels = await get_not_joined_channels(user_id)
    if not not_joined_channels:
        return True

    info = await UserCRUD().read_user(user_id)
    lang = info.language if info and info.language else BOT_LANGUAGE
    await add_user(
        user_id=user_id,
        step="start",
        time_s=Time_Date()["stamp"],
        language=lang,
    )

    text = CHANNEL_JOIN_MESSAGE.format(date=Time_Date()["mf"])
    buttons = build_channel_join_buttons(not_joined_channels)

    if is_callback:
        try:
            await event.answer("⚠️ ابتدا در کانال‌های اجباری عضو شوید.", alert=True)
        except Exception as exc:
            logger.debug("Could not answer blocked callback for user %s: %s", user_id, exc)
        await Kenzo.send_message(user_id, text, buttons=buttons, parse_mode="html")
    elif isinstance(event, events.CallbackQuery.Event):
        await event.respond(text, buttons=buttons, parse_mode="html")
    else:
        await event.reply(text, buttons=buttons, parse_mode="html")

    return False
