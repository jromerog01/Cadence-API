from datetime import datetime

from pydantic import BaseModel, Field, model_validator

from domain.models import Job, Segment


class ImportSegmentIn(BaseModel):
    idx: int = Field(ge=0)
    start_seconds: float = Field(ge=0, allow_inf_nan=False)
    end_seconds: float = Field(ge=0, allow_inf_nan=False)
    text: str = Field(max_length=10000)
    speaker: str | None = Field(default=None, max_length=200)


class ImportJobIn(BaseModel):
    original_filename: str = Field(min_length=1, max_length=255)
    duration_seconds: float | None = Field(default=None, ge=0, allow_inf_nan=False)
    language: str | None = Field(default=None, max_length=32)
    model: str = Field(default="apple-speech", min_length=1, max_length=100)
    segments: list[ImportSegmentIn] = Field(max_length=20000)

    @model_validator(mode="after")
    def validate_timeline(self):
        previous_end = 0.0
        total_characters = 0
        for index, segment in enumerate(self.segments):
            if segment.idx != index or segment.start_seconds < previous_end or segment.end_seconds < segment.start_seconds:
                raise ValueError("Los segmentos deben estar ordenados, sin solaparse y con índices consecutivos")
            if self.duration_seconds is not None and segment.end_seconds > self.duration_seconds + 0.01:
                raise ValueError("Los segmentos exceden la duración del audio")
            previous_end = segment.end_seconds
            total_characters += len(segment.text)
        if total_characters > 2_000_000:
            raise ValueError("La transcripción supera el límite de texto")
        return self


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
