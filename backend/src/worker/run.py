"""Worker entrypoint (replaces the bare `rq worker` CLI) so we can
reconcile jobs left in "processing" by a previous crash before taking new
work — otherwise they'd stay stuck in "processing" forever, since RQ has
no record of them once the process that was running them is gone."""

import logging
import os

from redis import Redis
from rq import Worker

from adapters.db import new_session
from adapters.logging_config import configure_logging
from adapters.postgres_repo import PostgresJobRepository

logger = logging.getLogger("cadence.worker")


def reconcile_stuck_jobs() -> None:
    session = new_session()
    try:
        repo = PostgresJobRepository(session)
        count = repo.mark_stuck_processing_as_error(
            "El worker se reinició mientras este trabajo estaba en proceso"
        )
        if count:
            logger.warning("marked stuck jobs as error", extra={"count": count})
    finally:
        session.close()


def main() -> None:
    configure_logging()
    reconcile_stuck_jobs()
    connection = Redis.from_url(os.environ["REDIS_URL"])
    worker = Worker(["transcriptions"], connection=connection)
    # with_scheduler=True: without it, a job scheduled for retry (see
    # job_creation.py's Retry(...)) sits in the scheduled registry forever
    # and never actually re-runs — RQ's scheduler is what promotes it back
    # onto the queue once its retry delay elapses.
    worker.work(with_scheduler=True)


if __name__ == "__main__":
    main()
