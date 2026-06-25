"""Serialize/deserialize inline keyboards for broadcast payload_json storage."""

from __future__ import annotations

import base64

from telethon import Button
from telethon.tl.types import (
    KeyboardButtonCallback,
    KeyboardButtonCopy,
    KeyboardButtonSimpleWebView,
    KeyboardButtonStyle,
    KeyboardButtonSwitchInline,
    KeyboardButtonUrl,
    KeyboardButtonWebView,
    ReplyInlineMarkup,
)

_STYLE_FIELDS = ("bg_primary", "bg_danger", "bg_success", "icon")


def _encode_bytes(value: bytes | str) -> str:
    if isinstance(value, bytes):
        return base64.b64encode(value).decode("ascii")
    return str(value)


def _decode_bytes(value: str) -> bytes:
    try:
        return base64.b64decode(value.encode("ascii"))
    except Exception:
        return value.encode("utf-8")


def _serialize_style(style) -> dict | None:
    if style is None:
        return None
    if isinstance(style, dict):
        return {key: style[key] for key in _STYLE_FIELDS if style.get(key)}
    if isinstance(style, KeyboardButtonStyle):
        result = {}
        for field in _STYLE_FIELDS:
            value = getattr(style, field, None)
            if value:
                result[field] = int(value) if field == "icon" else bool(value)
        return result or None
    return None


def _deserialize_style(style) -> KeyboardButtonStyle | None:
    if style is None:
        return None
    if isinstance(style, KeyboardButtonStyle):
        return style
    if isinstance(style, dict):
        kwargs = {}
        for field in _STYLE_FIELDS:
            value = style.get(field)
            if value:
                kwargs[field] = int(value) if field == "icon" else bool(value)
        return KeyboardButtonStyle(**kwargs) if kwargs else None
    return None


def _serialize_button_item(button) -> dict | None:
    item: dict = {"text": button.text}
    style = _serialize_style(getattr(button, "style", None))
    if style:
        item["style"] = style

    if isinstance(button, KeyboardButtonUrl):
        item["type"] = "url"
        item["url"] = button.url
    elif isinstance(button, KeyboardButtonCallback):
        item["type"] = "callback"
        item["data"] = _encode_bytes(button.data)
    elif isinstance(button, KeyboardButtonSwitchInline):
        item["type"] = "switch_inline"
        item["query"] = _encode_bytes(button.query)
        item["same_peer"] = bool(button.same_peer)
    elif isinstance(button, KeyboardButtonWebView):
        item["type"] = "web_view"
        item["url"] = button.url
    elif isinstance(button, KeyboardButtonSimpleWebView):
        item["type"] = "simple_web_view"
        item["url"] = button.url
    elif isinstance(button, KeyboardButtonCopy):
        item["type"] = "copy"
        item["copy_text"] = button.copy_text
    else:
        return None
    return item


def _deserialize_button_item(item: dict):
    text = item.get("text", "")
    style_obj = _deserialize_style(item.get("style"))
    btn_type = item.get("type")

    if btn_type == "url":
        url = item.get("url") or item.get("value", "")
        if style_obj:
            try:
                return KeyboardButtonUrl(text=text, url=url, style=style_obj)
            except TypeError:
                pass
        return Button.url(text, url)

    if btn_type == "callback":
        raw_data = _decode_bytes(item.get("data") or item.get("value", ""))
        if style_obj:
            try:
                return KeyboardButtonCallback(text=text, data=raw_data, style=style_obj)
            except TypeError:
                pass
        return Button.inline(text, raw_data)

    if btn_type == "switch_inline":
        query = _decode_bytes(item.get("query") or item.get("value", ""))
        return KeyboardButtonSwitchInline(
            text=text,
            query=query,
            same_peer=bool(item.get("same_peer", False)),
        )

    if btn_type == "web_view":
        url = item.get("url", "")
        if style_obj:
            try:
                return KeyboardButtonWebView(text=text, url=url, style=style_obj)
            except TypeError:
                pass
        return KeyboardButtonWebView(text=text, url=url)

    if btn_type == "simple_web_view":
        url = item.get("url", "")
        if style_obj:
            try:
                return KeyboardButtonSimpleWebView(text=text, url=url, style=style_obj)
            except TypeError:
                pass
        return KeyboardButtonSimpleWebView(text=text, url=url)

    if btn_type == "copy":
        copy_text = item.get("copy_text") or item.get("value", "")
        if style_obj:
            try:
                return KeyboardButtonCopy(text=text, copy_text=copy_text, style=style_obj)
            except TypeError:
                pass
        return KeyboardButtonCopy(text=text, copy_text=copy_text)

    return None


def serialize_reply_markup(markup) -> list[list[dict]] | None:
    """Convert Telethon reply markup to JSON-serializable button rows."""
    if markup is None:
        return None
    if isinstance(markup, list):
        return sanitize_button_rows(markup)
    if not isinstance(markup, ReplyInlineMarkup):
        return None

    rows: list[list[dict]] = []
    for row in markup.rows:
        btn_row: list[dict] = []
        for button in row.buttons:
            item = _serialize_button_item(button)
            if item:
                btn_row.append(item)
        if btn_row:
            rows.append(btn_row)
    return rows or None


def sanitize_button_rows(rows) -> list[list[dict]] | None:
    """Normalize stored button rows and ensure JSON-safe style values."""
    if rows is None:
        return None
    if not isinstance(rows, list):
        return serialize_reply_markup(rows)

    fixed: list[list[dict]] = []
    for row in rows:
        if not isinstance(row, list):
            continue
        fixed_row: list[dict] = []
        for item in row:
            if not isinstance(item, dict):
                continue
            clean = dict(item)
            if "style" in clean:
                clean["style"] = _serialize_style(clean["style"])
            fixed_row.append(clean)
        if fixed_row:
            fixed.append(fixed_row)
    return fixed or None


def serialize_message_buttons(message) -> list[list[dict]] | None:
    """Extract inline buttons from a Telethon message."""
    markup = getattr(message, "reply_markup", None)
    return serialize_reply_markup(markup)


def deserialize_buttons(data) -> list | None:
    """Rebuild Telethon button rows from stored JSON payload."""
    if not data:
        return None
    if not isinstance(data, list):
        return data

    rows: list = []
    for row in sanitize_button_rows(data) or []:
        btn_row = []
        for item in row:
            button = _deserialize_button_item(item)
            if button is not None:
                btn_row.append(button)
        if btn_row:
            rows.append(btn_row)
    return rows or None


def sanitize_payload_json(payload: dict) -> dict:
    """Ensure payload_json only contains JSON-serializable values."""
    clean = dict(payload)
    if clean.get("buttons") is not None:
        clean["buttons"] = serialize_reply_markup(clean["buttons"]) or sanitize_button_rows(clean["buttons"])
    return clean
