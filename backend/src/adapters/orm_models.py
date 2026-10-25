import uuid

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import CITEXT, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class UserRow(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    email: Mapped[str] = mapped_column(CITEXT(), unique=True, nullable=False)
    password_hash: Mapped[str | None] = mapped_column(String(), nullable=True)
    display_name: Mapped[str] = mapped_column(String(), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean(), nullable=False, server_default="true")
    created_at: Mapped[object] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class JobRow(Base):
    __tablename__ = "jobs"
    __table_args__ = (
        CheckConstraint("status IN ('queued','processing','done','error')", name="jobs_status_check"),
        CheckConstraint(
            "stage IS NULL OR stage IN ('normalizing','transcribing','diarizing')",
            name="jobs_stage_check",
        ),
        Index("ix_jobs_owner_created", "owner_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    owner_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    original_filename: Mapped[str] = mapped_column(String(), nullable=False)
    stored_path: Mapped[str | None] = mapped_column(String(), nullable=True)
    mime_type: Mapped[str | None] = mapped_column(String(), nullable=True)
    size_bytes: Mapped[int | None] = mapped_column(BigInteger(), nullable=True)
    duration_seconds: Mapped[float | None] = mapped_column(Numeric(), nullable=True)
    model: Mapped[str] = mapped_column(String(), nullable=False)
    language: Mapped[str | None] = mapped_column(String(), nullable=True)
    detected_language: Mapped[str | None] = mapped_column(String(), nullable=True)
    diarize: Mapped[bool] = mapped_column(Boolean(), nullable=False, server_default="false")
    status: Mapped[str] = mapped_column(String(), nullable=False, server_default="queued")
    progress: Mapped[float] = mapped_column(Numeric(), nullable=False, server_default="0")
    stage: Mapped[str | None] = mapped_column(String(), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text(), nullable=True)
    word_count: Mapped[int | None] = mapped_column(nullable=True)
    created_at: Mapped[object] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    started_at: Mapped[object | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[object | None] = mapped_column(DateTime(timezone=True), nullable=True)


class SegmentRow(Base):
    __tablename__ = "segments"
    __table_args__ = (Index("ix_segments_job_idx", "job_id", "idx"),)

    id: Mapped[int] = mapped_column(BigInteger(), primary_key=True, autoincrement=True)
    job_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("jobs.id", ondelete="CASCADE"), nullable=False
    )
    idx: Mapped[int] = mapped_column(nullable=False)
    start_seconds: Mapped[float] = mapped_column(Numeric(), nullable=False)
    end_seconds: Mapped[float] = mapped_column(Numeric(), nullable=False)
    text: Mapped[str] = mapped_column(Text(), nullable=False)
    speaker: Mapped[str | None] = mapped_column(String(), nullable=True)
