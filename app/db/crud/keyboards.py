from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.future import select

from app.db.base import AsyncSessionLocal as Session
from app.db.models.keyboards import KeyboardButton


class KeyboardButtonCRUD:
    async def get_button_text(self, button_key: str) -> str | None:

        try:
            async with Session() as session:
                stmt = select(KeyboardButton).where(KeyboardButton.button_key == button_key)
                result = await session.execute(stmt)
                row = result.scalars().first()
                return row.button_text if row else None
        except SQLAlchemyError:
            return None

    async def get_button(self, button_key: str) -> KeyboardButton | None:

        try:
            async with Session() as session:
                stmt = select(KeyboardButton).where(KeyboardButton.button_key == button_key)
                result = await session.execute(stmt)
                return result.scalars().first()
        except SQLAlchemyError:
            return None

    async def set_button(
        self,
        button_key: str,
        *,
        button_text: str | None = None,
        description: str | None = None,
        button_style: str | None = None,
        button_icon: int | None = None,
        clear_icon: bool = False,
    ) -> bool:

        try:
            async with Session() as session:
                stmt = select(KeyboardButton).where(KeyboardButton.button_key == button_key)
                result = await session.execute(stmt)
                existing = result.scalars().first()
                if existing:
                    if button_text is not None:
                        existing.button_text = button_text
                    if description is not None:
                        existing.description = description
                    if button_style is not None:
                        existing.button_style = button_style.strip()
                    if clear_icon or button_icon is not None:
                        existing.button_icon = None if clear_icon else button_icon
                else:
                    if button_text is None:
                        return False
                    session.add(
                        KeyboardButton(
                            button_key=button_key,
                            button_text=button_text,
                            description=description,
                            button_style=button_style.strip() if button_style is not None else None,
                            button_icon=button_icon,
                        )
                    )
                await session.commit()
                return True
        except SQLAlchemyError:
            return False

    async def set_button_text(self, button_key: str, button_text: str, description: str | None = None) -> bool:

        return await self.set_button(button_key, button_text=button_text, description=description)

    async def get_all(self) -> list[KeyboardButton]:

        try:
            async with Session() as session:
                result = await session.execute(select(KeyboardButton))
                return list(result.scalars().all())
        except SQLAlchemyError:
            return []

    async def get_buttons_by_key_prefix(self, prefix: str) -> list[KeyboardButton]:
        try:
            async with Session() as session:
                stmt = select(KeyboardButton).where(KeyboardButton.button_key.like(f"{prefix}%"))
                result = await session.execute(stmt)
                return list(result.scalars().all())
        except SQLAlchemyError:
            return []

    async def delete_button(self, button_key: str) -> bool:

        try:
            async with Session() as session:
                stmt = select(KeyboardButton).where(KeyboardButton.button_key == button_key)
                result = await session.execute(stmt)
                button = result.scalars().first()
                if button:
                    await session.delete(button)
                    await session.commit()
                    return True
                return False
        except SQLAlchemyError:
            return False

    async def initialize_default_buttons(self):

        default_buttons = [
            # Inline MyService
            ("in.ms.change_sub", "🔗 تغییر ساب", "دکمه تغییر ساب"),
            ("in.ms.change_link", "🔗 تغییر لینک", "دکمه تغییر لینک"),
            ("in.ms.copy_link", "🔗 کپی لینک", "دکمه کپی لینک"),
            ("in.ms.info", "⚙️ نمایش اطلاعات بیشتر", "دکمه نمایش اطلاعات بیشتر"),
            ("in.ms.extra_volume", "♾️ حجم اضافه", "دکمه خرید حجم اضافه"),
            ("in.ms.extend_time", "📅 تمدید زمان", "دکمه تمدید زمان"),
            ("in.ms.extend_service", "💎 تمدیدسرویس", "دکمه تمدید سرویس"),
            ("in.ms.qrcode", "🔘 دریافت Qrcode", "دکمه دریافت QR Code"),
            ("in.ms.transfer_config", "🔎 واگذاری کانفیگ", "دکمه واگذاری کانفیگ"),
            ("in.ms.other_links", "➕ نمایش لینک‌های دیگر", "دکمه نمایش لینک‌های دیگر"),
            ("in.ms.show_clients", "🖥 نمایش کلاینت‌ها", "دکمه نمایش کلاینت‌ها"),
            ("in.ms.usage_chart", "📊 نمودار مصرف", "دکمه نمودار مصرف روزانه"),
            ("in.ms.delete_service", "🗑 حذف این کانفیگ برای همیشه", "دکمه حذف کانفیگ"),
            ("in.ms.back_to_services", "بازگشت به لیست سرویس‌ها", "دکمه بازگشت به لیست سرویس‌ها"),
            (
                "in.ms.renew.discount",
                "🎁 کد تخفیف (تمدید)",
                "دکمه کد تخفیف در صفحه تأیید تمدید اکانت (سرویس‌های من)",
            ),
            (
                "in.ms.renew.back",
                "◀️ بازگشت",
                "دکمه بازگشت در صفحه تأیید تمدید اکانت",
            ),
            (
                "in.ms.renew.confirm",
                "💎 تأیید تمدید اکانت",
                "دکمه تأیید نهایی تمدید اکانت",
            ),
            ("in.ms.sub_links.prev", "صفحه قبلی →", "صفحه قبل در لیست لینک‌های ساب"),
            ("in.ms.sub_links.next", "← صفحه بعدی", "صفحه بعد در لیست لینک‌های ساب"),
            (
                "in.ms.sub_links.get_all",
                "📥 دریافت تمام لینک‌های کانفیگ",
                "دریافت یکجا همه لینک‌ها",
            ),
            (
                "in.ms.sub_links.back",
                "بازگشت به قبل",
                "بازگشت از othersSubLinks به جزئیات سرویس",
            ),
            # Home Keyboards
            ("bt.menu_my_services", "🔑 سرویس های من", "دکمه 🔑 سرویس های من"),
            ("bt.menu_get_trial", "🎁 دریافت تست", "دکمه 🎁 دریافت تست"),
            ("bt.menu_buy_service", "🛍 خرید سرویس", "دکمه 🛍 خرید سرویس"),
            ("bt.menu_buy_reseller", "🏢 خرید پنل نمایندگی", "دکمه خرید پنل نمایندگی"),
            ("bt.menu_my_resellers", "📋 نمایندگی‌های من", "دکمه لیست نمایندگی‌های کاربر"),
            ("bt.menu_profile", "🙍 پروفایل من", "دکمه 🙍 پروفایل من"),
            ("bt.menu_add_balance", "💰 افزایش موجودی", "دکمه 💰 افزایش موجودی"),
            ("bt.menu_support", "☎️ پشتیبانی", "دکمه ☎️ پشتیبانی"),
            ("bt.menu_uptime", "🔋 وضعیت سرویس ها", "دکمه 🔋 وضعیت سرویس ها"),
            ("bt.menu_help", "📚 راهنما", "دکمه 📚 راهنما"),
            ("bt.menu_advanced_settings", "⚙️ تنظیمات پیشرفته", "دکمه ⚙️ تنظیمات پیشرفته"),
            ("bt.menu_admin_panel", "⚙️ پنل مدیریت", "دکمه ⚙️ پنل مدیریت"),
            # Balance / charge inline buttons
            ("in.balance.stars", "⭐ پرداخت با استارز", "دکمه پرداخت با استارز"),
            ("in.balance.crypto", "💵 پرداخت ارزی", "دکمه ورود به پرداخت ارزی"),
            ("in.balance.manual", "💳 کارت به کارت (تایید زیر 5 دقیقه)", "دکمه کارت به کارت دستی"),
            ("in.balance.auto", "💷 کارت به کارت خودکار", "دکمه کارت به کارت خودکار"),
            ("in.balance.disabled", "❌ شارژ حساب غیرفعال می‌باشد", "دکمه زمانی که هیچ روش پرداختی فعال نیست"),
            ("in.balance.trx", "💵 پرداخت با TRX (ترون)", "دکمه پرداخت TRX"),
            ("in.balance.usdt", "💵 پرداخت با USDT (تتر)", "دکمه پرداخت USDT"),
            ("in.balance.ton", "💎 پرداخت با TON (تون)", "دکمه پرداخت TON"),
            ("in.balance.crypto_back", "🔙 بازگشت به روش‌های پرداخت", "دکمه بازگشت از منوی ارز به شارژ"),
            ("in.balance.send_receipt", "💰 پرداخت کردم | ارسال رسید واریزی", "دکمه ارسال رسید کارت دستی"),
            (
                "in.balance.flow_cancel",
                "🔙 انصراف · بازگشت به منوی شارژ",
                "دکمه انصراف در مراحل شارژ (کارت، ارز، استارز)",
            ),
            (
                "in.balance.back_home",
                "🏠 بازگشت به منوی اصلی",
                "دکمه بازگشت به منوی اصلی از منوی شارژ",
            ),
            # Buy service inline buttons
            ("in.buy.cancel", "❌ انصراف", "دکمه انصراف در فلو خرید سرویس"),
            ("in.buy.back", "🔙 بازگشت", "دکمه بازگشت در فلو خرید سرویس"),
            ("in.buy.confirm", "✅ تأیید خرید", "دکمه تأیید خرید سرویس/اکانت"),
            ("in.buy.discount", "🎉 اعمال کد تخفیف", "دکمه اعمال کد تخفیف هنگام خرید"),
            ("in.buy.default_username", "🎲 اسم پیشفرض ربات", "دکمه نام کاربری تصادفی هنگام خرید VPN"),
            (
                "in.buy.retry_username",
                "🔄 تغییر مجدد نام کانفیگ",
                "دکمه انتخاب مجدد نام کانفیگ پس از تکراری بودن در پنل",
            ),
            ("in.buy.empty_list", "🚀 خرید اکانت ویتوری", "دکمه خرید وقتی کاربر سرویسی ندارد"),
        ]

        for button_key, button_text, description in default_buttons:
            existing = await self.get_button(button_key)
            if not existing:
                await self.set_button_text(button_key, button_text, description)


async def get_button_text(button_key: str, default: str | None = None) -> str:

    keyboard_crud = KeyboardButtonCRUD()
    text = await keyboard_crud.get_button_text(button_key)
    if text:
        return text

    return default if default is not None else button_key
