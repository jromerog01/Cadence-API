"""Allow completed text-only jobs imported from a device."""
from alembic import op
import sqlalchemy as sa

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column("jobs", "stored_path", existing_type=sa.String(), nullable=True)
    op.alter_column("jobs", "size_bytes", existing_type=sa.BigInteger(), nullable=True)


def downgrade() -> None:
    # Preserve imported transcripts when reverting to the older schema.
    op.execute("UPDATE jobs SET stored_path = '' WHERE stored_path IS NULL")
    op.execute("UPDATE jobs SET size_bytes = 0 WHERE size_bytes IS NULL")
    op.alter_column("jobs", "stored_path", existing_type=sa.String(), nullable=False)
    op.alter_column("jobs", "size_bytes", existing_type=sa.BigInteger(), nullable=False)
