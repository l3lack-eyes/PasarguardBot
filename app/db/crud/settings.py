from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.future import select

from app.db.base import AsyncSessionLocal as Session
from app.db.models.settings import Settings
from app.logger import get_logger

log = get_logger(__name__)


class SettingsManager:
    async def get_settings(self):
        try:
            async with Session() as session:
                result = await session.execute(select(Settings))
                return result.scalars().one_or_none()
        except SQLAlchemyError as e:
            log.error("Error retrieving settings", exc_info=e)
            return None

    async def add_default_settings(self):
        try:
            async with Session() as session:
                result = await session.execute(select(Settings))
                if result.scalars().one_or_none() is None:
                    default_settings = Settings(
                        bot_mode=True,
                        sale_mode=False,
                        extension_mode=False,
                        test_mode=False,
                        test_panel_id=0,
                        pay_mode=False,
                        ip_mode=False,
                        arz_mode=False,
                        upg_mode=False,
                        tamdid_mode=False,
                        qr_mode=False,
                        other_links_mode=False,
                        sub_mode=False,
                        change_link_mode=False,
                        copy_link_mode=False,
                        transfer_config_mode=False,
                        info_mode=False,
                        client_list_mode=False,
                        usage_chart_mode=False,
                        del_service_mode=False,
                        channel_lock=False,
                        arz_usd=0,
                        arz_trx=0,
                        arz_ton=0,
                        manual_auto_confirm=False,
                        manual_card_random_mode=False,
                        manual_deposit_min=5000,
                        manual_deposit_max=2000000,
                        crypto_deposit_min=50000,
                        crypto_deposit_max=10000000,
                        manual_bonus_enabled=False,
                        manual_bonus_percent=0,
                        crypto_bonus_enabled=False,
                        crypto_bonus_percent=0,
                    )
                    session.add(default_settings)
                    await session.commit()
        except SQLAlchemyError as e:
            log.error("Error adding default settings", exc_info=e)

    async def add_setting(self, **kwargs):
        try:
            async with Session() as session:
                new_setting = Settings(**kwargs)
                session.add(new_setting)
                await session.commit()
                return new_setting
        except SQLAlchemyError as e:
            log.error("Error adding setting", exc_info=e)
            return None

    async def get_setting_by_id(self, setting_id):
        try:
            async with Session() as session:
                result = await session.execute(select(Settings).filter_by(id=setting_id))
                return result.scalars().first()
        except SQLAlchemyError as e:
            log.error("Error retrieving setting", exc_info=e)
            return None

    async def get_all_settings(self):
        try:
            async with Session() as session:
                result = await session.execute(select(Settings))
                return result.scalars().all()
        except SQLAlchemyError as e:
            log.error("Error retrieving settings", exc_info=e)
            return None

    async def update_setting(self, setting_id, **kwargs):
        try:
            async with Session() as session:
                result = await session.execute(select(Settings).filter_by(id=setting_id))
                setting = result.scalars().first()
                if setting:
                    for key, value in kwargs.items():
                        if hasattr(setting, key):
                            setattr(setting, key, value)
                    await session.commit()
                    return setting
            return None
        except SQLAlchemyError as e:
            log.error("Error updating setting", exc_info=e)
            return None

    async def delete_setting(self, setting_id):
        try:
            async with Session() as session:
                result = await session.execute(select(Settings).filter_by(id=setting_id))
                setting = result.scalars().first()
                if setting:
                    await session.delete(setting)
                    await session.commit()
                    return True
            return False
        except SQLAlchemyError as e:
            log.error("Error deleting setting", exc_info=e)
            return False

    async def toggle_mode(self, setting_id, mode_name):
        try:
            async with Session() as session:
                result = await session.execute(select(Settings).filter_by(id=setting_id))
                setting = result.scalars().first()
                if setting and hasattr(setting, mode_name):
                    current_value = getattr(setting, mode_name)
                    setattr(setting, mode_name, not current_value)
                    await session.commit()
                    return setting
            return None
        except SQLAlchemyError as e:
            log.error("Error toggling mode", exc_info=e)
            return None

    async def update_setting_by_name(self, setting_name, value):
        try:
            async with Session() as session:
                result = await session.execute(select(Settings))
                setting = result.scalars().first()
                if setting and hasattr(setting, setting_name):
                    setattr(setting, setting_name, value)
                    await session.commit()
                    return setting
            return None
        except SQLAlchemyError as e:
            log.error("Error updating setting by name", exc_info=e)
            return None
