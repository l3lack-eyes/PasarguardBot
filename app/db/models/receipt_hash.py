from sqlalchemy import BigInteger, Column, String

from app.db.base import Base


class ReceiptHash(Base):
    __tablename__ = "receipt_hashes"

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    phash = Column(String(64), nullable=False, unique=True, index=True)
    transaction_id = Column(BigInteger, nullable=True)
    user_id = Column(BigInteger, nullable=False)
    created_at = Column(BigInteger, nullable=False)
