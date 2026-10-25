import os
from typing import Iterator

import redis
from fastapi import Depends, HTTPException, Request
from redis import Redis
from rq import Queue
from sqlalchemy.orm import Session

from adapters.db import new_session
from adapters.ffmpeg_probe import FfmpegAudioProbe
from adapters.postgres_repo import PostgresJobRepository, PostgresUserRepository
from api.security import COOKIE_NAME, decode_session_token
from domain.models import User

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


def get_user_repo(session: Session = Depends(get_db_session)) -> PostgresUserRepository:
    return PostgresUserRepository(session)


def get_current_user(
    request: Request,
    user_repo: PostgresUserRepository = Depends(get_user_repo),
) -> User:
    authorization = request.headers.get("authorization", "")
    if authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
    else:
        token = request.cookies.get(COOKIE_NAME)
    user_id = decode_session_token(token) if token else None
    user = user_repo.get_by_id(user_id) if user_id else None
    if user is None or not user.is_active:
        raise HTTPException(401, "No autenticado")
    return user
