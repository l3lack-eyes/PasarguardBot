from sqlalchemy import BigInteger, Column, String

from app.db.base import Base


class CryptoPayments(Base):
    __tablename__ = "cryptopayments"

    order_id = Column(BigInteger, primary_key=True)
    status = Column(String(50), default="Pending")
    user_id = Column(BigInteger, nullable=False)
    arz = Column(String(20), nullable=True)
    amount = Column(String(50), nullable=False)
    amount_irt = Column(BigInteger, nullable=False)
    paytime = Column(BigInteger, default=0)
    createtime = Column(BigInteger, nullable=False)
    msg_id = Column(BigInteger, nullable=True)
