from datetime import datetime

from pydantic import BaseModel

from domain.models import Job, Segment


class SegmentOut(BaseModel):
    idx: int
    start_seconds: float
    end_seconds: float
    text: str
    speaker: str | None

    @classmethod
    def from_domain(cls, segment: Segment) -> "SegmentOut":
        return cls(
            idx=segment.idx,
            start_seconds=segment.start_seconds,
            end_seconds=segment.end_seconds,
            text=segment.text,
            speaker=segment.speaker,
        )


class JobOut(BaseModel):
    id: str
    original_filename: str
    duration_seconds: float | None
    model: str
    language: str | None
    detected_language: str | None
    status: str
    progress: float
    stage: str | None
    error_message: str | None
    word_count: int | None
    created_at: datetime
    segments: list[SegmentOut] = []

    @classmethod
    def from_domain(cls, job: Job) -> "JobOut":
        return cls(
            id=str(job.id),
            original_filename=job.original_filename,
            duration_seconds=job.duration_seconds,
            model=job.model,
            language=job.language,
            detected_language=job.detected_language,
            status=job.status,
            progress=job.progress,
            stage=job.stage,
            error_message=job.error_message,
            word_count=job.word_count,
            created_at=job.created_at,
            segments=[SegmentOut.from_domain(s) for s in job.segments],
        )
