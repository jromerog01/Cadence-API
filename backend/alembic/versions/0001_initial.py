"""initial schema: users, jobs, segments

Revision ID: 0001
Revises:
Create Date: 2026-09-06

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql
from sqlalchemy.dialects.postgresql import CITEXT

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

DEFAULT_USER_ID = "00000000-0000-0000-0000-000000000001"


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS citext")

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("email", CITEXT(), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(), nullable=True),
        sa.Column("display_name", sa.String(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )

    op.create_table(
        "jobs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "owner_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id"),
            nullable=False,
        ),
        sa.Column("original_filename", sa.String(), nullable=False),
        sa.Column("stored_path", sa.String(), nullable=False),
        sa.Column("mime_type", sa.String(), nullable=True),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False),
        sa.Column("duration_seconds", sa.Numeric(), nullable=True),
        sa.Column("model", sa.String(), nullable=False),
        sa.Column("language", sa.String(), nullable=True),
        sa.Column("detected_language", sa.String(), nullable=True),
        sa.Column("diarize", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("status", sa.String(), nullable=False, server_default="queued"),
        sa.Column("progress", sa.Numeric(), nullable=False, server_default="0"),
        sa.Column("stage", sa.String(), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column("started_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("finished_at", sa.TIMESTAMP(timezone=True), nullable=True),
    )
    op.create_check_constraint(
        "jobs_status_check",
        "jobs",
        "status IN ('queued','processing','done','error')",
    )
    op.create_check_constraint(
        "jobs_stage_check",
        "jobs",
        "stage IS NULL OR stage IN ('normalizing','transcribing','diarizing')",
    )
    op.create_index("ix_jobs_owner_created", "jobs", ["owner_id", "created_at"])

    op.create_table(
        "segments",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column(
            "job_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("jobs.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("idx", sa.Integer(), nullable=False),
        sa.Column("start_seconds", sa.Numeric(), nullable=False),
        sa.Column("end_seconds", sa.Numeric(), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("speaker", sa.String(), nullable=True),
    )
    op.create_index("ix_segments_job_idx", "segments", ["job_id", "idx"])

    op.execute(
        "INSERT INTO users (id, email, display_name, is_active) VALUES "
        f"('{DEFAULT_USER_ID}', 'default@cadence.local', 'default', true)"
    )


def downgrade() -> None:
    op.drop_table("segments")
    op.drop_table("jobs")
    op.drop_table("users")
    op.execute("DROP EXTENSION IF EXISTS citext")
