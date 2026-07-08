"""Home reply keyboard builders."""

from telethon import Button
from telethon.tl.types import KeyboardButtonRow, ReplyKeyboardMarkup

from app.db.crud.keyboards import KeyboardButtonCRUD
from app.db.crud.settings import SettingsManager
from app.db.crud.user import UserCRUD
from config import ADMIN_ID, DISABLE_UPTIME_BUTTONS, LINK_UPTIME_BUTTONS

from .common import _get_keyboard_button_config, styled_reply_button, styled_simple_webview_button

bhome = [
    [Button.text("🔑 سرویس های من", resize=True), Button.text("🛍 خرید سرویس")],
    [Button.text("🙍 پروفایل من"), Button.text("💰 افزایش موجودی")],
    [Button.text("☎️ پشتیبانی"), Button.text("📚 راهنما")],
]


async def bhome_buttons(user_id, lang):
    keyboard_crud = KeyboardButtonCRUD()

    menu_my_services, menu_my_services_style = await _get_keyboard_button_config(
        keyboard_crud,
        "bt.menu_my_services",
        "🔑 سرویس های من",
        default_style="primary",
        default_icon=5895443668663275064,
    )
    menu_get_trial, menu_get_trial_style = await _get_keyboard_button_config(
        keyboard_crud, "bt.menu_get_trial", "🎁 دریافت تست"
    )
    menu_buy_service, menu_buy_service_style = await _get_keyboard_button_config(
        keyboard_crud,
        "bt.menu_buy_service",
        "🛍 خرید سرویس",
        default_style="success",
        default_icon=5373052667671093676,
    )

    menu_profile, menu_profile_style = await _get_keyboard_button_config(
        keyboard_crud, "bt.menu_profile", "🙍 پروفایل من"
    )
    menu_add_balance, menu_add_balance_style = await _get_keyboard_button_config(
        keyboard_crud, "bt.menu_add_balance", "💰 افزایش موجودی"
    )

    menu_support, menu_support_style = await _get_keyboard_button_config(keyboard_crud, "bt.menu_support", "☎️ پشتیبانی")
    menu_uptime, menu_uptime_style = await _get_keyboard_button_config(
        keyboard_crud, "bt.menu_uptime", "🔋 وضعیت سرویس ها"
    )
    menu_help, menu_help_style = await _get_keyboard_button_config(keyboard_crud, "bt.menu_help", "📚 راهنما")

    menu_admin_panel, menu_admin_panel_style = await _get_keyboard_button_config(
        keyboard_crud, "bt.menu_admin_panel", "⚙️ پنل مدیریت"
    )
    menu_buy_reseller, menu_buy_reseller_style = await _get_keyboard_button_config(
        keyboard_crud,
        "bt.menu_buy_reseller",
        "🏢 خرید پنل نمایندگی",
        default_style="success",
    )
    menu_my_resellers, menu_my_resellers_style = await _get_keyboard_button_config(
        keyboard_crud,
        "bt.menu_my_resellers",
        "📋 نمایندگی‌های من",
        default_style="primary",
    )

    user_data = await UserCRUD().read_user(user_id=user_id)
    setting = await SettingsManager().get_settings()
    config_sale = bool(setting and setting.sale_mode)
    reseller_sale = bool(setting and setting.reseller_sale_mode)

    bhome: list[list] = []

    if user_data and user_data.tested == 0 and setting and setting.test_mode == 1 and setting.test_panel_id != 0:
        bhome.append([styled_reply_button(menu_get_trial, menu_get_trial_style)])

    shop_row = []
    if config_sale:
        shop_row.append(styled_reply_button(menu_my_services, menu_my_services_style))
        shop_row.append(styled_reply_button(menu_buy_service, menu_buy_service_style))
    if shop_row:
        bhome.append(shop_row)

    reseller_row = []
    if reseller_sale:
        reseller_row.append(styled_reply_button(menu_my_resellers, menu_my_resellers_style))
        reseller_row.append(styled_reply_button(menu_buy_reseller, menu_buy_reseller_style))
    if reseller_row:
        bhome.append(reseller_row)

    bhome.extend(
        [
            [
                styled_reply_button(menu_profile, menu_profile_style),
                styled_reply_button(menu_add_balance, menu_add_balance_style),
            ],
            [
                styled_reply_button(menu_support, menu_support_style),
                *(
                    []
                    if DISABLE_UPTIME_BUTTONS
                    else [styled_simple_webview_button(menu_uptime, LINK_UPTIME_BUTTONS, menu_uptime_style)]
                ),
                styled_reply_button(menu_help, menu_help_style),
            ],
        ]
    )

    if user_id in ADMIN_ID:
        bhome.append([styled_reply_button(menu_admin_panel, menu_admin_panel_style)])

    return ReplyKeyboardMarkup([KeyboardButtonRow(button) for button in bhome], resize=True)


alaki = ReplyKeyboardMarkup([KeyboardButtonRow([styled_simple_webview_button("salam", "https://x.c")])])
