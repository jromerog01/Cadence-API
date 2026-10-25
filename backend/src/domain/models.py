from dataclasses import dataclass, field
from datetime import datetime
from uuid import UUID

VALID_STATUSES = ("queued", "processing", "done", "error")
VALID_STAGES = ("normalizing", "transcribing", "diarizing")


@dataclass
class Segment:
    idx: int
    start_seconds: float
    end_seconds: float
    text: str
    speaker: str | None = None


@dataclass
class TranscriptionInfo:
    detected_language: str
    duration_seconds: float


@dataclass
class User:
    id: UUID
    email: str
    password_hash: str | None
    display_name: str
    is_active: bool = True


@dataclass
class Job:
    id: UUID
    owner_id: UUID
    original_filename: str
    stored_path: str | None
    mime_type: str | None
    size_bytes: int | None
    model: str
    status: str = "queued"
    progress: float = 0.0
    stage: str | None = None
    language: str | None = None
    detected_language: str | None = None
    diarize: bool = False
    duration_seconds: float | None = None
    error_message: str | None = None
    word_count: int | None = None
    created_at: datetime | None = None
    started_at: datetime | None = None
    finished_at: datetime | None = None
    segments: list[Segment] = field(default_factory=list)
