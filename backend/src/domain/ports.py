from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Protocol
from uuid import UUID

from domain.models import Job, Segment, TranscriptionInfo


class TranscriptionEngine(Protocol):
    def transcribe(
        self, audio_path: Path, *, language: str | None
    ) -> tuple[TranscriptionInfo, Iterator[Segment]]: ...


class JobRepository(Protocol):
    def create_job(self, **fields) -> Job: ...
    def get_job(self, job_id: UUID, *, include_segments: bool = True) -> Job | None: ...
    def list_jobs(self, owner_id: UUID, *, limit: int, offset: int) -> list[Job]: ...
    def update_job(self, job_id: UUID, **fields) -> None: ...
    def insert_segments(self, job_id: UUID, segments: list[Segment]) -> None: ...
    def list_segments(self, job_id: UUID) -> list[Segment]: ...


@dataclass
class AudioInfo:
    duration_seconds: float
    has_audio_stream: bool


class AudioProbe(Protocol):
    def probe(self, path: Path) -> AudioInfo: ...


@dataclass
class SpeakerTurn:
    start_seconds: float
    end_seconds: float
    speaker: str


class Diarizer(Protocol):
    def diarize(self, path: Path) -> list[SpeakerTurn]: ...
