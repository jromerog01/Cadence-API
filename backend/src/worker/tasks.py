import logging
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator
from uuid import UUID

from adapters.db import new_session
from adapters.ffmpeg_probe import normalize_to_wav
from adapters.postgres_repo import PostgresJobRepository
from adapters.whisper_engine import WhisperEngine
from domain.models import Segment

logger = logging.getLogger("cadence.worker")

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


def _consume_segments(
    repo: PostgresJobRepository,
    job_id: UUID,
    segments: Iterator[Segment],
    duration_seconds: float,
) -> int:
    # segments is faster-whisper's lazy generator: the actual transcription
    # work happens as this loop advances, which is why it must run while the
    # normalized audio file (and its temp directory) still exists.
    batch: list[Segment] = []
    word_count = 0
    for seg in segments:
        batch.append(seg)
        word_count += len(seg.text.split())
        if len(batch) >= BATCH_SIZE:
            repo.insert_segments(job_id, batch)
            if duration_seconds:
                progress = min(batch[-1].end_seconds / duration_seconds, 1.0)
                repo.update_job(job_id, progress=progress)
            batch = []
    if batch:
        repo.insert_segments(job_id, batch)
    return word_count


def transcribe_job(job_id: str) -> None:
    session = new_session()
    repo = PostgresJobRepository(session)
    job = repo.get_job(UUID(job_id))
    if job is None:
        session.close()
        return

    logger.info("job started", extra={"job_id": job_id, "model": job.model})
    # A retry (RQ Retry, see job_creation.py) re-runs this from scratch on
    # the same job_id, so clear whatever a previous attempt already wrote.
    repo.clear_segments(job.id)
    repo.update_job(
        job.id, status="processing", stage="normalizing", progress=0.0, started_at=_utcnow()
    )
    try:
        with tempfile.TemporaryDirectory() as tmp_dir:
            normalized_path = Path(tmp_dir) / "normalized.wav"
            normalize_to_wav(Path(job.stored_path), normalized_path)

            repo.update_job(job.id, stage="transcribing")
            engine = _get_engine(job.model)
            info, segments = engine.transcribe(normalized_path, language=job.language)
            repo.update_job(job.id, duration_seconds=info.duration_seconds)
            word_count = _consume_segments(repo, job.id, segments, info.duration_seconds)

            repo.update_job(
                job.id,
                status="done",
                stage=None,
                progress=1.0,
                detected_language=info.detected_language,
                word_count=word_count,
                finished_at=_utcnow(),
            )
            logger.info("job done", extra={"job_id": job_id})
    except Exception as exc:
        logger.exception("job failed", extra={"job_id": job_id})
        # The exception may have left the transaction aborted (e.g. a failed
        # insert), which would make this same update_job call fail too and
        # leave the job stuck in "processing" forever.
        session.rollback()
        repo.update_job(job.id, status="error", error_message=str(exc), finished_at=_utcnow())
        raise
    finally:
        session.close()
