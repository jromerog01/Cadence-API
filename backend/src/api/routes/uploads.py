import json
import math
import shutil
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from rq import Queue

from adapters.ffmpeg_probe import FfmpegAudioProbe
from adapters.postgres_repo import PostgresJobRepository
from api.deps import get_audio_probe, get_current_user, get_queue, get_repo
from api.job_creation import (
    ALLOWED_EXTENSIONS,
    MAX_UPLOAD_BYTES,
    check_concurrency_limit,
    finalize_job,
    storage_dir,
)
from api.schemas import JobOut
from domain.models import User

router = APIRouter()

CHUNK_SIZE_BYTES = 8 * 1024 * 1024


def _uploads_root() -> Path:
    path = storage_dir() / "uploads"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _session_dir(upload_id: str) -> Path:
    return _uploads_root() / upload_id


def _read_meta(session_dir: Path) -> dict:
    meta_path = session_dir / "meta.json"
    if not meta_path.exists():
        raise HTTPException(404, "Sesión de subida no encontrada")
    return json.loads(meta_path.read_text())


class InitUploadIn(BaseModel):
    filename: str
    size_bytes: int
    model: str | None = None
    language: str | None = None


class InitUploadOut(BaseModel):
    upload_id: str
    chunk_size: int
    total_parts: int


class UploadStatusOut(BaseModel):
    total_parts: int
    received: list[int]


@router.post("", response_model=InitUploadOut)
def init_upload(
    payload: InitUploadIn,
    current_user: User = Depends(get_current_user),
    repo: PostgresJobRepository = Depends(get_repo),
):
    ext = Path(payload.filename).suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Formato no soportado: {ext or 'desconocido'}")
    if payload.size_bytes <= 0 or payload.size_bytes > MAX_UPLOAD_BYTES:
        raise HTTPException(
            413, f"El archivo debe ser mayor a 0 y hasta {MAX_UPLOAD_BYTES // (1024 * 1024)} MB"
        )

    check_concurrency_limit(repo)

    upload_id = str(uuid.uuid4())
    session_dir = _session_dir(upload_id)
    session_dir.mkdir(parents=True)
    total_parts = math.ceil(payload.size_bytes / CHUNK_SIZE_BYTES)

    meta = {
        "owner_id": str(current_user.id),
        "filename": payload.filename,
        "ext": ext,
        "size_bytes": payload.size_bytes,
        "total_parts": total_parts,
        "model": payload.model,
        "language": payload.language,
    }
    (session_dir / "meta.json").write_text(json.dumps(meta))

    return InitUploadOut(upload_id=upload_id, chunk_size=CHUNK_SIZE_BYTES, total_parts=total_parts)


def _check_owner(meta: dict, current_user: User) -> None:
    if meta.get("owner_id") != str(current_user.id):
        raise HTTPException(404, "Sesión de subida no encontrada")


@router.get("/{upload_id}", response_model=UploadStatusOut)
def upload_status(upload_id: uuid.UUID, current_user: User = Depends(get_current_user)):
    session_dir = _session_dir(str(upload_id))
    meta = _read_meta(session_dir)
    _check_owner(meta, current_user)
    received = sorted(
        int(path.name.removeprefix("part-"))
        for path in session_dir.glob("part-?????")
        if path.name.removeprefix("part-").isdigit()
        and int(path.name.removeprefix("part-")) < meta["total_parts"]
    )
    return UploadStatusOut(total_parts=meta["total_parts"], received=received)


@router.put("/{upload_id}/parts/{part_number}")
async def upload_part(
    upload_id: str,
    part_number: int,
    request: Request,
    current_user: User = Depends(get_current_user),
):
    session_dir = _session_dir(upload_id)
    meta = _read_meta(session_dir)
    _check_owner(meta, current_user)

    if not (0 <= part_number < meta["total_parts"]):
        raise HTTPException(400, "Número de parte fuera de rango")

    body = await request.body()
    (session_dir / f"part-{part_number:05d}").write_bytes(body)
    return {"received": part_number}


@router.post("/{upload_id}/complete", response_model=JobOut)
def complete_upload(
    upload_id: str,
    current_user: User = Depends(get_current_user),
    repo: PostgresJobRepository = Depends(get_repo),
    queue: Queue = Depends(get_queue),
    probe: FfmpegAudioProbe = Depends(get_audio_probe),
):
    session_dir = _session_dir(upload_id)
    meta = _read_meta(session_dir)
    _check_owner(meta, current_user)

    missing = [
        n for n in range(meta["total_parts"]) if not (session_dir / f"part-{n:05d}").exists()
    ]
    if missing:
        raise HTTPException(409, f"Faltan {len(missing)} de {meta['total_parts']} partes")

    job_id = uuid.uuid4()
    dest = storage_dir() / f"{job_id}{meta['ext']}"
    size_bytes = 0
    with dest.open("wb") as out:
        for n in range(meta["total_parts"]):
            chunk = (session_dir / f"part-{n:05d}").read_bytes()
            size_bytes += len(chunk)
            out.write(chunk)

    shutil.rmtree(session_dir, ignore_errors=True)

    if size_bytes != meta["size_bytes"]:
        dest.unlink(missing_ok=True)
        raise HTTPException(400, "El tamaño ensamblado no coincide con el declarado")

    return finalize_job(
        job_id=job_id,
        owner_id=current_user.id,
        original_filename=meta["filename"],
        dest=dest,
        mime_type=None,
        size_bytes=size_bytes,
        model=meta.get("model"),
        language=meta.get("language"),
        repo=repo,
        queue=queue,
        probe=probe,
    )
