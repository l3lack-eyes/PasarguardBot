"""Shared helpers for admin home panel."""

from app import Kenzo
from app.telegram.keyboards.admin import Panel_Admin_Buttons
from app.telegram.state import set_step

ADD_PANEL_STEPS = frozenset(
    {
        "addPanel_name",
        "AddPanel_url",
        "AddPanel_username",
        "AddPanel_password",
        "AddPanel_select_group",
    }
)


def _admin_home_message(user_id: int, username: str | None) -> str:
    user_label = username or "—"
    return f"**🌺به پنل مدیریت خوش آمدید.**\nایدی عددی شما: `{user_id}`\nنام کاربری شما: @{user_label}\n"


async def send_admin_home(user_id: int, username: str | None = None) -> None:
    await set_step(user_id=user_id, step="panel")
    await Kenzo.send_message(
        entity=user_id,
        message=_admin_home_message(user_id, username),
        buttons=Panel_Admin_Buttons,
    )
