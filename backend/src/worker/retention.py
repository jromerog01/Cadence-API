"""Deletes original audio files older than AUDIO_RETENTION_DAYS, keeping the
transcript (jobs/segments rows untouched — exports read only from the DB).

Disabled by default (AUDIO_RETENTION_DAYS=0). Meant to run on a schedule
outside the container, e.g. a host crontab entry once a day:

    0 3 * * * cd /path/to/cadenceAPI && docker compose exec -T worker \
        python -m worker.retention

Run manually to test: `docker compose exec worker python -m worker.retention`
"""

import logging
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

from adapters.db import new_session
from adapters.logging_config import configure_logging
from adapters.postgres_repo import PostgresJobRepository

logger = logging.getLogger("cadence.retention")


def purge_old_audio(retention_days: int) -> int:
    if retention_days <= 0:
        return 0

    cutoff = datetime.now(timezone.utc) - timedelta(days=retention_days)
    session = new_session()
    purged = 0
    try:
        repo = PostgresJobRepository(session)
        for job in repo.list_finished_jobs_before(cutoff):
            if not job.stored_path:
                continue
            path = Path(job.stored_path)
            if path.exists():
                path.unlink()
                purged += 1
                logger.info("purged audio for job %s (%s)", job.id, path)
    finally:
        session.close()
    return purged


if __name__ == "__main__":
    configure_logging()
    days = int(os.environ.get("AUDIO_RETENTION_DAYS", "0"))
    count = purge_old_audio(days)
    logger.info("purged %d audio file(s) older than %d day(s)", count, days)
