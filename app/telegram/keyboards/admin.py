"""Admin reply/inline keyboard builders."""

from telethon import Button

from app.db.crud.user import UserCRUD

from .common import create_button, glass_inline_button, glass_text_button

Lock_Channels_Menu_Buttons = [
    [glass_text_button("افزودن کانال"), glass_text_button("حذف کانال")],
    [glass_text_button("لیست کانال‌ها")],
    [glass_text_button("🔙 بازگشت به پنل")],
]
# Lock Channels (🔐) Inline Menu (fully glassy)
Lock_Channels_Inline_Menu = [
    [
        glass_inline_button("➕ افزودن کانال", data="lock_add"),
        glass_inline_button("📋 لیست کانال‌ها", data="lock_list:1"),
    ],
    [glass_inline_button("🔙 بازگشت به پنل", data="back_to_panel")],
]


async def create_inline_manageuser(UserID):
    buttons = [
        [Button.inline("📂 لیست سرویس‌ها", f"MToUser_listSv:{UserID}")],
        [
            Button.inline("🔍 جستجوی کانفیگ", f"AdminSearchConfig:{UserID}"),
            Button.inline("🗑 حذف گروهی کانفیگ", f"BulkDeleteConfigs:{UserID}"),
        ],
        [Button.inline("رفع مسدودی", f"unbansup_{UserID}"), Button.inline("مسدود سازی", f"bansup_{UserID}")],
        [Button.inline("اطلاعات کاربر", f"UserInfo:{UserID}"), Button.inline("پیام به کاربر", f"sendm_{UserID}")],
    ]
    user = await UserCRUD().read_user(UserID)
    if not user or not user.number:
        buttons.append([Button.inline("📱 تایید شماره کاربر", f"confirm_phone_{UserID}")])

    buttons.append([Button.inline("ساخت کانفیگ برای کاربر", f"CreateConfigFor:{UserID}")])
    return buttons


def btn_cardtocard_settings(settings=None):
    auto_text = "✅ تایید خودکار روشن" if settings and settings.manual_auto_confirm else "❌ تایید خودکار خاموش"
    random_mode_text = (
        "✅ نمایش رندوم کارت روشن" if settings and settings.manual_card_random_mode else "❌ نمایش رندوم کارت خاموش"
    )
    return [
        [
            Button.inline(text="➕ افزودن کارت", data="add_manual_card"),
            Button.inline(text="🗑 حذف کارت", data="delete_manual_card"),
        ],
        [Button.inline(text="📋 انتخاب کارت فعال", data="select_active_card")],
        [Button.inline(text=random_mode_text, data="toggle_manual_card_random_mode")],
        [Button.inline(text=auto_text, data="toggle_manual_auto_confirm")],
        [Button.inline(text="📋 قوانین تایید خودکار", data="maar_rules_menu")],
        [
            Button.inline(text="💰 محدودیت کارت دستی", data="set_manual_limits"),
        ],
        [Button.inline(text="💰 محدودیت واریز ارزی", data="set_crypto_limits")],
        [Button.inline(text="🎁 تنظیمات بونوس", data="bonus_settings_menu")],
        [Button.inline(text="💼 مدیریت کیف پول‌ها", data="wallet_management")],
    ]


Panel_Admin_Buttons = [
    [create_button("💳 تنظیمات درگاه"), create_button("👥 آمار گیری")],
    [create_button("📚 منوی پنل ها"), create_button("⚙️ تنظیمات ربات")],
    [create_button("🎟 کدتخفیف"), create_button("🗞 ساخت پلن")],
    [create_button("👤 مدیریت کاربر"), create_button("📮 ارسال همگانی")],
    [create_button("📥 فوروارد همگانی")],
    [create_button("➖ کسر موجودی"), create_button("➕ افزودن موجودی")],
    [create_button("💰 شارژ گروهی"), create_button("🔄 ریست دریافت تست")],
    [create_button("📈 افزایش حجم و زمان همگانی"), create_button("🔐 قفل چنل ها")],
    [create_button("📝 مدیریت لاگ‌ها")],
    [create_button("📝 متن‌های ربات"), create_button("⌨️ مدیریت دکمه‌های کیبورد")],
    [create_button("🔗 لینک های آماده")],
    [create_button("🈸 آپدیت برنامه ها")],
    [create_button("🏠")],
]

BT_takhfifList = [
    [create_button("🎛 لیست کدتخفیف"), create_button("🪄 ساخت کدتخفیف")],
    [create_button("🔙 بازگشت به پنل")],
]

panel_xui_buttons = [
    [create_button("📉 وضعیت پنل ها"), create_button("▫️ افزودن پنل جدید")],
    [create_button("🔙 بازگشت به پنل")],
]


panel_back = [[create_button("🔙 بازگشت به پنل")]]

Home_Back = [[create_button("🏠")]]
