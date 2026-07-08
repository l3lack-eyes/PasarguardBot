from sqlalchemy import BigInteger, Integer, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Settings(Base):
    __tablename__ = "settings"

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer, "sqlite"),
        primary_key=True,
        autoincrement=True,
    )
    bot_mode: Mapped[bool] = mapped_column(default=True, server_default=text("1"))
    sale_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    single_panel_buy_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    extension_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    test_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    test_panel_id: Mapped[int] = mapped_column(BigInteger, default=0, server_default=text("0"))
    test_phone_verify: Mapped[bool] = mapped_column(default=True, server_default=text("1"))
    pay_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    ip_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    arz_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    upg_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    tamdid_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    qr_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    other_links_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    sub_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    change_link_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    copy_link_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    transfer_config_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    info_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    client_list_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    usage_chart_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    del_service_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    channel_lock: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    arz_usd: Mapped[int | None] = mapped_column(BigInteger, server_default=text("0"))
    arz_trx: Mapped[int | None] = mapped_column(BigInteger, server_default=text("0"))
    arz_ton: Mapped[int | None] = mapped_column(BigInteger, server_default=text("0"))
    manual_auto_confirm: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    manual_card_random_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    manual_deposit_min: Mapped[int | None] = mapped_column(BigInteger, nullable=False, server_default=text("50000"))
    manual_deposit_max: Mapped[int | None] = mapped_column(BigInteger, nullable=False, server_default=text("2000000"))
    crypto_deposit_min: Mapped[int | None] = mapped_column(BigInteger, nullable=False, server_default=text("50000"))
    crypto_deposit_max: Mapped[int | None] = mapped_column(BigInteger, nullable=False, server_default=text("10000000"))
    manual_bonus_enabled: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    manual_bonus_percent: Mapped[int | None] = mapped_column(Integer, nullable=False, server_default=text("0"))
    crypto_bonus_enabled: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    crypto_bonus_percent: Mapped[int | None] = mapped_column(Integer, nullable=False, server_default=text("0"))
    reseller_sale_mode: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    reseller_usage_billing_enabled: Mapped[bool] = mapped_column(default=False, server_default=text("0"))
    reseller_min_wallet_balance: Mapped[int | None] = mapped_column(
        BigInteger, nullable=False, server_default=text("100000")
    )
