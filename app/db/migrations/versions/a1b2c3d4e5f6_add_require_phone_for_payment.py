"""add require_phone_for_payment to settings

Revision ID: a1b2c3d4e5f6
Revises: b96b89b8f07d
Create Date: 2026-07-21 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = 'b96b89b8f07d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'settings',
        sa.Column(
            'require_phone_for_payment',
            sa.Boolean(),
            server_default=sa.text('1'),
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_column('settings', 'require_phone_for_payment')
