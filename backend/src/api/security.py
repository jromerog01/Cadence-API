import os
from datetime import datetime, timedelta, timezone
from uuid import UUID

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from fastapi import Response

COOKIE_NAME = "cadence_session"
SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 30  # 30 days

# Secure=True requires HTTPS; set COOKIE_SECURE=false only for local dev
# over plain http://localhost, never in production (browsers won't store
# a Secure cookie over plain HTTP anyway, so this only affects that case).
COOKIE_SECURE = os.environ.get("COOKIE_SECURE", "true").lower() == "true"

_hasher = PasswordHasher()


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except VerifyMismatchError:
        return False


def _jwt_secret() -> str:
    return os.environ["SESSION_SECRET"]


def create_session_token(user_id: UUID) -> str:
    payload = {
        "sub": str(user_id),
        "exp": datetime.now(timezone.utc) + timedelta(seconds=SESSION_MAX_AGE_SECONDS),
    }
    return jwt.encode(payload, _jwt_secret(), algorithm="HS256")


def decode_session_token(token: str) -> UUID | None:
    try:
        payload = jwt.decode(token, _jwt_secret(), algorithms=["HS256"])
        return UUID(payload["sub"])
    except (jwt.InvalidTokenError, KeyError, ValueError):
        return None


def set_session_cookie(response: Response, token: str) -> None:
    response.set_cookie(
        COOKIE_NAME,
        token,
        max_age=SESSION_MAX_AGE_SECONDS,
        httponly=True,
        secure=COOKIE_SECURE,
        samesite="lax",
        path="/",
    )


def clear_session_cookie(response: Response) -> None:
    response.delete_cookie(COOKIE_NAME, path="/")
