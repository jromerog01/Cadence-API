from fastapi import APIRouter
from sqlalchemy import text

from adapters.db import get_engine
from api.deps import get_redis

router = APIRouter()


@router.get("/health")
def health():
    postgres_ok = False
    redis_ok = False

    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
        postgres_ok = True
    except Exception:
        postgres_ok = False

    try:
        redis_ok = bool(get_redis().ping())
    except Exception:
        redis_ok = False

    return {
        "status": "ok" if postgres_ok and redis_ok else "degraded",
        "postgres": postgres_ok,
        "redis": redis_ok,
    }
