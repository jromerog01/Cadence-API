from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import func, insert, select
from sqlalchemy.orm import Session

from adapters.orm_models import JobRow, SegmentRow, UserRow
from domain.models import Job, Segment, User


def _user_from_row(row: UserRow) -> User:
    return User(
        id=row.id,
        email=row.email,
        password_hash=row.password_hash,
        display_name=row.display_name,
        is_active=row.is_active,
    )


class PostgresUserRepository:
    def __init__(self, session: Session):
        self._session = session

    def get_by_email(self, email: str) -> User | None:
        stmt = select(UserRow).where(UserRow.email == email)
        row = self._session.execute(stmt).scalar_one_or_none()
        return _user_from_row(row) if row else None

    def get_by_id(self, user_id: UUID) -> User | None:
        row = self._session.get(UserRow, user_id)
        return _user_from_row(row) if row else None

    def upsert_user(self, *, email: str, password_hash: str, display_name: str) -> User:
        stmt = select(UserRow).where(UserRow.email == email)
        row = self._session.execute(stmt).scalar_one_or_none()
        if row is None:
            row = UserRow(
                id=uuid4(), email=email, password_hash=password_hash,
                display_name=display_name, is_active=True,
            )
            self._session.add(row)
        else:
            row.password_hash = password_hash
            row.display_name = display_name
        self._session.commit()
        self._session.refresh(row)
        return _user_from_row(row)


def _job_from_row(row: JobRow, segments: list[Segment] | None = None) -> Job:
    return Job(
        id=row.id,
        owner_id=row.owner_id,
        original_filename=row.original_filename,
        stored_path=row.stored_path,
        mime_type=row.mime_type,
        size_bytes=row.size_bytes,
        model=row.model,
        status=row.status,
        progress=float(row.progress),
        stage=row.stage,
        language=row.language,
        detected_language=row.detected_language,
        diarize=row.diarize,
        duration_seconds=float(row.duration_seconds) if row.duration_seconds is not None else None,
        error_message=row.error_message,
        created_at=row.created_at,
        started_at=row.started_at,
        finished_at=row.finished_at,
        segments=segments or [],
    )


class PostgresJobRepository:
    def __init__(self, session: Session):
        self._session = session

    def create_job(self, **fields) -> Job:
        row = JobRow(**fields)
        self._session.add(row)
        self._session.commit()
        self._session.refresh(row)
        return _job_from_row(row)

    def get_job(self, job_id: UUID, *, include_segments: bool = True) -> Job | None:
        row = self._session.get(JobRow, job_id)
        if row is None:
            return None
        segments = self.list_segments(job_id) if include_segments else []
        return _job_from_row(row, segments)

    def list_jobs(self, owner_id: UUID, *, limit: int, offset: int) -> list[Job]:
        stmt = (
            select(JobRow)
            .where(JobRow.owner_id == owner_id)
            .order_by(JobRow.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        rows = self._session.execute(stmt).scalars().all()
        return [_job_from_row(row) for row in rows]

    def update_job(self, job_id: UUID, **fields) -> None:
        row = self._session.get(JobRow, job_id)
        if row is None:
            return
        for key, value in fields.items():
            setattr(row, key, value)
        self._session.commit()

    def insert_segments(self, job_id: UUID, segments: list[Segment]) -> None:
        if not segments:
            return
        self._session.execute(
            insert(SegmentRow),
            [
                {
                    "job_id": job_id,
                    "idx": s.idx,
                    "start_seconds": s.start_seconds,
                    "end_seconds": s.end_seconds,
                    "text": s.text,
                    "speaker": s.speaker,
                }
                for s in segments
            ],
        )
        self._session.commit()

    def list_finished_jobs_before(self, cutoff: datetime) -> list[Job]:
        stmt = select(JobRow).where(JobRow.status == "done", JobRow.created_at < cutoff)
        rows = self._session.execute(stmt).scalars().all()
        return [_job_from_row(row) for row in rows]

    def count_active_jobs(self) -> int:
        stmt = select(func.count()).select_from(JobRow).where(
            JobRow.status.in_(["queued", "processing"])
        )
        return self._session.execute(stmt).scalar_one()

    def list_segments(self, job_id: UUID) -> list[Segment]:
        stmt = (
            select(SegmentRow)
            .where(SegmentRow.job_id == job_id)
            .order_by(SegmentRow.idx)
        )
        rows = self._session.execute(stmt).scalars().all()
        return [
            Segment(
                idx=row.idx,
                start_seconds=float(row.start_seconds),
                end_seconds=float(row.end_seconds),
                text=row.text,
                speaker=row.speaker,
            )
            for row in rows
        ]
