import os
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID

from adapters.db import new_session
from adapters.postgres_repo import PostgresJobRepository
from adapters.whisper_engine import WhisperEngine
from domain.models import Segment

BATCH_SIZE = 20

_engine_cache: WhisperEngine | None = None


def _get_engine(model_size: str) -> WhisperEngine:
    global _engine_cache
    if _engine_cache is None or _engine_cache.model_size != model_size:
        _engine_cache = WhisperEngine(
            model_size=model_size,
            cpu_threads=int(os.environ.get("WHISPER_CPU_THREADS", "4")),
            download_root=os.environ.get("WHISPER_MODEL_CACHE_DIR", "/models"),
        )
    return _engine_cache


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def transcribe_job(job_id: str) -> None:
    session = new_session()
    repo = PostgresJobRepository(session)
    job = repo.get_job(UUID(job_id))
    if job is None:
        session.close()
        return

    repo.update_job(job.id, status="processing", stage="transcribing", started_at=_utcnow())
    try:
        engine = _get_engine(job.model)
        info, segments = engine.transcribe(Path(job.stored_path), language=job.language)
        repo.update_job(job.id, duration_seconds=info.duration_seconds)

        batch: list[Segment] = []
        for seg in segments:
            batch.append(seg)
            if len(batch) >= BATCH_SIZE:
                repo.insert_segments(job.id, batch)
                if info.duration_seconds:
                    progress = min(batch[-1].end_seconds / info.duration_seconds, 1.0)
                    repo.update_job(job.id, progress=progress)
                batch = []
        if batch:
            repo.insert_segments(job.id, batch)

        repo.update_job(
            job.id,
            status="done",
            stage=None,
            progress=1.0,
            detected_language=info.detected_language,
            finished_at=_utcnow(),
        )
    except Exception as exc:
        repo.update_job(job.id, status="error", error_message=str(exc), finished_at=_utcnow())
        raise
    finally:
        session.close()
