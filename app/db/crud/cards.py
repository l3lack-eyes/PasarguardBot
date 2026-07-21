from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.future import select

from app.db.base import AsyncSessionLocal as Session
from app.db.models.manual_card import ManualCard


class ManualCardManager:
    async def add_card(self, number: str, name: str, active: bool = False):
        async with Session() as session:
            try:
                if active:
                    result = await session.execute(select(ManualCard))
                    for card in result.scalars().all():
                        card.active = False
                new_card = ManualCard(number=number, name=name, active=active)
                session.add(new_card)
                await session.commit()
                return new_card
            except SQLAlchemyError:
                await session.rollback()
                return None

    async def get_all_cards(self):
        async with Session() as session:
            result = await session.execute(select(ManualCard))
            return result.scalars().all()

    async def get_card(self, card_id: int):
        async with Session() as session:
            result = await session.execute(select(ManualCard).filter_by(id=card_id))
            return result.scalars().first()

    async def set_active(self, card_id: int):
        async with Session() as session:
            result = await session.execute(select(ManualCard))
            cards = result.scalars().all()
            target = None
            for card in cards:
                if card.id == card_id:
                    target = card
                    card.active = True
                else:
                    card.active = False
            await session.commit()
            return target

    async def delete_card(self, card_id: int):
        async with Session() as session:
            result = await session.execute(select(ManualCard).filter_by(id=card_id))
            card = result.scalars().first()
            if card:
                await session.delete(card)
                await session.commit()
                return True
            return False
