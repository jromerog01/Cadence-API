import os
from typing import Iterator

import redis
from fastapi import Depends
from redis import Redis
from rq import Queue
from sqlalchemy.orm import Session

from adapters.db import new_session
from adapters.ffmpeg_probe import FfmpegAudioProbe
from adapters.postgres_repo import PostgresJobRepository

_redis_conn: Redis | None = None


def get_redis() -> Redis:
    global _redis_conn
    if _redis_conn is None:
        _redis_conn = redis.from_url(os.environ["REDIS_URL"])
    return _redis_conn


def get_db_session() -> Iterator[Session]:
    session = new_session()
    try:
        yield session
    finally:
        session.close()


def get_repo(session: Session = Depends(get_db_session)) -> PostgresJobRepository:
    return PostgresJobRepository(session)


def get_queue() -> Queue:
    return Queue("transcriptions", connection=get_redis())


def get_audio_probe() -> FfmpegAudioProbe:
    return FfmpegAudioProbe()
