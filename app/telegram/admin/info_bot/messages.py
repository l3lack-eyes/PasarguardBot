"""Message handlers for admin stats/info bot."""

from telethon import events
from telethon.tl.custom import Message

from app import CustomMarkdown
from app.telegram.admin.info_bot import keyboards, service
from config import ADMIN_ID


async def message_handler_infobot(event: Message):
    if not event.is_private:
        return
    payload = await service.main_payload(force=False)
    msg, entities = CustomMarkdown.parse(service.main_text(payload))
    await event.reply(msg, formatting_entities=entities, buttons=keyboards.main_menu_buttons())


def register(client):
    client.add_event_handler(
        message_handler_infobot,
        events.NewMessage(pattern=r"^👥 آمار گیری$", incoming=True, from_users=ADMIN_ID),
    )
