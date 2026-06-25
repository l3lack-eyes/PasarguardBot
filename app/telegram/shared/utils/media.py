"""Telegram media/caption size helpers."""

from __future__ import annotations

TELEGRAM_CAPTION_LIMIT = 1024
TELEGRAM_MESSAGE_LIMIT = 4096


def split_telegram_text(text: str, limit: int = TELEGRAM_MESSAGE_LIMIT) -> list[str]:
    if len(text) <= limit:
        return [text]

    chunks: list[str] = []
    current = ""
    for line in text.splitlines(keepends=True):
        if len(line) > limit:
            if current:
                chunks.append(current.rstrip())
                current = ""
            for index in range(0, len(line), limit):
                chunks.append(line[index : index + limit].rstrip())
            continue
        if len(current) + len(line) > limit:
            if current:
                chunks.append(current.rstrip())
            current = line
        else:
            current += line
    if current:
        chunks.append(current.rstrip())
    return chunks or [text[:limit]]


async def respond_with_photo_and_text(
    event,
    *,
    file,
    text: str,
    short_caption: str,
    buttons=None,
) -> None:
    """Send a photo; use short_caption when full text exceeds Telegram's caption limit."""
    kwargs: dict = {}
    if buttons is not None:
        kwargs["buttons"] = buttons

    if len(text) <= TELEGRAM_CAPTION_LIMIT:
        await event.respond(message=text, file=file, **kwargs)
        return

    await event.respond(message=short_caption, file=file, **kwargs)
    for chunk in split_telegram_text(text):
        await event.respond(chunk)
